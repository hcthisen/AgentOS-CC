#!/bin/bash
# watchdog.sh — Ensure Claude Code is running in tmux
# Runs every 5 minutes via cron

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

TMUX_SESSION="claude"
CLAUDE_CMD="claude --continue --channels plugin:telegram@claude-plugins-official"

# Check if tmux session exists
if ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
  log "tmux session '$TMUX_SESSION' not found, creating..."
  tmux new-session -d -s "$TMUX_SESSION"
  sleep 1
fi

# Get pane PID
PANE_PID=$(tmux list-panes -t "$TMUX_SESSION" -F '#{pane_pid}' 2>/dev/null | head -1)

if [[ -z "$PANE_PID" ]]; then
  log "ERROR: Could not get pane PID"
  exit 1
fi

# Check if claude is running as a child or grandchild of the pane
claude_running=false

# Check direct children
for child in $(pgrep -P "$PANE_PID" 2>/dev/null); do
  if ps -p "$child" -o comm= 2>/dev/null | grep -q "claude"; then
    claude_running=true
    break
  fi
  # Check grandchildren (shell -> claude)
  for grandchild in $(pgrep -P "$child" 2>/dev/null); do
    if ps -p "$grandchild" -o comm= 2>/dev/null | grep -q "claude"; then
      claude_running=true
      break 2
    fi
  done
done

if $claude_running; then
  log "Claude Code is running (pane PID: $PANE_PID)"
else
  log "Claude Code not found, starting..."
  tmux send-keys -t "$TMUX_SESSION" "$CLAUDE_CMD" Enter
  log "Start command sent to tmux session"
fi
