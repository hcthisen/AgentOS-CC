# AgentOS-CC

A self-hosted system that gives Claude Code persistent memory, security monitoring, and always-on Telegram access — all on a single VPS.

## Install

SSH into a fresh Ubuntu/Debian VPS as root and run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"
```

Or fully automated (no prompts):

```bash
AGENTOS_DOMAIN=example.com \
AGENTOS_DASHBOARD_PASSWORD=yourpassword \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"
```

### DNS

Before installing, point your domain at the VPS:

| Record | Type | Value |
|--------|------|-------|
| `example.com` | A | `<VPS IP>` |
| `*.example.com` | A | `<VPS IP>` |

Caddy auto-provisions HTTPS via Let's Encrypt.

### What the installer does

1. Creates `agentos` user with passwordless sudo
2. Installs Docker, Node.js, Caddy, tmux, fail2ban
3. Collects config (domain, dashboard password) or reads env vars
4. Generates all secrets (Postgres password, JWT, Supabase keys)
5. Starts PostgreSQL + PostgREST + Dashboard + Terminal via Docker Compose
6. Configures Caddy for `dashboard.domain.com` with auto TLS
7. Deploys automation scripts and cron jobs
8. Installs Claude Code CLI
9. Hands off to you for interactive Claude Code auth + Telegram setup

### After install — Telegram setup

The bootstrap switches you to the `agentos` user. Run `claude` and complete browser authentication. Then install the Telegram plugin:

```
/plugin install telegram@claude-plugins-official
```

Follow the prompts to configure your bot token and approve your Telegram user. Once done, type `/exit` to leave Claude, then `exit` twice to close SSH.

The watchdog starts Claude in tmux within 5 minutes. Everything runs autonomously from there.

Claude Code runs with full tool permissions (Bash, Read, Write, Edit, etc.) so it can operate autonomously via Telegram without prompting for approval. This is safe because it runs as the non-root `agentos` user.

No API keys needed for the core system — summaries use `claude -p` (your subscription). External service keys (ElevenLabs, etc.) can be added via the dashboard secrets tab.

## Architecture

```
VPS (domain.com + *.domain.com)
├── Claude Code CLI (tmux + Telegram plugin)
├── PostgreSQL + PostgREST (Docker, localhost only)
├── Security Dashboard (Docker, dashboard.domain.com)
├── Web Terminal (Docker, WebSocket SSH bridge)
├── Caddy (reverse proxy + auto TLS)
├── fail2ban (SSH brute-force protection)
└── Cron scripts:
    ├── watchdog       (*/5 min)  — auto-restart Claude
    ├── secrets-sync   (*/5 min)  — dashboard secrets → local .env
    ├── security-sync  (*/10 min) — bans + logins → DB
    ├── server-health  (*/10 min) — metrics → DB
    ├── session-sync   (*/30 min) — JSONL → DB
    └── daily-summary  (2h)       — session summaries via claude -p
```

## Post-Install

```bash
# System status
bash /opt/agentos/scripts/status.sh

# View logs
tail -f /opt/agentos/logs/watchdog.log

# Attach to Claude Code
tmux attach -t claude

# Restart services
cd /opt/agentos && docker compose restart

# Update
cd /opt/agentos && git pull && bash bootstrap.sh
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AGENTOS_DOMAIN` | Yes* | Root domain pointed at the VPS |
| `AGENTOS_DASHBOARD_PASSWORD` | Yes* | Dashboard login password |
| `AGENTOS_DIR` | No | Install directory (default: `/opt/agentos`) |

\* Prompted interactively if not set.

## Requirements

- Ubuntu 22.04+ or Debian 12+ VPS (2GB+ RAM recommended)
- Domain with A + wildcard A records pointed at the VPS
- Claude Code subscription (for CLI authentication)

## License

Private.
