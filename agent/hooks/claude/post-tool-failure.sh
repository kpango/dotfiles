#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat || true)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
ERROR=$(echo "$INPUT" | jq -r '.error // "unknown error"' 2>/dev/null || echo "unknown error")
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
# session_id comes from the hook's stdin JSON (a documented common hook input field;
# the undocumented CLAUDE_SESSION_ID env var is not used). jq validates the JSON
# value: it must be a string made only of ASCII A-Z a-z 0-9 . _ - and not "." or ".."
# (the same allowed set as agent/scripts/jev/evidence_reducer.py's
# _sanitize_session_id), otherwise "unknown". Checking in jq rather than with bash
# `[[ =~ ]]` avoids two problems: bash range matching is locale-dependent, and $()
# strips a trailing newline before bash could see it. \A...\z is used because `$` also
# matches just before a final newline.
SESSION_ID=$(printf '%s' "$INPUT" | jq -rs '(.[0] | if type == "object" then .session_id else null end) as $s | if ($s | type) == "string" and ($s | test("\\A[A-Za-z0-9._-]+\\z")) and $s != "." and $s != ".." then $s else "unknown" end' 2>/dev/null || echo unknown)
SESSION_ID=${SESSION_ID:-unknown}
LOG_DIR="${HOME}/.claude/session-data"
mkdir -p "${LOG_DIR}"

ERROR_SHORT="${ERROR:0:200}"
echo "${TIMESTAMP} TOOL_FAILURE session=${SESSION_ID:0:8} ${TOOL}: ${ERROR_SHORT}" >> "${LOG_DIR}/sessions.log"
echo "${TIMESTAMP} session=${SESSION_ID:0:8} tool=${TOOL}: ${ERROR_SHORT}" >> "${LOG_DIR}/tool-failures.log"

if command -v dunstify &>/dev/null; then
    dunstify -u critical "Claude Code: Tool Failure" "${TOOL}: ${ERROR:0:100}" 2>/dev/null || true
fi
