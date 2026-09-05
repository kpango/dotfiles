#!/usr/bin/env bash
# StopFailure hook — log agent stop failures (timeout, max turns, etc.)
set -euo pipefail

INPUT=$(cat || true)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

read -r SESSION_ID STOP_REASON < <(python3 -c "
import json, sys
d = json.load(sys.stdin)
sid = d.get('session_id', 'unknown')
reason = d.get('stop_reason', 'unknown').replace(' ', '_')
print(sid, reason)
" <<< "$INPUT" 2>/dev/null || echo "unknown unknown")

echo "${TIMESTAMP} stop-failure session=${SESSION_ID:0:8} reason=${STOP_REASON}" >> "${LOG_DIR}/sessions.log"
echo "${TIMESTAMP} session=${SESSION_ID:0:8} reason=${STOP_REASON}" >> "${LOG_DIR}/stop-failures.log"

exit 0
