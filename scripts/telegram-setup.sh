#!/bin/bash
# ============================================================
# telegram-setup.sh — Guided Telegram bot setup for AgentOS-CC
# Run as the agentos user after Claude Code authentication.
#
# Can also be run non-interactively:
#   AGENTOS_TELEGRAM_TOKEN=123:AAH... bash telegram-setup.sh
# ============================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }

TELEGRAM_ENV_DIR="$HOME/.claude/channels/telegram"
TELEGRAM_ENV_FILE="$TELEGRAM_ENV_DIR/.env"
CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
CHANNEL_FLAG="plugin:telegram@claude-plugins-official"

echo ""
echo -e "${GREEN}${BOLD}AgentOS-CC — Telegram Setup${NC}"
echo "==========================="
echo ""

# --- Pre-flight ---
if [[ ! -x "$CLAUDE_BIN" ]] && ! command -v claude &>/dev/null; then
  error "Claude Code CLI not found. Run bootstrap.sh first."
  exit 1
fi
if ! command -v claude &>/dev/null; then
  export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"
fi

# ============================================================
# Step 1: Create a bot (instructions only — requires Telegram)
# ============================================================
echo -e "${BOLD}Step 1 — Create a Telegram bot${NC}"
echo ""
echo "  1. Open Telegram and search for @BotFather (or go to t.me/BotFather)"
echo "  2. Send /newbot"
echo "  3. Choose a display name (anything, can contain spaces)"
echo "  4. Choose a unique username ending in 'bot' (e.g. my_assistant_bot)"
echo "  5. BotFather replies with a token like: 123456789:AAHfiqksKZ8..."
echo "     Copy the ENTIRE token including the leading number and colon."
echo ""

# ============================================================
# Step 2: Configure the token
# ============================================================
echo -e "${BOLD}Step 2 — Configure the bot token${NC}"
echo ""

TOKEN="${AGENTOS_TELEGRAM_TOKEN:-}"
NEED_TOKEN=true

# Check for existing token
if [[ -f "$TELEGRAM_ENV_FILE" ]] && grep -q "TELEGRAM_BOT_TOKEN=." "$TELEGRAM_ENV_FILE" 2>/dev/null; then
  existing=$(grep "TELEGRAM_BOT_TOKEN=" "$TELEGRAM_ENV_FILE" | cut -d= -f2)
  info "Existing token found: ${existing:0:10}..."
  if [[ -n "$TOKEN" ]]; then
    info "Overwriting with token from AGENTOS_TELEGRAM_TOKEN env var"
  else
    read -rp "  Keep existing token? (Y/n): " keep
    if [[ "${keep,,}" != "n" ]]; then
      NEED_TOKEN=false
      success "Keeping existing token"
    fi
  fi
fi

if $NEED_TOKEN; then
  if [[ -z "$TOKEN" ]]; then
    read -rp "  Paste your bot token: " TOKEN
  else
    info "Using token from AGENTOS_TELEGRAM_TOKEN env var"
  fi

  if [[ -z "$TOKEN" ]]; then
    error "No token provided. Re-run this script when you have one."
    exit 1
  fi

  # Basic format check
  if [[ ! "$TOKEN" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]; then
    warn "Token doesn't match expected format (number:alphanumeric). Double-check it."
  fi

  mkdir -p "$TELEGRAM_ENV_DIR"
  echo "TELEGRAM_BOT_TOKEN=$TOKEN" > "$TELEGRAM_ENV_FILE"
  chmod 600 "$TELEGRAM_ENV_FILE"
  success "Token saved to $TELEGRAM_ENV_FILE"
fi
echo ""

# ============================================================
# Step 3: Install the plugin
# ============================================================
echo -e "${BOLD}Step 3 — Install the Telegram plugin${NC}"
echo ""
echo "  Claude Code will start now. Inside the session, run:"
echo ""
echo -e "    ${GREEN}/plugin install telegram@claude-plugins-official${NC}"
echo ""
echo "  After the plugin installs, type ${BOLD}/exit${NC} to return here."
echo ""
read -rp "  Press Enter to launch Claude Code..."
echo ""

claude || true

echo ""

# ============================================================
# Step 4: Pair your Telegram account
# ============================================================
echo -e "${BOLD}Step 4 — Pair your Telegram account${NC}"
echo ""
echo "  Claude Code will restart with the Telegram channel enabled."
echo "  Once it's running:"
echo ""
echo "    1. Open Telegram and DM your bot (t.me/your_bot_username)"
echo "    2. Send any message — the bot replies with a 6-character pairing code"
echo "    3. In the Claude Code session below, run:"
echo ""
echo -e "       ${GREEN}/telegram:access pair <CODE>${NC}"
echo ""
echo "    4. Send another DM to verify it works"
echo ""
echo "    5. Lock down access so only you can use the bot:"
echo ""
echo -e "       ${GREEN}/telegram:access policy allowlist${NC}"
echo ""
echo "    6. Type ${BOLD}/exit${NC} when done"
echo ""
read -rp "  Press Enter to launch Claude Code with Telegram..."
echo ""

claude --channels "$CHANNEL_FLAG" || true

# Seed the always-on tmux session immediately instead of waiting for cron.
bash /opt/agentos/scripts/watchdog.sh >/dev/null 2>&1 || true

echo ""
echo -e "${GREEN}${BOLD}Telegram setup complete!${NC}"
echo ""
echo "  The watchdog cron job will automatically keep Claude Code running"
echo "  with Telegram enabled in a tmux session. You can safely disconnect."
echo ""
echo "  Useful commands:"
echo "    tmux attach -t claude          — attach to the Claude session"
echo "    bash /opt/agentos/scripts/status.sh  — check system status"
echo ""
