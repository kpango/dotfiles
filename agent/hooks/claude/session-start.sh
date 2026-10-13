#!/usr/bin/env bash
# SessionStart hook — injects memory context at session start
#
# I/Oプロトコル変換(セッションログ書き込み・hookSpecificOutput整形)を担う。メモリ検索/注入ロジック
# 自体は下記の supermemory 経由(agent/scripts/hooks/supermemory.sh)。
set -euo pipefail

# Read the hook's stdin JSON once, before deriving SESSION_ID; nothing else in this
# file reads stdin.
# session_id comes from the hook's stdin JSON (a documented common hook input field;
# the undocumented CLAUDE_SESSION_ID env var is not used). jq validates the JSON
# value: it must be a string made only of ASCII A-Z a-z 0-9 . _ - and not "." or ".."
# (the same allowed set as agent/scripts/jev/evidence_reducer.py's
# _sanitize_session_id), otherwise "unknown". Checking in jq rather than with bash
# `[[ =~ ]]` avoids two problems: bash range matching is locale-dependent, and $()
# strips a trailing newline before bash could see it. \A...\z is used because `$` also
# matches just before a final newline.
INPUT=$(cat 2>/dev/null || true)
SESSION_ID=$(printf '%s' "$INPUT" | jq -rs '(.[0] | if type == "object" then .session_id else null end) as $s | if ($s | type) == "string" and ($s | test("\\A[A-Za-z0-9._-]+\\z")) and $s != "." and $s != ".." then $s else "unknown" end' 2>/dev/null || echo unknown)
SESSION_ID=${SESSION_ID:-unknown}
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# Log session start
LOG_DIR="$HOME/.claude/session-data"
mkdir -p "$LOG_DIR"
date +%s > "$LOG_DIR/.session-${SESSION_ID:0:8}.start" 2>/dev/null || true

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成したmerged directory
# (per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
# Memory injection now uses the locally self-hosted supermemory server (RAG retrieval)
# instead of the decide.py memory_context markdown dump (migrated 2026-09-08,
# supermemory-migration mission). The ~/.claude/memory corpus was ingested into
# supermemory (containerTag claude-memory); sm_inject returns a small query-relevant
# subset. Degrades gracefully to empty when the server is unreachable.
CONTEXT=""
if [[ -f "$ROOT/agent/scripts/hooks/supermemory.sh" ]]; then
    # A sourcing failure (permission error, a future syntax error) must degrade to
    # empty context like every other failure mode here, not abort session start.
    # shellcheck source=/dev/null
    . "$ROOT/agent/scripts/hooks/supermemory.sh" || true
    CONTEXT="$(sm_inject "$(pwd)" claude-memory 2>/dev/null || true)"
fi

CONTEXT_BYTES=${#CONTEXT}
echo "[$TIMESTAMP] Session started: ${SESSION_ID:0:8} cwd=$(pwd) memory=supermemory/${CONTEXT_BYTES}bytes" >> "$LOG_DIR/sessions.log" 2>/dev/null || true

if command -v jq &>/dev/null && [[ -n "$CONTEXT" ]]; then
    CONTEXT_JSON=$(jq -Rs . <<< "$CONTEXT")
    printf '{"continue":true,"suppressOutput":true,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}' "$CONTEXT_JSON"
else
    printf '{"continue":true,"suppressOutput":true}'
fi
