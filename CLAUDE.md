# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AgentOS-CC is a Claude Code persistent memory, security monitoring, and always-on Telegram setup. Everything runs on a single VPS: Claude Code CLI, self-hosted Supabase (Docker), a Next.js security dashboard with secrets management and web terminal, and Caddy for reverse proxy + auto TLS. The domain and wildcard (`*.domain.com`) point at the VPS.

The system requires **zero API keys** for core functionality — summaries use `claude -p` (subscription auth). External service keys can be added via the dashboard secrets tab.

Deployable in a single session via `bootstrap.sh` with guided prompts (or fully automated via env vars).

## Architecture

**VPS**: Claude Code runs in a tmux session with the Telegram plugin. Scripts in `/opt/agentos/scripts/` handle memory, session sync, summaries, watchdog, security monitoring, and server health. All scripts talk to Supabase via localhost curl REST calls.

**Supabase**: Self-hosted via Docker Compose. PostgreSQL + PostgREST. Nine tables: `cc_sessions`, `cc_memory`, `cc_projects`, `cc_user_profile` (core); `cc_secrets` (dashboard-managed keys); `cc_security_bans`, `cc_security_logins`, `cc_security_stats`, `cc_server_health` (security/health). Only accessible via localhost.

**Dashboard**: Next.js app with 3 tabs — Overview (health/security), Secrets (API key management), Terminal (browser SSH). Served via Caddy on `dashboard.domain.com`.

**Terminal**: WebSocket-to-SSH bridge service. Connects to VPS as `agentos` user on demand.

**Caddy**: Reverse proxy with auto Let's Encrypt TLS. Routes dashboard + terminal WebSocket.

### Key Scripts (all in `/opt/agentos/scripts/`)

| Script | Purpose | Trigger |
|---|---|---|
| `memory.sh` | Memory load/search/get/add | Called by Claude or hooks |
| `memory-load.sh` | Loads session summaries + profile at start | SessionStart hook |
| `sync-sessions.sh` | JSONL → Supabase | Cron every 30 min |
| `daily-summary.sh` | Session summaries via `claude -p` | Cron every 2 hours |
| `watchdog.sh` | Auto-restart Claude in tmux | Cron every 5 min |
| `sync-secrets.sh` | Dashboard secrets → local .env | Cron every 5 min |
| `security-sync.sh` | fail2ban/logins → Supabase | Cron every 10 min |
| `server-health.sh` | System metrics → Supabase | Cron every 10 min |
| `system-overview.sh` | System inventory (called by health) | Not scheduled directly |

### Memory Model

- **CLAUDE.md** (on deployed VPS) is the primary long-term memory — Claude writes skills, company info, and important discoveries here during sessions
- **Session summaries** in Supabase are a searchable log — lightweight one-liners loaded at session start, full detail available via `memory.sh get <id>`
- **SQL keyword search** for historical lookup — no vector embeddings needed

## Build & Deploy

```bash
# Bootstrap install on VPS (interactive)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"

# Fully automated (no prompts)
AGENTOS_DOMAIN=example.com AGENTOS_DASHBOARD_PASSWORD=pass \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"

# Post-install: check status
bash /opt/agentos/scripts/status.sh

# Update
cd /opt/agentos && git pull && bash bootstrap.sh

# Rebuild dashboard after changes
cd /opt/agentos && docker compose up -d --build dashboard

# Restart all services
cd /opt/agentos && docker compose restart
```

## Development

```bash
# Sync local files to VPS for testing (requires sync-to-vps.py + paramiko)
python sync-to-vps.py

# Run individual scripts on VPS
python vps.py 'bash /opt/agentos/scripts/memory.sh load'
python vps.py 'bash /opt/agentos/scripts/server-health.sh'

# Check VPS Docker containers
python vps.py 'docker ps'
```

## Conventions

- **Bash scripts**: Pure bash, `source` credentials from env files, idempotent upsert patterns, silent failure with retry on next cron cycle
- **Credentials**: Runtime creds in `~/.claude/credentials/` with `chmod 600`. Auto-generated secrets in `/opt/agentos/.env`. Dashboard-managed keys synced to `custom.env`.
- **Naming**: Scripts use `kebab-case.sh`, logs use `script-name.log`
- **Supabase access**: Scripts use `SUPABASE_SERVICE_ROLE_KEY` (full access). Dashboard uses `SUPABASE_ANON_KEY` for reads, `SERVICE_ROLE_KEY` for secrets writes. All via localhost.
- **Summaries**: Generated via `claude -p --model haiku` (subscription auth, no API key). 2-hour inactivity threshold, content truncated to 80k chars.
- **Firewall**: Handled by VPS hosting provider, not managed on the server itself

## Security Rules

- Never share credentials over Telegram or in git
- Supabase is localhost-only — never exposed to the internet
- Dashboard password hash stored in `/opt/agentos/.env`, never in code
- `cc_secrets` table has no anon access — only readable via SERVICE_ROLE_KEY
- fail2ban protects SSH against brute-force attempts
