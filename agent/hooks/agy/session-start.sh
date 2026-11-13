#!/usr/bin/env bash
# Antigravity SessionStart Hook — injects auto-memory context and logs session metadata
#
# I/Oプロトコル変換(セッションログ書き込み・JSON整形)を担う。メモリ検索/注入ロジック自体は下記の
# supermemory 経由(agent/scripts/hooks/supermemory.sh)。
set -euo pipefail

PAYLOAD=$(cat || true)

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SESSION_ID="unknown"

if command -v jq &>/dev/null && [[ -n "$PAYLOAD" ]]; then
    SESSION_ID=$(echo "$PAYLOAD" | jq -r 'if type=="object" then (.session_id // .sessionId // "unknown") else "unknown" end' 2>/dev/null || echo "unknown")
fi

LOG_DIR="$HOME/.gemini/session-data"
mkdir -p "$LOG_DIR"

# ~/.agy/hooks・~/.gemini/hooks は agy/hooks/ と agent/hooks/agy/ の2ソースを合成したmerged
# directory(per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
# Memory injection now uses the locally self-hosted supermemory server (RAG retrieval)
# instead of the decide.py memory_context markdown dump (migrated 2026-09-08,
# supermemory-migration mission). The shared knowledge base (formerly ~/.claude/memory
# + ~/.gemini/memory) was ingested into supermemory (containerTag claude-memory).
# Degrades gracefully to empty when the server is unreachable.
CONTEXT=""
if [[ -f "$ROOT/agent/scripts/hooks/supermemory.sh" ]]; then
    # A sourcing failure (permission error, a future syntax error) must degrade to
    # empty context like every other failure mode here, not abort session start.
    # shellcheck source=/dev/null
    . "$ROOT/agent/scripts/hooks/supermemory.sh" || true
    CONTEXT="$(sm_inject "$(pwd)" claude-memory 2>/dev/null || true)"
fi

CONTEXT_BYTES=${#CONTEXT}
echo "[$TIMESTAMP] AGY Session started: ${SESSION_ID:0:8} cwd=$(pwd) memory=supermemory/${CONTEXT_BYTES}bytes" >> "$LOG_DIR/sessions.log" 2>/dev/null || true

if command -v jq &>/dev/null && [[ -n "$CONTEXT" ]]; then
    CONTEXT_JSON=$(jq -Rs . <<< "$CONTEXT")
    printf '{"continue":true,"decision":"allow","context":%s}\n' "$CONTEXT_JSON"
else
    printf '{"continue":true,"decision":"allow"}\n'
fi

exit 0
