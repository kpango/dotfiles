#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat || true)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
ERROR=$(echo "$INPUT" | jq -r '.error // "unknown error"' 2>/dev/null || echo "unknown error")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

ERROR_SHORT="${ERROR:0:200}"
echo "${TIMESTAMP} TOOL_FAILURE session=${SESSION_ID:0:8} ${TOOL}: ${ERROR_SHORT}" >> "${LOG_DIR}/sessions.log"
echo "${TIMESTAMP} session=${SESSION_ID:0:8} tool=${TOOL}: ${ERROR_SHORT}" >> "${LOG_DIR}/tool-failures.log"

if command -v dunstify &>/dev/null; then
    dunstify -u critical "Claude Code: Tool Failure" "${TOOL}: ${ERROR:0:100}" 2>/dev/null || true
fi
