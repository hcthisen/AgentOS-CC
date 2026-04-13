'use client'
import { useState, useEffect, useCallback } from 'react'
import SecretsTab from './components/SecretsTab'
import TerminalTab from './components/TerminalTab'

// --- Shared Components ---

function Stat({ label, value, status }) {
  return (
    <div className="stat">
      <div className="stat-label">{label}</div>
      <div className={`stat-value ${status || ''}`}>{value}</div>
    </div>
  )
}

function ServiceStatus({ name, status }) {
  const dotClass = status === 'active' || status === 'reachable'
    ? 'green'
    : status === 'disabled'
      ? 'yellow'
      : 'red'
  return (
    <span style={{ marginRight: '1rem' }}>
      <span className={`dot ${dotClass}`}></span>
      {name}: {status}
    </span>
  )
}

function BarChart({ data }) {
  if (!data || !data.length) return <div style={{ color: 'var(--text-dim)' }}>No data</div>
  const max = Math.max(...data.map(d => d.count), 1)
  return (
    <div className="bar-chart">
      {data.map((d, i) => (
        <div className="bar-row" key={i}>
          <div className="bar-label">{d.date || d.ip || d.label}</div>
          <div className="bar-track">
            <div className="bar-fill" style={{ width: `${(d.count / max) * 100}%` }}></div>
          </div>
          <div className="bar-value">{d.count}</div>
        </div>
      ))}
    </div>
  )
}

// --- Login ---

function LoginForm({ onLogin }) {
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    setError('')
    try {
      const res = await fetch('/api/auth', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      })
      if (res.ok) onLogin()
      else setError('Invalid password')
    } catch {
      setError('Connection error')
    }
    setLoading(false)
  }

  return (
    <div className="login-container">
      <form className="login-box" onSubmit={handleSubmit}>
        <h1>AgentOS // login</h1>
        {error && <div className="login-error">{error}</div>}
        <input type="password" placeholder="password" value={password}
          onChange={(e) => setPassword(e.target.value)} autoFocus />
        <button type="submit" disabled={loading}>
          {loading ? 'authenticating...' : 'authenticate'}
        </button>
      </form>
    </div>
  )
}

// --- Overview Tab ---

function OverviewTab() {
  const [data, setData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [lastUpdate, setLastUpdate] = useState(null)

  const fetchData = useCallback(async () => {
    try {
      const res = await fetch('/api/security')
      if (res.status === 401) { window.location.reload(); return }
      if (res.ok) { setData(await res.json()); setLastUpdate(new Date()) }
    } catch { /* retry next cycle */ }
    setLoading(false)
  }, [])

  useEffect(() => {
    fetchData()
    const interval = setInterval(fetchData, 60000)
    return () => clearInterval(interval)
  }, [fetchData])

  if (loading) return <div className="loading">loading...</div>
  if (!data) return <div className="loading">failed to load data</div>

  const h = data.health || {}
  const s = data.stats || {}
  const claude = h.claude_status || {}
  const services = h.services || {}
  const cpuStatus = (h.cpu_percent || 0) > 80 ? 'error' : (h.cpu_percent || 0) > 50 ? 'warn' : 'ok'
  const ramPercent = h.ram_total_mb ? ((h.ram_used_mb / h.ram_total_mb) * 100).toFixed(0) : 0
  const ramStatus = ramPercent > 80 ? 'error' : ramPercent > 60 ? 'warn' : 'ok'
  const diskPercent = h.disk_total_gb ? ((h.disk_used_gb / h.disk_total_gb) * 100).toFixed(0) : 0

  return (
    <>
      <div className="section-header-meta">
        <span className="refresh">{lastUpdate ? `updated ${lastUpdate.toLocaleTimeString()}` : ''}</span>
      </div>

      <div className="section">
        <div className="section-header">Server Health</div>
        <div className="section-body">
          <div className="stat-grid">
            <Stat label="CPU" value={`${h.cpu_percent || 0}%`} status={cpuStatus} />
            <Stat label="RAM" value={`${h.ram_used_mb || 0}/${h.ram_total_mb || 0} MB`} status={ramStatus} />
            <Stat label="Disk" value={`${h.disk_used_gb || 0}/${h.disk_total_gb || 0} GB (${diskPercent}%)`} />
            <Stat label="Load" value={h.load_avg || '-'} />
            <Stat label="Uptime" value={h.uptime || '-'} />
            <Stat label="Connections" value={h.active_connections || 0} />
          </div>
        </div>
      </div>

      <div className="section">
        <div className="section-header">Claude Code</div>
        <div className="section-body">
          <div className="stat-grid">
            <Stat label="Process" value={claude.running ? 'running' : 'stopped'} status={claude.running ? 'ok' : 'error'} />
            <Stat label="Telegram" value={claude.telegram ? 'active' : 'inactive'} status={claude.telegram ? 'ok' : 'warn'} />
            <Stat label="tmux" value={claude.tmux_session ? 'active' : 'missing'} status={claude.tmux_session ? 'ok' : 'error'} />
            <Stat label="Sessions" value={claude.total_sessions || 0} />
          </div>
        </div>
      </div>

      <div className="section">
        <div className="section-header">Services</div>
        <div className="section-body">
          {Object.entries(services).map(([name, status]) => (
            <ServiceStatus key={name} name={name} status={status} />
          ))}
        </div>
      </div>

      <div className="section">
        <div className="section-header">Security</div>
        <div className="section-body">
          <div className="stat-grid">
            <Stat label="Banned IPs" value={s.total_banned || 0} status={(s.total_banned || 0) > 50 ? 'warn' : 'ok'} />
            <Stat label="Failed Attempts" value={s.total_failed || 0} />
            <Stat label="Total Logins" value={s.total_logins || 0} />
          </div>
        </div>
      </div>

      {h.failed_per_day?.length > 0 && (
        <div className="section">
          <div className="section-header">Failed Logins / Day (7d)</div>
          <div className="section-body"><BarChart data={h.failed_per_day} /></div>
        </div>
      )}

      {h.top_attackers?.length > 0 && (
        <div className="section">
          <div className="section-header">Top Attackers</div>
          <div className="section-body"><BarChart data={h.top_attackers} /></div>
        </div>
      )}

      <div className="section">
        <div className="section-header">Recent Bans ({(data.bans || []).length})</div>
        <div className="section-body">
          <table>
            <thead><tr><th>IP</th><th>Country</th><th>Jail</th><th>Time</th></tr></thead>
            <tbody>
              {(data.bans || []).slice(0, 20).map((ban, i) => (
                <tr key={i}>
                  <td>{ban.ip}</td>
                  <td>{ban.country_code ? `${ban.country_code} ${ban.country || ''}` : '-'}</td>
                  <td>{ban.jail}</td>
                  <td>{ban.banned_at ? new Date(ban.banned_at).toLocaleString() : '-'}</td>
                </tr>
              ))}
              {(data.bans || []).length === 0 && (
                <tr><td colSpan="4" style={{ color: 'var(--text-dim)' }}>No bans recorded</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      <div className="section">
        <div className="section-header">Login History</div>
        <div className="section-body">
          <table>
            <thead><tr><th>User</th><th>IP</th><th>Type</th><th>Time</th><th>Duration</th></tr></thead>
            <tbody>
              {(data.logins || []).slice(0, 20).map((login, i) => (
                <tr key={i}>
                  <td>{login.user_name}</td>
                  <td>{login.ip || '-'}</td>
                  <td>{login.session_type}</td>
                  <td>{login.login_at || '-'}</td>
                  <td>{login.duration || '-'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {h.docker_containers?.length > 0 && (
        <div className="section">
          <div className="section-header">Docker Containers</div>
          <div className="section-body">
            <table>
              <thead><tr><th>Name</th><th>Image</th><th>Status</th></tr></thead>
              <tbody>
                {h.docker_containers.map((c, i) => (
                  <tr key={i}>
                    <td>{c.name}</td><td>{c.image}</td>
                    <td><span className={`dot ${c.status?.includes('Up') ? 'green' : 'red'}`}></span>{c.status}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {h.open_ports?.length > 0 && (
        <div className="section">
          <div className="section-header">Open Ports</div>
          <div className="section-body">
            <table>
              <thead><tr><th>Port</th><th>Process</th></tr></thead>
              <tbody>
                {h.open_ports.map((p, i) => (
                  <tr key={i}><td>{p.port}</td><td>{p.process}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </>
  )
}

// --- Main App ---

const TABS = [
  { id: 'overview', label: 'overview' },
  { id: 'secrets', label: 'secrets' },
  { id: 'terminal', label: 'terminal' },
]

export default function Home() {
  const [authenticated, setAuthenticated] = useState(null)
  const [activeTab, setActiveTab] = useState('overview')

  useEffect(() => {
    fetch('/api/auth/check')
      .then(r => r.json())
      .then(d => setAuthenticated(d.authenticated))
      .catch(() => setAuthenticated(false))
  }, [])

  if (authenticated === null) return <div className="loading">...</div>
  if (!authenticated) return <LoginForm onLogin={() => setAuthenticated(true)} />

  const handleLogout = () => {
    document.cookie = 'dashboard_session=; Max-Age=0; path=/'
    window.location.reload()
  }

  return (
    <div className="dashboard">
      <div className="header">
        <h1>AgentOS // dashboard</h1>
        <button className="logout-btn" onClick={handleLogout}>logout</button>
      </div>

      <div className="tab-nav">
        {TABS.map(tab => (
          <button key={tab.id}
            className={`tab-item ${activeTab === tab.id ? 'active' : ''}`}
            onClick={() => setActiveTab(tab.id)}>
            {tab.label}
          </button>
        ))}
      </div>

      <div className="tab-content">
        {activeTab === 'overview' && <OverviewTab />}
        {activeTab === 'secrets' && <SecretsTab />}
        {activeTab === 'terminal' && <TerminalTab />}
      </div>
    </div>
  )
}
