#!/bin/bash
# ============================================================
# AgentOS-CC Bootstrap Installer
# Deploy Claude Code with persistent memory, security
# monitoring, and Telegram on a single VPS.
# ============================================================

set -euo pipefail

AGENTOS_USER="agentos"
INSTALL_DIR="${AGENTOS_DIR:-/opt/agentos}"
REPO_URL="https://github.com/hcthisen/AgentOS-CC.git"
REPO_BRANCH="${AGENTOS_BRANCH:-main}"

# --- Colors ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERR]${NC}  $*" >&2; }
step()    { echo -e "\n${GREEN}>>>${NC} $*"; }

is_yes() {
  case "${1,,}" in
    y|yes|true|1) return 0 ;;
    *) return 1 ;;
  esac
}

is_no() {
  case "${1,,}" in
    n|no|false|0) return 0 ;;
    *) return 1 ;;
  esac
}

env_get() {
  local key="$1"
  local file="$2"
  [[ -f "$file" ]] || return 0
  grep -E "^${key}=" "$file" | head -1 | cut -d= -f2-
}

# ============================================================
# Pre-flight checks
# ============================================================

check_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root"
    exit 1
  fi
}

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect OS"
    exit 1
  fi
  source /etc/os-release
  if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    warn "Untested OS: $ID. Proceeding anyway..."
  fi
  info "OS: $PRETTY_NAME"
}

# ============================================================
# Phase 1: System Setup
# ============================================================

create_user() {
  if id "$AGENTOS_USER" &>/dev/null; then
    info "User '$AGENTOS_USER' already exists"
  else
    step "Creating user '$AGENTOS_USER'..."
    useradd -m -s /bin/bash "$AGENTOS_USER"
    echo "$AGENTOS_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agentos
    chmod 440 /etc/sudoers.d/agentos
    success "User '$AGENTOS_USER' created with passwordless sudo"
  fi
}

install_deps() {
  step "Installing system dependencies..."
  export DEBIAN_FRONTEND=noninteractive

  # Docker
  if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1
    systemctl enable docker --now
    usermod -aG docker "$AGENTOS_USER"
    success "Docker installed"
  else
    info "Docker already installed"
  fi

  # System packages
  apt-get update -qq
  apt-get install -y -qq cron tmux fail2ban python3 jq curl git unzip >/dev/null 2>&1
  systemctl enable cron --now 2>/dev/null || true
  systemctl enable fail2ban --now 2>/dev/null || true
  success "System packages installed"
}

install_nodejs() {
  if command -v node &>/dev/null; then
    info "Node.js already installed: $(node --version)"
    return
  fi
  step "Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null 2>&1
  apt-get install -y -qq nodejs >/dev/null 2>&1
  success "Node.js $(node --version) installed"
}

install_bun() {
  local bun_bin="/home/$AGENTOS_USER/.bun/bin/bun"
  if [[ -x "$bun_bin" ]]; then
    info "Bun already installed: $("$bun_bin" --version 2>/dev/null)"
    return
  fi
  step "Installing Bun (required by Telegram plugin)..."
  # Install as agentos user (goes to ~/.bun)
  # Use || true to prevent set -e from killing bootstrap if installer returns non-zero
  sudo -u "$AGENTOS_USER" bash -c 'curl -fsSL https://bun.sh/install | bash' >/dev/null 2>&1 || true
  # Add to PATH in both .bashrc and .profile so login shells find it too
  local bashrc="/home/$AGENTOS_USER/.bashrc"
  local profile="/home/$AGENTOS_USER/.profile"
  for rc in "$bashrc" "$profile"; do
    if ! grep -q '.bun/bin' "$rc" 2>/dev/null; then
      echo 'export BUN_INSTALL="$HOME/.bun"' >> "$rc"
      echo 'export PATH="$HOME/.bun/bin:$PATH"' >> "$rc"
      chown "$AGENTOS_USER":"$AGENTOS_USER" "$rc"
    fi
  done
  if [[ -x "$bun_bin" ]]; then
    success "Bun installed: $("$bun_bin" --version 2>/dev/null)"
  else
    warn "Bun install failed. Telegram plugin requires it."
  fi
}

install_caddy() {
  if [[ "${AGENTOS_CADDY_ENABLED:-false}" != "true" ]]; then
    info "Skipping Caddy install because domain setup was skipped"
    return
  fi
  if command -v caddy &>/dev/null; then
    info "Caddy already installed"
    return
  fi
  step "Installing Caddy..."
  apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https >/dev/null 2>&1
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt-get update -qq
  apt-get install -y -qq caddy >/dev/null 2>&1
  success "Caddy installed"
}

clone_repo() {
  step "Setting up installation directory..."
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Repo exists, pulling latest..."
    cd "$INSTALL_DIR" && git pull --quiet
  else
    if [[ -d "$INSTALL_DIR" ]] && [[ "$(ls -A $INSTALL_DIR 2>/dev/null)" ]]; then
      info "Directory exists but is not a git repo, using existing files"
    else
      info "Cloning repository..."
      git clone --quiet --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" 2>/dev/null || {
        warn "Git clone failed. Creating directory structure manually..."
        mkdir -p "$INSTALL_DIR"
      }
    fi
  fi
  # Ensure directory structure
  mkdir -p "$INSTALL_DIR"/{scripts,dashboard,supabase/migrations,config,logs}
  chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
  success "Installation directory ready: $INSTALL_DIR"
}

# ============================================================
# Phase 2: Configuration
# ============================================================

collect_config() {
  step "Collecting configuration..."

  local add_domain=""

  if [[ -n "${AGENTOS_ADD_DOMAIN:-}" ]]; then
    add_domain="${AGENTOS_ADD_DOMAIN}"
  elif [[ -n "${AGENTOS_DOMAIN:-}" ]]; then
    add_domain="yes"
  else
    while true; do
      read -rp "  Add domain? [y/n]: " add_domain
      if is_yes "$add_domain" || is_no "$add_domain"; then
        break
      fi
      warn "Please answer y or n."
    done
  fi

  if is_yes "$add_domain"; then
    AGENTOS_ADD_DOMAIN="true"
    if [[ -z "${AGENTOS_DOMAIN:-}" ]]; then
      read -rp "  Enter your domain (e.g., example.com): " AGENTOS_DOMAIN
    fi
    if [[ -z "$AGENTOS_DOMAIN" ]]; then
      error "Domain is required when domain setup is enabled"
      exit 1
    fi
    AGENTOS_CADDY_ENABLED="true"
    AGENTOS_DASHBOARD_BIND_IP="127.0.0.1"
    AGENTOS_DASHBOARD_URL="https://dashboard.${AGENTOS_DOMAIN}"
    AGENTOS_SECURE_COOKIES="true"
    AGENTOS_TERMINAL_ENABLED="true"
    info "Domain mode enabled: ${AGENTOS_DASHBOARD_URL}"
  elif is_no "$add_domain"; then
    AGENTOS_ADD_DOMAIN="false"
    if [[ -n "${AGENTOS_DOMAIN:-}" ]]; then
      warn "Ignoring AGENTOS_DOMAIN because domain setup was skipped"
    fi
    AGENTOS_DOMAIN=""
    AGENTOS_CADDY_ENABLED="false"
    AGENTOS_DASHBOARD_BIND_IP="0.0.0.0"
    AGENTOS_DASHBOARD_URL="http://localhost:3000"
    AGENTOS_SECURE_COOKIES="false"
    AGENTOS_TERMINAL_ENABLED="false"
    info "Domain mode disabled"
    info "Dashboard access: http://localhost:3000 (or http://<server-ip>:3000 on a VPS)"
  else
    error "Invalid AGENTOS_ADD_DOMAIN value: ${add_domain}"
    exit 1
  fi

  # Dashboard password
  if [[ -z "${AGENTOS_DASHBOARD_PASSWORD:-}" ]]; then
    read -rsp "  Enter dashboard password: " AGENTOS_DASHBOARD_PASSWORD
    echo ""
  fi
  if [[ -z "$AGENTOS_DASHBOARD_PASSWORD" ]]; then
    error "Dashboard password is required"
    exit 1
  fi

  success "Configuration collected"
}

generate_secrets() {
  step "Generating secrets..."

  # Preserve existing secrets on re-run
  local existing_env="$INSTALL_DIR/.env"
  if [[ -f "$existing_env" ]]; then
    info "Preserving existing secrets from .env"
    POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(env_get POSTGRES_PASSWORD "$existing_env")}"
    JWT_SECRET="${JWT_SECRET:-$(env_get JWT_SECRET "$existing_env")}"
    SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY:-$(env_get SUPABASE_ANON_KEY "$existing_env")}"
    SUPABASE_SERVICE_ROLE_KEY="${SUPABASE_SERVICE_ROLE_KEY:-$(env_get SUPABASE_SERVICE_ROLE_KEY "$existing_env")}"
  fi

  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -hex 24)}"
  JWT_SECRET="${JWT_SECRET:-$(openssl rand -base64 32)}"
  DASHBOARD_PASSWORD_HASH=$(echo -n "$AGENTOS_DASHBOARD_PASSWORD" | sha256sum | awk '{print $1}')

  # Generate JWT keys if not already set
  if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
    SUPABASE_ANON_KEY=$(generate_jwt "anon" "$JWT_SECRET")
  fi
  if [[ -z "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    SUPABASE_SERVICE_ROLE_KEY=$(generate_jwt "service_role" "$JWT_SECRET")
  fi

  success "Secrets ready"
}

generate_jwt() {
  local role="$1"
  local secret="$2"
  python3 -c "
import hmac, hashlib, base64, json, time
def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode()
header = b64url(json.dumps({'alg':'HS256','typ':'JWT'}).encode())
now = int(time.time())
payload = b64url(json.dumps({'role':'$role','iss':'supabase','iat':now,'exp':now+315360000}).encode())
sig = b64url(hmac.new('$secret'.encode(), f'{header}.{payload}'.encode(), hashlib.sha256).digest())
print(f'{header}.{payload}.{sig}')
"
}

write_env() {
  cat > "$INSTALL_DIR/.env" << EOF
AGENTOS_ADD_DOMAIN=${AGENTOS_ADD_DOMAIN}
AGENTOS_CADDY_ENABLED=${AGENTOS_CADDY_ENABLED}
AGENTOS_DOMAIN=${AGENTOS_DOMAIN}
AGENTOS_DASHBOARD_URL=${AGENTOS_DASHBOARD_URL}
AGENTOS_DASHBOARD_BIND_IP=${AGENTOS_DASHBOARD_BIND_IP}
AGENTOS_SECURE_COOKIES=${AGENTOS_SECURE_COOKIES}
AGENTOS_TERMINAL_ENABLED=${AGENTOS_TERMINAL_ENABLED}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
DASHBOARD_PASSWORD_HASH=${DASHBOARD_PASSWORD_HASH}
EOF
  chmod 600 "$INSTALL_DIR/.env"
  success ".env written"
}

# ============================================================
# Phase 3: Services
# ============================================================

start_supabase() {
  step "Starting Supabase (PostgreSQL + PostgREST)..."
  cd "$INSTALL_DIR"

  # Start Postgres first
  docker compose up -d supabase-db 2>&1 | grep -v "^$" || true

  # Wait for ready
  info "Waiting for PostgreSQL..."
  for i in $(seq 1 30); do
    if docker exec agentos-db pg_isready -U postgres >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! docker exec agentos-db pg_isready -U postgres >/dev/null 2>&1; then
    error "PostgreSQL failed to start"
    exit 1
  fi
  success "PostgreSQL ready"

  # Start PostgREST
  docker compose up -d supabase-rest 2>&1 | grep -v "^$" || true
  sleep 2

  if curl -sf http://localhost:3001/ >/dev/null 2>&1; then
    success "PostgREST ready on :3001"
  else
    warn "PostgREST may still be starting..."
  fi
}

build_dashboard() {
  step "Building and starting dashboard..."
  cd "$INSTALL_DIR"
  local services=("dashboard")

  if [[ "${AGENTOS_TERMINAL_ENABLED:-false}" == "true" ]]; then
    services+=("terminal-ws")
  else
    docker compose stop terminal-ws >/dev/null 2>&1 || true
    docker compose rm -sf terminal-ws >/dev/null 2>&1 || true
  fi

  docker compose up -d --build "${services[@]}" 2>&1 | tail -5 || true
  sleep 3

  if curl -sf http://localhost:3000 >/dev/null 2>&1; then
    success "Dashboard ready on :3000"
  else
    warn "Dashboard may still be building (check: docker logs agentos-dashboard)"
  fi

  if [[ "${AGENTOS_TERMINAL_ENABLED:-false}" == "true" ]]; then
    if ss -tlnp | grep -q ':3002 '; then
      success "Terminal WebSocket ready on :3002"
    else
      warn "Terminal may still be starting (check: docker logs agentos-terminal)"
    fi
  else
    info "Web terminal disabled because domain setup was skipped"
  fi
}

configure_caddy() {
  if [[ "${AGENTOS_CADDY_ENABLED:-false}" != "true" ]]; then
    warn "Skipping Caddy configuration because domain setup was skipped"
    return
  fi

  step "Configuring Caddy..."

  # Write Caddyfile with actual domain + terminal WebSocket
  cat > /etc/caddy/Caddyfile << EOF
dashboard.${AGENTOS_DOMAIN} {
	reverse_proxy /ws/terminal localhost:3002
	reverse_proxy localhost:3000
}
EOF

  systemctl enable caddy --now 2>/dev/null || true
  systemctl reload caddy 2>/dev/null || caddy reload --config /etc/caddy/Caddyfile 2>/dev/null || true
  success "Caddy configured for dashboard.${AGENTOS_DOMAIN}"
}

disable_caddy() {
  if [[ "${AGENTOS_CADDY_ENABLED:-false}" == "true" ]]; then
    return
  fi

  if ! command -v caddy &>/dev/null; then
    info "Caddy not installed (domain setup skipped)"
    return
  fi

  step "Disabling Caddy..."
  systemctl disable --now caddy 2>/dev/null || true
  success "Caddy disabled because domain setup was skipped"
}

# ============================================================
# Phase 4: Claude Code Setup
# ============================================================

deploy_scripts() {
  step "Deploying scripts..."
  chmod +x "$INSTALL_DIR"/scripts/*.sh 2>/dev/null || true
  # Ensure agentos user can execute
  chown -R "$AGENTOS_USER":"$AGENTOS_USER" "$INSTALL_DIR"/scripts/
  chown -R "$AGENTOS_USER":"$AGENTOS_USER" "$INSTALL_DIR"/logs/
  success "Scripts deployed"
}

setup_terminal_ssh() {
  if [[ "${AGENTOS_TERMINAL_ENABLED:-false}" != "true" ]]; then
    info "Skipping web terminal SSH setup because domain setup was skipped"
    return
  fi

  step "Setting up SSH keypair for web terminal..."
  local key_path="$INSTALL_DIR/terminal-ssh-key"
  if [[ -f "$key_path" ]]; then
    info "SSH keypair already exists"
  else
    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "agentos-terminal" >/dev/null 2>&1
    success "SSH keypair generated"
  fi

  # Install public key for agentos user
  local ssh_dir="/home/$AGENTOS_USER/.ssh"
  mkdir -p "$ssh_dir"
  local pub_key=$(cat "${key_path}.pub")
  local auth_file="$ssh_dir/authorized_keys"

  # Add key if not already present
  if ! grep -qF "agentos-terminal" "$auth_file" 2>/dev/null; then
    echo "from=\"172.16.0.0/12\" $pub_key" >> "$auth_file"
  fi

  chmod 700 "$ssh_dir"
  chmod 600 "$auth_file"
  chown -R "$AGENTOS_USER":"$AGENTOS_USER" "$ssh_dir"
  chmod 644 "${key_path}.pub"
  success "Terminal SSH key installed"
}

write_credentials() {
  step "Setting up credentials..."
  local cred_dir="/home/$AGENTOS_USER/.claude/credentials"
  mkdir -p "$cred_dir"

  cat > "$cred_dir/supabase.env" << EOF
SUPABASE_URL=http://localhost:3001
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
SUPABASE_SERVICE_ROLE_KEY=${SUPABASE_SERVICE_ROLE_KEY}
EOF

  chmod 700 "$cred_dir"
  chmod 600 "$cred_dir"/*.env
  chown -R "$AGENTOS_USER":"$AGENTOS_USER" "/home/$AGENTOS_USER/.claude"
  success "Credentials written"
}

configure_claude() {
  step "Configuring Claude Code..."
  local claude_dir="/home/$AGENTOS_USER/.claude"
  mkdir -p "$claude_dir"

  # Settings with SessionStart hook
  if [[ -f "$INSTALL_DIR/config/settings.json" ]]; then
    cp "$INSTALL_DIR/config/settings.json" "$claude_dir/settings.json"
  else
    cat > "$claude_dir/settings.json" << 'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash /opt/agentos/scripts/memory-load.sh"
          }
        ]
      }
    ]
  }
}
EOF
  fi

  # Deploy VPS CLAUDE.md
  if [[ -f "$INSTALL_DIR/config/claude-vps.md" ]]; then
    local vps_claude="/home/$AGENTOS_USER/CLAUDE.md"
    cp "$INSTALL_DIR/config/claude-vps.md" "$vps_claude"
    sed -i "s|DASHBOARD_URL|${AGENTOS_DASHBOARD_URL}|g" "$vps_claude"
    chown "$AGENTOS_USER":"$AGENTOS_USER" "$vps_claude"
  fi

  # Skip all permission prompts — autonomous agent needs full access
  cat > "$claude_dir/settings.local.json" << 'EOF'
{
  "permissions": {
    "dangerouslySkipPermissions": true
  }
}
EOF

  # Pre-configure Telegram bot token if provided
  if [[ -n "${AGENTOS_TELEGRAM_TOKEN:-}" ]]; then
    local tg_dir="$claude_dir/channels/telegram"
    mkdir -p "$tg_dir"
    echo "TELEGRAM_BOT_TOKEN=${AGENTOS_TELEGRAM_TOKEN}" > "$tg_dir/.env"
    chmod 600 "$tg_dir/.env"
    success "Telegram bot token pre-configured"
  fi

  chown -R "$AGENTOS_USER":"$AGENTOS_USER" "$claude_dir"
  success "Claude Code configured"
}

install_crontab() {
  step "Installing cron jobs..."
  local log_dir="/opt/agentos/logs"
  mkdir -p "$log_dir"
  chown "$AGENTOS_USER":"$AGENTOS_USER" "$log_dir"

  local cron_content="# AgentOS-CC automation
*/5 * * * * /opt/agentos/scripts/watchdog.sh >> /opt/agentos/logs/watchdog.log 2>&1
*/5 * * * * /opt/agentos/scripts/sync-secrets.sh >> /opt/agentos/logs/secrets-sync.log 2>&1
*/10 * * * * /opt/agentos/scripts/security-sync.sh >> /opt/agentos/logs/security.log 2>&1
*/10 * * * * /opt/agentos/scripts/server-health.sh >> /opt/agentos/logs/health.log 2>&1
*/30 * * * * /opt/agentos/scripts/sync-sessions.sh >> /opt/agentos/logs/sync.log 2>&1
0 */2 * * * /opt/agentos/scripts/daily-summary.sh >> /opt/agentos/logs/summary-\$(date +\\%Y-\\%m-\\%d).log 2>&1
0 3 * * * /opt/agentos/scripts/memory-consolidate.sh >> /opt/agentos/logs/consolidation.log 2>&1
*/5 * * * * /opt/agentos/scripts/tasks.sh sync >> /opt/agentos/logs/tasks-sync.log 2>&1"

  echo "$cron_content" | crontab -u "$AGENTOS_USER" -
  success "8 cron jobs installed for $AGENTOS_USER"
}

install_claude_code() {
  step "Installing Claude Code CLI..."

  local user_home="/home/$AGENTOS_USER"
  local bashrc="$user_home/.bashrc"

  # Ensure ~/.local/bin exists and is in PATH for the agentos user
  sudo -u "$AGENTOS_USER" mkdir -p "$user_home/.local/bin"
  if ! grep -q '.local/bin' "$bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$bashrc"
    chown "$AGENTOS_USER":"$AGENTOS_USER" "$bashrc"
  fi

  if sudo -u "$AGENTOS_USER" bash -lc 'which claude' &>/dev/null; then
    info "Claude Code already installed"
    return
  fi

  # Run installer with ~/.local/bin already in PATH so it doesn't warn
  sudo -u "$AGENTOS_USER" bash -c 'export PATH="$HOME/.local/bin:$PATH"; curl -fsSL https://claude.ai/install.sh | bash' 2>&1 || {
    warn "Auto-install failed. You may need to install Claude Code manually as '$AGENTOS_USER'."
  }

  if sudo -u "$AGENTOS_USER" bash -lc 'which claude' &>/dev/null; then
    success "Claude Code installed"
  else
    warn "Claude Code not found in PATH. You may need to install it manually."
  fi
}

# ============================================================
# Phase 5: Initial Sync + Interactive Handoff
# ============================================================

run_initial_sync() {
  step "Running initial data sync..."
  # Run as agentos user so credentials are found
  sudo -u "$AGENTOS_USER" bash "$INSTALL_DIR/scripts/security-sync.sh" 2>/dev/null || true
  sudo -u "$AGENTOS_USER" bash "$INSTALL_DIR/scripts/server-health.sh" 2>/dev/null || true
  success "Initial sync complete"
}

print_banner() {
  echo ""
  echo -e "${GREEN}============================================${NC}"
  echo -e "${GREEN}  AgentOS-CC Installation Complete!${NC}"
  echo -e "${GREEN}============================================${NC}"
  echo ""
  if [[ "${AGENTOS_CADDY_ENABLED:-false}" == "true" ]]; then
    echo -e "  Dashboard: ${BLUE}${AGENTOS_DASHBOARD_URL}${NC}"
  else
    echo -e "  Dashboard (local): ${BLUE}http://localhost:3000${NC}"
    echo -e "  Dashboard (VPS):   ${BLUE}http://<server-ip>:3000${NC}"
    echo -e "  Caddy:             ${YELLOW}disabled (domain setup skipped)${NC}"
    echo -e "  Web terminal:      ${YELLOW}disabled without domain/Caddy routing${NC}"
  fi
  echo -e "  Password:  (the one you entered)"
  echo ""
  echo -e "  ${YELLOW}NEXT STEPS:${NC}"
  echo ""
  echo "  1. You will be switched to the '$AGENTOS_USER' user"
  echo "  2. Run: claude"
  echo "  3. Complete browser authentication (follow the URL)"
  echo ""
  if [[ -n "${AGENTOS_TELEGRAM_TOKEN:-}" ]]; then
    echo -e "  ${GREEN}Telegram token was pre-configured.${NC} Continue with:"
    echo ""
    echo "  4. Install the Telegram plugin inside Claude Code:"
    echo "     /plugin install telegram@claude-plugins-official"
    echo "  5. Configure Telegram (token is already saved):"
    echo "     /telegram:configure"
    echo "  6. DM your bot on Telegram — it replies with a 6-char pairing code"
    echo "  7. Pair:    /telegram:access pair <CODE>"
    echo "  8. Lock:    /telegram:access policy allowlist"
    echo "  9. Type /exit to leave Claude Code"
    echo "  10. Relaunch with Telegram channel enabled:"
    echo "      claude --channels plugin:telegram@claude-plugins-official"
  else
    echo "  4. Run the guided Telegram setup:"
    echo "     bash /opt/agentos/scripts/telegram-setup.sh"
    echo ""
    echo "     This walks you through creating a bot, configuring the"
    echo "     token, installing the plugin, and pairing your account."
    echo ""
    echo "     Or set AGENTOS_TELEGRAM_TOKEN beforehand to skip prompts."
  fi
  echo ""
  echo "  The watchdog will keep Claude Code running with Telegram"
  echo "  in a tmux session. You can safely disconnect after setup."
  echo ""
  echo -e "  ${BLUE}Post-install: bash /opt/agentos/scripts/status.sh${NC}"
  echo ""
  echo -e "${GREEN}============================================${NC}"
  echo ""
  echo -e "  Switching to ${AGENTOS_USER} user now..."
  echo ""
}

# ============================================================
# Main
# ============================================================

main() {
  echo ""
  echo -e "${GREEN}AgentOS-CC Bootstrap Installer${NC}"
  echo "=============================="
  echo ""

  check_root
  check_os

  # Phase 1: System
  create_user
  install_deps
  install_nodejs
  install_bun
  clone_repo

  # Phase 2: Config
  collect_config
  install_caddy
  generate_secrets
  write_env

  # Phase 3: Services
  setup_terminal_ssh
  start_supabase
  build_dashboard
  if [[ "${AGENTOS_CADDY_ENABLED:-false}" == "true" ]]; then
    configure_caddy
  else
    disable_caddy
  fi

  # Phase 4: Claude Code
  deploy_scripts
  write_credentials
  configure_claude
  install_crontab
  install_claude_code

  # Phase 5: Sync + Handoff
  run_initial_sync
  print_banner

  # Switch to agentos user for interactive Claude Code auth
  su - "$AGENTOS_USER"
}

main "$@"
