#!/bin/bash
# status.sh — Post-install verification script

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  [${GREEN}OK${NC}]   $1"; }
fail() { echo -e "  [${RED}FAIL${NC}] $1"; }
note() { echo -e "  [INFO] $1"; }

check() {
  if eval "$2" >/dev/null 2>&1; then ok "$1"; else fail "$1"; fi
}

echo ""
echo "AgentOS-CC System Status"
echo "========================"
echo ""

ENV_FILE="/opt/agentos/.env"
DOMAIN=$(grep '^AGENTOS_DOMAIN=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
CADDY_ENABLED=$(grep '^AGENTOS_CADDY_ENABLED=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)
DASHBOARD_URL=$(grep '^AGENTOS_DASHBOARD_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)

check "Docker running" "systemctl is-active docker"
check "PostgreSQL container up" "docker ps | grep -q agentos-db"
check "PostgREST responding on :3001" "curl -sf http://localhost:3001/ | grep -q paths"
check "Dashboard responding on :3000" "curl -sf http://localhost:3000 | grep -q html"
if [[ "$CADDY_ENABLED" == "true" ]]; then
  check "Caddy running" "systemctl is-active caddy"
else
  note "Caddy disabled (domain setup skipped)"
fi
check "fail2ban running" "systemctl is-active fail2ban"

# Claude Code
AGENTOS_HOME="/home/agentos"
if [[ -d "$AGENTOS_HOME" ]]; then
  check "Claude Code installed" "sudo -u agentos which claude"
else
  check "Claude Code installed" "which claude"
fi
check "tmux session 'claude' exists" "tmux has-session -t claude"

# Crontab
CRON_COUNT=$(crontab -u agentos -l 2>/dev/null | grep -v '^#' | grep -c agentos || echo "0")
if [[ "$CRON_COUNT" -ge 5 ]]; then ok "Crontab has $CRON_COUNT entries"; else fail "Crontab has $CRON_COUNT entries (expected 5+)"; fi

# Database tables
TABLE_COUNT=$(docker exec agentos-db psql -U postgres -d postgres -t -c "SELECT count(*) FROM pg_tables WHERE schemaname='public'" 2>/dev/null | tr -d ' ')
if [[ "$TABLE_COUNT" -ge 8 ]]; then ok "Supabase has $TABLE_COUNT tables"; else fail "Supabase has ${TABLE_COUNT:-0} tables (expected 8)"; fi

# Credentials
if [[ -d "$AGENTOS_HOME/.claude/credentials" ]]; then
  CRED_PERMS=$(stat -c '%a' "$AGENTOS_HOME/.claude/credentials" 2>/dev/null || echo "???")
  if [[ "$CRED_PERMS" == "700" ]]; then ok "Credentials directory (mode $CRED_PERMS)"; else fail "Credentials directory (mode $CRED_PERMS, expected 700)"; fi
else
  fail "Credentials directory missing"
fi

# Dashboard check
if [[ "$CADDY_ENABLED" == "true" && -n "$DOMAIN" ]]; then
  check "Dashboard at https://dashboard.${DOMAIN}" "curl -sfk https://dashboard.${DOMAIN} | grep -q html"
elif [[ -n "$DASHBOARD_URL" ]]; then
  note "Dashboard URL: ${DASHBOARD_URL} (or http://<server-ip>:3000 on a VPS without a domain)"
fi

echo ""
