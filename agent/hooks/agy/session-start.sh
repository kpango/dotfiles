#!/usr/bin/env bash
# Antigravity SessionStart Hook — logs session metadata
set -euo pipefail

PAYLOAD=$(cat || true)

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_ID="unknown"

if command -v jq &>/dev/null && [[ -n "$PAYLOAD" ]]; then
    SESSION_ID=$(echo "$PAYLOAD" | jq -r 'if type=="object" then (.session_id // .sessionId // "unknown") else "unknown" end' 2>/dev/null || echo "unknown")
fi

LOG_DIR="$HOME/.gemini/session-data"
mkdir -p "$LOG_DIR"

echo "[$TIMESTAMP] AGY Session started: ${SESSION_ID:0:8} cwd=$(pwd)" >> "$LOG_DIR/sessions.log" 2>/dev/null || true

# Refresh the model list `agy models` reports for this run; on failure the cache is marked unavailable.
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
python3 "$HERE/../../scripts/fetch-harness-models.py" agy >/dev/null 2>&1 || true

printf '{"continue":true,"decision":"allow"}\n'

exit 0
