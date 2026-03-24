const http = require('http')
const { WebSocketServer } = require('ws')
const { Client } = require('ssh2')
const crypto = require('crypto')
const fs = require('fs')

const PORT = 3002
const SSH_HOST = process.env.SSH_HOST || 'host.docker.internal'
const SSH_USER = process.env.SSH_USER || 'agentos'
const SSH_KEY_PATH = '/ssh-key/id_ed25519'
const JWT_SECRET = process.env.JWT_SECRET || ''
const DASHBOARD_PASSWORD_HASH = process.env.DASHBOARD_PASSWORD_HASH || ''
const IDLE_TIMEOUT = 30 * 60 * 1000 // 30 minutes

function verifySession(cookieHeader) {
  if (!cookieHeader) return false
  const cookies = Object.fromEntries(
    cookieHeader.split(';').map(c => {
      const [k, ...v] = c.trim().split('=')
      return [k, v.join('=')]
    })
  )
  const sessionToken = cookies['dashboard_session']
  if (!sessionToken) return false
  const expected = crypto.createHash('sha256')
    .update(DASHBOARD_PASSWORD_HASH + JWT_SECRET)
    .digest('hex')
  return sessionToken === expected
}

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' })
  res.end('AgentOS Terminal WebSocket Server')
})

const wss = new WebSocketServer({ server })

wss.on('connection', (ws, req) => {
  // Verify authentication
  if (!verifySession(req.headers.cookie)) {
    ws.close(4001, 'Unauthorized')
    return
  }

  console.log(`[${new Date().toISOString()}] Terminal session opened`)

  let sshStream = null
  let idleTimer = null

  const resetIdleTimer = () => {
    if (idleTimer) clearTimeout(idleTimer)
    idleTimer = setTimeout(() => {
      console.log('Idle timeout — closing session')
      ws.close(4002, 'Idle timeout')
    }, IDLE_TIMEOUT)
  }
  resetIdleTimer()

  // Read SSH key
  let privateKey
  try {
    privateKey = fs.readFileSync(SSH_KEY_PATH, 'utf8')
  } catch (err) {
    console.error('Failed to read SSH key:', err.message)
    ws.close(4003, 'SSH key not available')
    return
  }

  // Establish SSH connection
  const ssh = new Client()

  ssh.on('ready', () => {
    ssh.shell({ term: 'xterm-256color', cols: 80, rows: 24 }, (err, stream) => {
      if (err) {
        console.error('SSH shell error:', err.message)
        ws.close(4004, 'SSH shell failed')
        return
      }

      sshStream = stream

      // SSH → WebSocket
      stream.on('data', (data) => {
        resetIdleTimer()
        if (ws.readyState === 1) {
          ws.send(data)
        }
      })

      stream.on('close', () => {
        console.log(`[${new Date().toISOString()}] SSH stream closed`)
        ws.close()
      })

      stream.stderr.on('data', (data) => {
        if (ws.readyState === 1) ws.send(data)
      })
    })
  })

  ssh.on('error', (err) => {
    console.error('SSH error:', err.message)
    ws.close(4005, 'SSH connection failed')
  })

  ssh.connect({
    host: SSH_HOST,
    port: 22,
    username: SSH_USER,
    privateKey,
  })

  // WebSocket → SSH
  ws.on('message', (data) => {
    resetIdleTimer()
    if (!sshStream) return

    const buf = Buffer.from(data)

    // Check for resize command (prefix byte 0x00)
    if (buf.length > 1 && buf[0] === 0) {
      try {
        const dims = JSON.parse(buf.slice(1).toString())
        if (dims.cols && dims.rows) {
          sshStream.setWindow(dims.rows, dims.cols, 0, 0)
        }
      } catch {
        // Not a resize command, treat as regular input
        sshStream.write(buf)
      }
      return
    }

    sshStream.write(buf)
  })

  ws.on('close', () => {
    console.log(`[${new Date().toISOString()}] Terminal session closed`)
    if (idleTimer) clearTimeout(idleTimer)
    ssh.end()
  })

  ws.on('error', (err) => {
    console.error('WebSocket error:', err.message)
    ssh.end()
  })
})

server.listen(PORT, () => {
  console.log(`Terminal WebSocket server listening on port ${PORT}`)
  console.log(`SSH target: ${SSH_USER}@${SSH_HOST}`)
})
