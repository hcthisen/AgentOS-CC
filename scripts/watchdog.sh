#!/bin/bash
# watchdog.sh — Ensure Claude Code is running in tmux with Telegram channel
# Runs every 5 minutes via cron

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

TMUX_SESSION="claude"
CLAUDE_BIN="$HOME/.local/bin/claude"
CHANNEL_FLAG="--channels plugin:telegram@claude-plugins-official"
PROMPT_WAIT_SECONDS=12
WORKDIR="/opt/agentos"
SESSION_DIR="$HOME/.claude/projects/-root"

pane_text() {
  tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null | tail -n 40 || true
}

handle_startup_prompts() {
  local i
  for i in $(seq 1 "$PROMPT_WAIT_SECONDS"); do
    local content
    content="$(pane_text)"

    if echo "$content" | grep -q "Bypass Permissions mode"; then
      log "Accepting bypass permissions prompt"
      tmux send-keys -t "$TMUX_SESSION" "2" Enter
      sleep 2
      continue
    fi

    if echo "$content" | grep -qi "trust this folder"; then
      log "Accepting trust folder prompt"
      tmux send-keys -t "$TMUX_SESSION" "1" Enter
      sleep 2
      continue
    fi

    if echo "$content" | grep -q "Listening for channel messages"; then
      return
    fi

    sleep 1
  done
}

build_claude_cmd() {
  if compgen -G "$SESSION_DIR/*.jsonl" >/dev/null 2>&1; then
    echo "$CLAUDE_BIN --continue --dangerously-skip-permissions $CHANNEL_FLAG"
  else
    echo "$CLAUDE_BIN --dangerously-skip-permissions $CHANNEL_FLAG"
  fi
}

# Check if tmux session exists
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  log "tmux session '$TMUX_SESSION' not found, creating..."
  tmux new-session -d -s "$TMUX_SESSION" -c "$WORKDIR"
  sleep 1
fi

# Get pane PID
PANE_PID=$(tmux list-panes -t "$TMUX_SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)

if [[ -z "$PANE_PID" ]]; then
  log "ERROR: Could not get pane PID"
  exit 1
fi

# Check if claude is running as a child or grandchild of the pane
claude_pid=""
for child in $(pgrep -P "$PANE_PID" 2>/dev/null); do
  if ps -p "$child" -o comm= 2>/dev/null | grep -q "claude"; then
    claude_pid="$child"
    break
  fi
  for grandchild in $(pgrep -P "$child" 2>/dev/null); do
    if ps -p "$grandchild" -o comm= 2>/dev/null | grep -q "claude"; then
      claude_pid="$grandchild"
      break 2
    fi
  done
done

if [[ -n "$claude_pid" ]]; then
  pane_content="$(pane_text)"
  if echo "$pane_content" | grep -qi "trust this folder\|Bypass Permissions mode"; then
    log "Claude Code is waiting on a startup prompt"
    handle_startup_prompts
    pane_content="$(pane_text)"
  fi

  # Claude is running — verify it has --channels in its command line
  cmdline=$(tr '\0' ' ' < "/proc/$claude_pid/cmdline" 2>/dev/null)
  if echo "$cmdline" | grep -q -- "--channels"; then
    if echo "$pane_content" | grep -q "Listening for channel messages"; then
      log "Claude Code is running with channels (confirmed via pane, PID: $claude_pid)"
    else
      log "Claude Code process is running with channels (PID: $claude_pid)"
    fi
    exit 0
  fi

  # Running without channels — need to restart
  log "Claude Code running WITHOUT channels (PID: $claude_pid), restarting..."
  tmux send-keys -t "$TMUX_SESSION" "/exit" Enter
  sleep 3
  # Fall through to start with channels
fi

# Claude not running (or was just stopped) — start with channels
CLAUDE_CMD="$(build_claude_cmd)"
log "Starting Claude Code with Telegram channel..."
tmux send-keys -t "$TMUX_SESSION" "cd $WORKDIR" Enter
sleep 1
tmux send-keys -t "$TMUX_SESSION" "$CLAUDE_CMD" Enter
handle_startup_prompts
if pane_text | grep -q "No conversation found to continue"; then
  log "No saved conversation found, retrying without --continue"
  tmux send-keys -t "$TMUX_SESSION" "$CLAUDE_BIN --dangerously-skip-permissions $CHANNEL_FLAG" Enter
  handle_startup_prompts
fi
log "Start command sent to tmux session"
