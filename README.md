# AgentOS-CC

A self-hosted system that gives Claude Code persistent memory, security monitoring, and always-on Telegram access on a single machine or VPS.

## Install

The bootstrap command downloads `bootstrap.sh` from GitHub `main` every time. It does not use uncommitted local changes from your checkout.

To test local edits, run `bash ./bootstrap.sh` from the repo itself.

### Mode 1: Domain-enabled VPS

Use this when you have a real domain pointed at the server and you want the current Caddy + HTTPS setup.

SSH into a fresh Ubuntu/Debian VPS as root and run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"
```

Or fully automated:

```bash
AGENTOS_ADD_DOMAIN=true \
AGENTOS_DOMAIN=example.com \
AGENTOS_DASHBOARD_PASSWORD=yourpassword \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"
```

Before installing, point your domain at the VPS:

| Record | Type | Value |
|--------|------|-------|
| `example.com` | A | `<VPS IP>` |
| `*.example.com` | A | `<VPS IP>` |

Caddy auto-provisions HTTPS via Let's Encrypt.

### Mode 2: No-domain install

Use this for a local machine or a simple VPS test where you want the dashboard directly on port `3000`.

Interactive install:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"
```

Choose `Add domain? [y/n]` and answer `n`.

Non-interactive install:

```bash
AGENTOS_ADD_DOMAIN=false \
AGENTOS_DASHBOARD_PASSWORD=yourpassword \
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/hcthisen/AgentOS-CC/main/bootstrap.sh)"
```

No-domain access patterns:

- Local machine: `http://localhost:3000`
- VPS without a domain: `http://<server-ip>:3000`

In no-domain mode, Caddy is intentionally skipped and the web terminal tab is disabled because it depends on the Caddy websocket route.

### What the installer does

1. Creates `agentos` user with passwordless sudo
2. Installs Docker, Node.js, tmux, fail2ban, and Bun
3. Collects config (`Add domain`, optional domain, dashboard password) or reads env vars
4. Generates all secrets (Postgres password, JWT, Supabase keys)
5. Starts PostgreSQL + PostgREST + Dashboard via Docker Compose
6. Starts the web terminal and configures Caddy only when domain mode is enabled
7. Deploys automation scripts and cron jobs
8. Installs Claude Code CLI
9. Hands off to you for interactive Claude Code auth + Telegram setup

### After install — Telegram setup

The bootstrap switches you to the `agentos` user. Run this and complete browser authentication first:

```bash
claude --dangerously-skip-permissions
```

#### 1. Create a bot with BotFather

Open Telegram and search for [@BotFather](https://t.me/BotFather). Send `/newbot` and follow the prompts:

- **Name** — display name shown in chat headers (anything, can contain spaces)
- **Username** — unique handle ending in `bot` (e.g. `my_assistant_bot`)

BotFather replies with a token like `123456789:AAHfiqksKZ8...` — copy the entire thing including the leading number and colon.

#### 2. Install the plugin

Inside a Claude Code session:

```
/plugin install telegram@claude-plugins-official
```

Then leave Claude Code:

```
/exit
```

Re-enter Claude Code:

```bash
claude --dangerously-skip-permissions
```

#### 3. Configure the token

Still inside Claude Code:

```
/telegram:configure 123456789:AAHfiqksKZ8...
```

This writes the token to `~/.claude/channels/telegram/.env`.

Then type `/exit` to leave the session.

#### 4. Relaunch with the Telegram channel

```bash
claude --channels plugin:telegram@claude-plugins-official
```

> You only need to do this once manually. The watchdog cron job already launches Claude with this flag, so after setup it happens automatically.

#### 5. Pair your Telegram account

With Claude Code running from step 4:

1. Open Telegram and DM your bot
2. The bot replies with a **6-character pairing code**
3. In the Claude Code session, run:

```
/telegram:access pair <CODE>
```

Your next DM reaches the assistant.

#### 6. Lock it down

Switch to allowlist mode so only paired users can interact with the bot:

```
/telegram:access policy allowlist
```

Type `/exit`, then `exit` to disconnect from the VPS. The watchdog starts Claude in tmux within 5 minutes. Everything runs autonomously from there.

---

Claude Code runs with full tool permissions (Bash, Read, Write, Edit, etc.) so it can operate autonomously via Telegram without prompting for approval. This is safe because it runs as the non-root `agentos` user.

No API keys needed for the core system — summaries use `claude -p` (your subscription). External service keys (ElevenLabs, etc.) can be added via the dashboard secrets tab.

## Architecture

Typical domain-enabled VPS layout:

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

## Post-Install (optional)

Everything runs automatically after setup — no extra steps needed. These commands are for maintenance and troubleshooting:

```bash
# Check that all services are running
bash /opt/agentos/scripts/status.sh

# Tail logs if something seems off
tail -f /opt/agentos/logs/watchdog.log

# Attach to the live Claude Code session (detach with Ctrl+B, D)
tmux attach -t claude

# Restart services after config changes
cd /opt/agentos && docker compose restart

# Pull latest updates and re-run the installer
cd /opt/agentos && git pull && bash bootstrap.sh
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `AGENTOS_ADD_DOMAIN` | No | `true` to enable domain/Caddy/HTTPS, `false` to skip them |
| `AGENTOS_DOMAIN` | Required when `AGENTOS_ADD_DOMAIN=true` | Root domain pointed at the VPS |
| `AGENTOS_DASHBOARD_PASSWORD` | Yes* | Dashboard login password |
| `AGENTOS_DIR` | No | Install directory (default: `/opt/agentos`) |

\* Prompted interactively if not set.

## Requirements

- Ubuntu 22.04+ or Debian 12+ machine (2GB+ RAM recommended)
- For domain mode: a domain with A + wildcard A records pointed at the VPS
- Claude Code subscription (for CLI authentication)

## License

Private.
