'use client'
import { useState, useEffect, useRef, useCallback } from 'react'

export default function TerminalTab() {
  const termRef = useRef(null)
  const wsRef = useRef(null)
  const xtermRef = useRef(null)
  const fitRef = useRef(null)
  const [status, setStatus] = useState('disconnected')

  const connect = useCallback(async () => {
    if (wsRef.current) return

    setStatus('connecting')

    // Dynamically import xterm (client-side only)
    let Terminal, FitAddon, WebLinksAddon
    try {
      const xtermModule = await import('@xterm/xterm')
      const fitModule = await import('@xterm/addon-fit')
      const linksModule = await import('@xterm/addon-web-links')
      Terminal = xtermModule.Terminal
      FitAddon = fitModule.FitAddon
      WebLinksAddon = linksModule.WebLinksAddon

      // Import CSS
      await import('@xterm/xterm/css/xterm.css')
    } catch (err) {
      setStatus('error: xterm not installed')
      return
    }

    // Create terminal
    const term = new Terminal({
      theme: {
        background: '#0a0a0a',
        foreground: '#c8c8c8',
        cursor: '#00ff41',
        cursorAccent: '#0a0a0a',
        selectionBackground: '#333',
        black: '#0a0a0a',
        green: '#00ff41',
        red: '#ff3333',
        yellow: '#ffcc00',
        blue: '#4da6ff',
      },
      fontFamily: "'JetBrains Mono', 'Fira Code', 'SF Mono', monospace",
      fontSize: 13,
      cursorBlink: true,
      convertEol: true,
    })

    const fit = new FitAddon()
    term.loadAddon(fit)
    term.loadAddon(new WebLinksAddon())

    if (termRef.current) {
      termRef.current.innerHTML = ''
      term.open(termRef.current)
      fit.fit()
    }

    xtermRef.current = term
    fitRef.current = fit

    // WebSocket connection
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    const ws = new WebSocket(`${protocol}//${window.location.host}/ws/terminal`)
    wsRef.current = ws

    ws.binaryType = 'arraybuffer'

    ws.onopen = () => {
      setStatus('connected')
      // Send initial terminal size
      const dims = JSON.stringify({ cols: term.cols, rows: term.rows })
      ws.send(new Uint8Array([0, ...new TextEncoder().encode(dims)]))
    }

    ws.onmessage = (event) => {
      if (event.data instanceof ArrayBuffer) {
        term.write(new Uint8Array(event.data))
      } else {
        term.write(event.data)
      }
    }

    ws.onclose = () => {
      setStatus('disconnected')
      wsRef.current = null
      term.write('\r\n\x1b[31m[connection closed]\x1b[0m\r\n')
    }

    ws.onerror = () => {
      setStatus('error')
      wsRef.current = null
    }

    // Send terminal input to WebSocket
    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(new TextEncoder().encode(data))
      }
    })

    // Handle resize
    const handleResize = () => {
      fit.fit()
      if (ws.readyState === WebSocket.OPEN) {
        const dims = JSON.stringify({ cols: term.cols, rows: term.rows })
        ws.send(new Uint8Array([0, ...new TextEncoder().encode(dims)]))
      }
    }

    term.onResize(() => {
      if (ws.readyState === WebSocket.OPEN) {
        const dims = JSON.stringify({ cols: term.cols, rows: term.rows })
        ws.send(new Uint8Array([0, ...new TextEncoder().encode(dims)]))
      }
    })

    window.addEventListener('resize', handleResize)

    // Store cleanup reference
    term._cleanup = () => {
      window.removeEventListener('resize', handleResize)
    }
  }, [])

  const disconnect = useCallback(() => {
    if (wsRef.current) {
      wsRef.current.close()
      wsRef.current = null
    }
    if (xtermRef.current) {
      xtermRef.current._cleanup?.()
      xtermRef.current.dispose()
      xtermRef.current = null
    }
    fitRef.current = null
    setStatus('disconnected')
  }, [])

  // Connect on mount, disconnect on unmount
  useEffect(() => {
    connect()
    return () => disconnect()
  }, [connect, disconnect])

  const statusColor = {
    connected: 'var(--green)',
    connecting: 'var(--yellow)',
    disconnected: 'var(--text-dim)',
    error: 'var(--red)',
  }

  return (
    <div className="terminal-wrapper">
      <div className="terminal-toolbar">
        <div className="terminal-status">
          <span className="dot" style={{ background: statusColor[status] || 'var(--text-dim)' }}></span>
          {status}
        </div>
        <div>
          {status === 'disconnected' && (
            <button className="btn-sm" onClick={connect}>reconnect</button>
          )}
          {status === 'connected' && (
            <button className="btn-sm" onClick={disconnect}>disconnect</button>
          )}
        </div>
      </div>
      <div ref={termRef} className="terminal-container"></div>
    </div>
  )
}
