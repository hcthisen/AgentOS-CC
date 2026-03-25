#!/bin/bash
# task-runner.sh — Execute a scheduled task: run prompt via claude -p, send result to Telegram
# Called by cron: task-runner.sh <task_id>

set -euo pipefail

TASK_ID="${1:?Task ID required}"

CRED_FILE="$HOME/.claude/credentials/supabase.env"
TG_ENV="$HOME/.claude/channels/telegram/.env"

if [[ -f "$CRED_FILE" ]]; then source "$CRED_FILE"; else echo "$(date) ERROR: $CRED_FILE not found" >&2; exit 1; fi
if [[ -f "$TG_ENV" ]]; then source "$TG_ENV"; fi

SUPABASE_URL="${SUPABASE_URL:-http://localhost:3001}"
SUPABASE_KEY="${SUPABASE_SERVICE_ROLE_KEY}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [task:${TASK_ID:0:8}] $*"; }

# Fetch task from Supabase
task_json=$(curl -sf "${SUPABASE_URL}/cc_scheduled_tasks?id=eq.${TASK_ID}&enabled=eq.true&limit=1" \
  -H "apikey: ${SUPABASE_KEY}" \
  -H "Authorization: Bearer ${SUPABASE_KEY}" 2>/dev/null || echo "[]")

# Parse and execute via Python (avoids shell quoting nightmares with prompts/results)
export TASK_JSON="$task_json"
export TASK_ID SUPABASE_URL SUPABASE_KEY
export TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"

python3 << 'PYEOF'
import json, os, subprocess, datetime, sys

task_json = os.environ.get("TASK_JSON", "[]")
task_id = os.environ["TASK_ID"]
supabase_url = os.environ["SUPABASE_URL"]
supabase_key = os.environ["SUPABASE_KEY"]
tg_token = os.environ.get("TELEGRAM_BOT_TOKEN", "")

data = json.loads(task_json)
if not data:
    print(f"Task {task_id[:8]} not found or disabled")
    sys.exit(0)

task = data[0]
name = task.get("name", "Unnamed task")
prompt = task.get("prompt", "")
chat_id = task.get("chat_id", "")
model = task.get("model", "opus")

if not prompt:
    print("Empty prompt, skipping")
    sys.exit(0)

print(f"Running task: {name}")

# Run the prompt via claude -p
try:
    result = subprocess.run(
        ["claude", "-p", "--model", model, prompt],
        capture_output=True, text=True, timeout=120
    )
    output = result.stdout.strip()
    if not output:
        output = "(No output generated)"
except subprocess.TimeoutExpired:
    output = "(Task timed out after 120s)"
except Exception as e:
    output = f"(Task error: {e})"

print(f"Output: {output[:200]}...")

# Send to Telegram
if chat_id and tg_token:
    message = f"{name}\n\n{output}"
    if len(message) > 4000:
        message = message[:3997] + "..."

    try:
        payload = json.dumps({"chat_id": chat_id, "text": message})
        r = subprocess.run([
            "curl", "-sf", "-X", "POST",
            f"https://api.telegram.org/bot{tg_token}/sendMessage",
            "-H", "Content-Type: application/json",
            "-d", payload
        ], capture_output=True, text=True, timeout=30)
        if r.returncode == 0:
            print(f"Sent to Telegram chat {chat_id}")
        else:
            print(f"Telegram send failed: {r.stderr}")
    except Exception as e:
        print(f"Telegram error: {e}")

# Update last_run and last_result
update = json.dumps({
    "last_run": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "last_result": output[:2000],
    "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat()
})

subprocess.run([
    "curl", "-sf", "-X", "PATCH",
    f"{supabase_url}/cc_scheduled_tasks?id=eq.{task_id}",
    "-H", f"apikey: {supabase_key}",
    "-H", f"Authorization: Bearer {supabase_key}",
    "-H", "Content-Type: application/json",
    "-d", update
], capture_output=True, timeout=10)

print("Task complete")
PYEOF
