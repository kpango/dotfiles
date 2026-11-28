#!/usr/bin/env bash
# SessionStart hook — logs session start metadata
set -euo pipefail

# Read the hook's stdin JSON once, before deriving SESSION_ID; nothing else in this
# file reads stdin.
# session_id comes from the hook's stdin JSON (a documented common hook input field;
# the undocumented CLAUDE_SESSION_ID env var is not used). jq validates the JSON
# value: it must be a string made only of ASCII A-Z a-z 0-9 . _ - and not "." or ".."
# (the same allowed set as _sanitize_session_id), otherwise "unknown".
# Checking in jq rather than with bash `[[ =~ ]]` avoids two problems: bash range
# matching is locale-dependent, and $() strips a trailing newline before bash could
# see it. \A...\z is used because `$` also matches just before a final newline.
INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -rs '(.[0] | if type == "object" then .session_id else null end) as $s | if ($s | type) == "string" and ($s | test("\\A[A-Za-z0-9._-]+\\z")) and $s != "." and $s != ".." then $s else "unknown" end' 2>/dev/null || echo unknown)
SESSION_ID=${SESSION_ID:-unknown}
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log session start
LOG_DIR="$HOME/.claude/session-data"
mkdir -p "$LOG_DIR"
date +%s > "$LOG_DIR/.session-${SESSION_ID:0:8}.start" 2>/dev/null || true

echo "[$TIMESTAMP] Session started: ${SESSION_ID:0:8} cwd=$(pwd)" >> "$LOG_DIR/sessions.log" 2>/dev/null || true

printf '{"continue":true,"suppressOutput":true}'
