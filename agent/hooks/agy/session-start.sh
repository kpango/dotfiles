#!/usr/bin/env bash
# Antigravity SessionStart Hook — injects auto-memory context and logs session metadata
#
# メモリdir/ローカルoverrideファイルの走査・合成ロジックは agent/scripts/hooks/memory_context.py +
# decide.py へ統合済み(2026-09-03、agent/hooks/claude/session-start.shと独立に再実装されていたロジックを
# 1箇所化)。本ファイルはI/Oプロトコル変換(セッションログ書き込み・JSON整形)のみ。
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
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

CONTEXT=""
TOTAL_FILES=0
if [[ -f "$DECIDE" ]] && command -v python3 &>/dev/null && command -v jq &>/dev/null; then
    # 走査順は旧実装どおり ~/.gemini/memory を先に見る(重複排除は先勝ち)。
    REQUEST=$(jq -n --arg d1 "$HOME/.gemini/memory" --arg d2 "$HOME/.claude/memory" --arg cwd "$(pwd)" \
        '{family: "memory_context", memory_dirs: [$d1, $d2],
          local_files: ["AGENTS.local.md", "CLAUDE.local.md"], cwd: $cwd,
          index_head: 200, topic_head: 150, local_head: 150,
          multi_dir_labels: true, local_all_matches: true}')
    if command -v timeout &>/dev/null; then
        RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || RESULT=""
    else
        RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || RESULT=""
    fi
    if [[ -n "$RESULT" ]]; then
        CONTEXT=$(echo "$RESULT" | jq -r '.context // ""' 2>/dev/null || echo "")
        TOTAL_FILES=$(echo "$RESULT" | jq -r '.file_count // 0' 2>/dev/null || echo 0)
    fi
fi

CONTEXT_BYTES=${#CONTEXT}
echo "[$TIMESTAMP] AGY Session started: ${SESSION_ID:0:8} cwd=$(pwd) memory_files=${TOTAL_FILES} bytes=${CONTEXT_BYTES}" >> "$LOG_DIR/sessions.log" 2>/dev/null || true

if command -v jq &>/dev/null && [[ -n "$CONTEXT" ]]; then
    CONTEXT_JSON=$(jq -Rs . <<< "$CONTEXT")
    printf '{"continue":true,"decision":"allow","context":%s}\n' "$CONTEXT_JSON"
else
    printf '{"continue":true,"decision":"allow"}\n'
fi

exit 0
