#!/usr/bin/env bash
# swarm-parallel-gate.sh (PreToolUse:Task|Agent hook) + parallel-gate.sh の regression test。
# SWARM.md §1「実装層 Maker/Checker の並列実行は独立タスクにつき最大3並列まで」の機械強制を検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# $SCRIPT_DIR = agent/skills/swarm-implement/scripts。実hookは agent/hooks/claude/ 配下
# (2026-09-04、claude-hooks-full-agent-consolidationミッションでclaude/hooks/配下の残存全ファイルを
# agent/hooks/claude/へ実体移動したことに伴う変更。旧パスは4階層上がってclaude/hooks/へ入る必要が
# あったが、新パスは3階層上がってhooks/claude/へ入る)。
GATE_HOOK="$(cd "$SCRIPT_DIR/../../../hooks/claude" && pwd)/swarm-parallel-gate.sh"
PARALLEL_GATE="$SCRIPT_DIR/parallel-gate.sh"
# PARALLEL_GATE_MAX_SLOTSを実強制側(swarm-parallel-gate.sh)・表示側(parallel-gate.sh)と同じ
# fable-budget.confから読む(2026-09-04、Phase 4.5敵対的レビュー〈code-quality/shell-config両方が
# 独立指摘〉で発見: このテストはconfへ集約された定数を使わず`3`を直書きしていたため、将来
# PARALLEL_GATE_MAX_SLOTSが変更されてもこのテストは気づかず古い閾値のまま検証し続ける状態だった)。
# shellcheck disable=SC1090
[ -f "$SCRIPT_DIR/fable-budget.conf" ] && . "$SCRIPT_DIR/fable-budget.conf"
: "${PARALLEL_GATE_MAX_SLOTS:=3}"
export HOME="$(mktemp -d)" # 実スロットを汚さず、実運用中の他ミッションのスロットに影響されない隔離 HOME
trap 'rm -rf "$HOME"' EXIT
SLOTS_DIR="$HOME/.claude/session-data/swarm/.parallel-slots"

pass_count=0
fail_count=0
pass() { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail() { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }

spawn() { # <task-id-or-empty-for-no-marker>
  local prompt
  if [ -n "$1" ]; then
    prompt="Maker for [parallel-task:$1] please implement"
  else
    prompt="no marker here, unrelated research agent"
  fi
  jq -nc --arg p "$prompt" '{tool_name:"Agent",tool_input:{prompt:$p}}' | bash "$GATE_HOOK"
}

# case 1: no marker -> unaffected, exit 0, no slot created
if spawn "" >/tmp/pg_case1.out 2>&1; then
  pass "case1: no-marker agent exits 0"
else
  fail "case1: no-marker agent should exit 0"
fi
if [ "$(find "$SLOTS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)" -eq 0 ]; then
  pass "case1: no slot created for no-marker agent"
else
  fail "case1: unexpected slot created for no-marker agent"
fi

# case 2: task-A acquires slot 1
if spawn test-pg-A >/dev/null 2>&1; then
  pass "case2: task-A acquires slot"
else
  fail "case2: task-A should be allowed"
fi
[ -f "$SLOTS_DIR/test-pg-A" ] && pass "case2: slot file exists for task-A" || fail "case2: slot file missing for task-A"

# case 3: task-A again (idempotent, e.g. Checker after Maker) -> still allowed, still 1 slot from this test's set
if spawn test-pg-A >/dev/null 2>&1; then
  pass "case3: task-A re-acquire (idempotent) exits 0"
else
  fail "case3: task-A re-acquire should exit 0"
fi

# case 4: task-B, task-C also acquire (fill up to however many pre-existing + these 3)
spawn test-pg-B >/dev/null 2>&1 || true
spawn test-pg-C >/dev/null 2>&1 || true

# case 5: if the tree currently has >=$PARALLEL_GATE_MAX_SLOTS active slots, task-D must be blocked;
# otherwise it must succeed. (this test file only asserts the invariant, not an absolute count, since
# other concurrent sessions could hold slots on a real host — but in an isolated CI/test run count
# should be exactly our PARALLEL_GATE_MAX_SLOTS.)
active=$(find "$SLOTS_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$active" -ge "$PARALLEL_GATE_MAX_SLOTS" ]; then
  if spawn test-pg-D >/dev/null 2>&1; then
    fail "case5: task-D should be BLOCKED when $active slots are active"
  else
    pass "case5: task-D correctly blocked when $active slots are active"
  fi
else
  if spawn test-pg-D >/dev/null 2>&1; then
    pass "case5: task-D allowed when only $active slots active"
  else
    fail "case5: task-D should be allowed when only $active slots active"
  fi
fi

# case 6: release via parallel-gate.sh --release, then --status reflects it
bash "$PARALLEL_GATE" --release test-pg-A >/dev/null 2>&1
if [ ! -f "$SLOTS_DIR/test-pg-A" ]; then
  pass "case6: --release removes task-A's slot"
else
  fail "case6: task-A's slot should be removed after --release"
fi

echo "----"
echo "pass=$pass_count fail=$fail_count"
[ "$fail_count" -eq 0 ]
