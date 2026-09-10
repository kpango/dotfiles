#!/usr/bin/env bash
# agent/scripts/hooks/memory_context.py を実際に消費する実装(agent/hooks/claude/session-start.sh・
# agent/hooks/agy/session-start.sh・agent/hooks/pi/auto-memory.ts)を横断的に検証する統合テスト。
#
# usage: agent/scripts/test-memory-context.sh
# exit: 0 = 全テストPASS, 1 = 1件以上FAIL
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"
CLAUDE_HOOK="$ROOT/agent/hooks/claude/session-start.sh"
AGY_HOOK="$ROOT/agent/hooks/agy/session-start.sh"

total_fail=0
section() { echo; echo "=== $1 ==="; }

FIXTURE="$(mktemp -d)"
mkdir -p "$FIXTURE/dirA" "$FIXTURE/dirB" "$FIXTURE/cwd"
cat > "$FIXTURE/dirA/MEMORY.md" << 'EOF'
# Memory Index
- topic_a
- topic_b
EOF
cat > "$FIXTURE/dirA/topic_a.md" << 'EOF'
content A
EOF
cat > "$FIXTURE/dirA/topic_b.md" << 'EOF'
content B (from dirA, should win dedup)
EOF
cat > "$FIXTURE/dirB/topic_b.md" << 'EOF'
content B (from dirB, should be deduped away)
EOF
cat > "$FIXTURE/dirB/topic_c.md" << 'EOF'
content C (only in dirB)
EOF
cat > "$FIXTURE/cwd/CLAUDE.local.md" << 'EOF'
local claude override
EOF
cat > "$FIXTURE/cwd/AGENTS.local.md" << 'EOF'
local agents override
EOF
cleanup() { rm -rf "$FIXTURE" 2>/dev/null || python3 -c "import shutil; shutil.rmtree('$FIXTURE', ignore_errors=True)"; }
trap cleanup EXIT

check_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "[OK] $desc"
    else
        echo "[FAIL] $desc : expected to find '$needle'"
        total_fail=$((total_fail + 1))
    fi
}
check_not_contains() {
    local desc="$1" haystack="$2" needle="$3"
    if echo "$haystack" | grep -qF -- "$needle"; then
        echo "[FAIL] $desc : did not expect to find '$needle'"
        total_fail=$((total_fail + 1))
    else
        echo "[OK] $desc"
    fi
}

section "decide.py memory_context family (直接呼び出し)"

REQUEST_SINGLE=$(jq -n --arg d "$FIXTURE/dirA" --arg cwd "$FIXTURE/cwd" \
    '{family:"memory_context", memory_dirs:[$d], local_files:["CLAUDE.local.md"], cwd:$cwd,
      index_head:200, topic_head:150, local_head:null, multi_dir_labels:false, local_all_matches:false}')
RESULT_SINGLE=$(echo "$REQUEST_SINGLE" | python3 "$DECIDE")
CTX_SINGLE=$(echo "$RESULT_SINGLE" | jq -r '.context')
check_contains "claude方式: dirAのtopic_a本文を含む" "$CTX_SINGLE" "content A"
check_contains "claude方式: CLAUDE.local.mdを含む" "$CTX_SINGLE" "local claude override"
check_not_contains "claude方式: AGENTS.local.mdは対象外" "$CTX_SINGLE" "local agents override"
FILE_COUNT_SINGLE=$(echo "$RESULT_SINGLE" | jq -r '.file_count')
[[ "$FILE_COUNT_SINGLE" == "2" ]] && echo "[OK] claude方式: file_count=2" || { echo "[FAIL] claude方式: file_count expected=2 got=$FILE_COUNT_SINGLE"; total_fail=$((total_fail + 1)); }

REQUEST_MULTI=$(jq -n --arg d1 "$FIXTURE/dirA" --arg d2 "$FIXTURE/dirB" --arg cwd "$FIXTURE/cwd" \
    '{family:"memory_context", memory_dirs:[$d1,$d2], local_files:["AGENTS.local.md","CLAUDE.local.md"], cwd:$cwd,
      index_head:200, topic_head:150, local_head:150, multi_dir_labels:true, local_all_matches:true}')
RESULT_MULTI=$(echo "$REQUEST_MULTI" | python3 "$DECIDE")
CTX_MULTI=$(echo "$RESULT_MULTI" | jq -r '.context')
check_contains "agy方式: dirAのtopic_bが優先される(先勝ちdedup)" "$CTX_MULTI" "content B (from dirA, should win dedup)"
check_not_contains "agy方式: dirBのtopic_bは重複排除される" "$CTX_MULTI" "content B (from dirB, should be deduped away)"
check_contains "agy方式: dirB限定のtopic_cも含まれる" "$CTX_MULTI" "content C (only in dirB)"
check_contains "agy方式: AGENTS.local.mdを含む" "$CTX_MULTI" "local agents override"
check_contains "agy方式: CLAUDE.local.mdも両方含む" "$CTX_MULTI" "local claude override"
check_contains "agy方式: Memory Indexヘッダを含む" "$CTX_MULTI" "# Memory Index (dirA/MEMORY.md)"
check_contains "agy方式: トピックヘッダを含む" "$CTX_MULTI" "## Memory: topic_a.md"
FILE_COUNT_MULTI=$(echo "$RESULT_MULTI" | jq -r '.file_count')
[[ "$FILE_COUNT_MULTI" == "3" ]] && echo "[OK] agy方式: file_count=3(dedup後)" || { echo "[FAIL] agy方式: file_count expected=3 got=$FILE_COUNT_MULTI"; total_fail=$((total_fail + 1)); }

section "agent/hooks/claude/session-start.sh (実ファイル経由)"
if [[ -f "$CLAUDE_HOOK" ]]; then
    OUT=$(echo '{}' | CLAUDE_MEMORY_DIR="$FIXTURE/dirA" CLAUDE_SESSION_ID="test-mc" bash "$CLAUDE_HOOK" 2>&1)
    CTX=$(echo "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    check_contains "claude session-start: dirAのcontentを注入" "$CTX" "content A"
else
    echo "[SKIP] agent/hooks/claude/session-start.sh not found"
fi

section "agent/hooks/agy/session-start.sh (実ファイル経由、実HOME参照のためallow判定のみ確認)"
if [[ -f "$AGY_HOOK" ]]; then
    OUT=$(echo '{"session_id":"test-mc"}' | bash "$AGY_HOOK" 2>&1)
    DECISION=$(echo "$OUT" | jq -r '.decision // empty' 2>/dev/null)
    [[ "$DECISION" == "allow" ]] && echo "[OK] agy session-start: decision=allow" || { echo "[FAIL] agy session-start: expected decision=allow got=$DECISION"; total_fail=$((total_fail + 1)); }
else
    echo "[SKIP] agent/hooks/agy/session-start.sh not found"
fi

echo
if [[ "$total_fail" -eq 0 ]]; then
    echo "test-memory-context: 全テストPASS"
    exit 0
else
    echo "test-memory-context: ${total_fail} 件のFAILあり"
    exit 1
fi
