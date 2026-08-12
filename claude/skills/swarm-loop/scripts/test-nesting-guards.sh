#!/usr/bin/env bash
# TDAD Test Maker (RED phase): tests for the NOT-YET-IMPLEMENTED "nested /swarm-loop"
# guard mechanism (depth-limited self-invocation, shared mission budget).
#
# Covers two future features (design案A, /swarm-architect承認済み):
#   1. mission-init.sh: 5th positional arg `depth` (default 0), REFUSE on non-integer
#      or depth>1, `- depth: N` line appended to @fix_plan.md frontmatter.
#   2. budget-guard.sh: `--mission=<root-slug>` / `--mission-max=<N>` flags maintaining
#      a shared counter `_mission-total-<root-slug>` independent of per-task counters,
#      MISSION_BUDGET_EXCEEDED on overflow, `--reset` clearing both.
#
# This script must NOT be used to implement either feature — it only asserts the
# target behavior against the current (unmodified) scripts, expected to be RED.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MISSION_INIT="$SCRIPT_DIR/mission-init.sh"
BUDGET_GUARD="$(cd "$SCRIPT_DIR/../../swarm-implement/scripts" && pwd)/budget-guard.sh"
BUDGET_DIR="$HOME/.claude/session-data/swarm/budget"
MISSIONS_DIR="$HOME/.claude/session-data/swarm/missions"

pass_count=0
fail_count=0
pass() { pass_count=$((pass_count + 1)); echo "PASS: $1"; }
fail() { fail_count=$((fail_count + 1)); echo "FAIL: $1"; }

# ---- cleanup bookkeeping (trap-based, never leaves real budget dir / missions dir / repo dirty) ----
declare -a TMP_REPOS=()
declare -a BUDGET_TASK_IDS=()
declare -a MISSION_SLUGS=()
declare -a MISSION_STATE_SLUGS=()

cleanup() {
  local repo tid slug
  for repo in "${TMP_REPOS[@]}"; do
    [ -n "$repo" ] && [ -d "$repo" ] && rm -rf "$repo"
  done
  for tid in "${BUDGET_TASK_IDS[@]}"; do
    [ -n "$tid" ] && rm -f "$BUDGET_DIR/${tid//\//_}"
  done
  for slug in "${MISSION_SLUGS[@]}"; do
    [ -n "$slug" ] && rm -f "$BUDGET_DIR/_mission-total-${slug}"
  done
  for slug in "${MISSION_STATE_SLUGS[@]}"; do
    [ -n "$slug" ] && [ -d "$MISSIONS_DIR/$slug" ] && rm -rf "$MISSIONS_DIR/$slug"
  done
}
trap cleanup EXIT

new_tmp_repo() {
  local d
  d=$(mktemp -d)
  git -C "$d" init -q
  TMP_REPOS+=("$d")
  printf '%s' "$d"
}

SUFFIX="$$-$RANDOM"

echo "== Group 1: mission-init.sh depth guard =="

# Test 1: depth omitted entirely (existing 4-arg call) -> must keep succeeding (backward compat)
slug="test-slug-nodepth-$SUFFIX"
MISSION_STATE_SLUGS+=("$slug")
repo=$(new_tmp_repo)
if out=$(cd "$repo" && "$MISSION_INIT" "$slug" "goal" "mission" "" 2>&1); then
  pass "mission-init: depth omitted (4-arg call) succeeds (backward compat)"
else
  fail "mission-init: depth omitted should succeed, got: $out"
fi

# Test 2: depth=0 explicit -> success
slug="test-slug-depth0-$SUFFIX"
MISSION_STATE_SLUGS+=("$slug")
repo=$(new_tmp_repo)
if out=$(cd "$repo" && "$MISSION_INIT" "$slug" "goal" "mission" "" "0" 2>&1); then
  pass "mission-init: depth=0 succeeds"
else
  fail "mission-init: depth=0 should succeed, got: $out"
fi

# Test 3: depth=1 -> success (one level of self-nesting allowed)
slug="test-slug-depth1-$SUFFIX"
MISSION_STATE_SLUGS+=("$slug")
repo=$(new_tmp_repo)
if out=$(cd "$repo" && "$MISSION_INIT" "$slug" "goal" "mission" "" "1" 2>&1); then
  pass "mission-init: depth=1 succeeds"
else
  fail "mission-init: depth=1 should succeed, got: $out"
fi

# Test 4: depth=2 -> REFUSE + exit 1 (grandchild nesting forbidden)
slug="test-slug-depth2-$SUFFIX"
MISSION_STATE_SLUGS+=("$slug")
repo=$(new_tmp_repo)
if out=$(cd "$repo" && "$MISSION_INIT" "$slug" "goal" "mission" "" "2" 2>&1); then
  fail "mission-init: depth=2 should REFUSE (exit 1), but succeeded: $out"
else
  if printf '%s' "$out" | grep -qi 'REFUSE'; then
    pass "mission-init: depth=2 refused with REFUSE message"
  else
    fail "mission-init: depth=2 exited nonzero but printed no REFUSE message: $out"
  fi
fi

# Test 5: depth="abc" (non-integer) -> REFUSE + exit 1
slug="test-slug-depthabc-$SUFFIX"
MISSION_STATE_SLUGS+=("$slug")
repo=$(new_tmp_repo)
if out=$(cd "$repo" && "$MISSION_INIT" "$slug" "goal" "mission" "" "abc" 2>&1); then
  fail "mission-init: depth=abc should REFUSE (exit 1), but succeeded: $out"
else
  if printf '%s' "$out" | grep -qi 'REFUSE'; then
    pass "mission-init: depth=abc refused with REFUSE message"
  else
    fail "mission-init: depth=abc exited nonzero but printed no REFUSE message: $out"
  fi
fi

# Test 6: generated @fix_plan.md contains "- depth: " line near "- scale:"
slug="test-slug-depthline-$SUFFIX"
MISSION_STATE_SLUGS+=("$slug")
repo=$(new_tmp_repo)
if (cd "$repo" && "$MISSION_INIT" "$slug" "goal" "mission" "" "1" >/dev/null 2>&1); then
  if grep -q '^- depth: ' "$repo/@fix_plan.md" 2>/dev/null; then
    pass "mission-init: @fix_plan.md contains '- depth: ' frontmatter line"
  else
    fail "mission-init: @fix_plan.md missing '- depth: ' frontmatter line"
  fi
else
  fail "mission-init: setup call for depth-line test failed unexpectedly (should have succeeded at depth=1)"
fi

echo "== Group 2: budget-guard.sh shared mission budget =="

# Test 7: existing call without --mission= must keep working exactly as before (regression)
tid="test-nesting-guard-plain-$SUFFIX"
BUDGET_TASK_IDS+=("$tid")
if out=$("$BUDGET_GUARD" "$tid" 5 2>&1); then
  if printf '%s' "$out" | grep -q 'attempt 1/5'; then
    pass "budget-guard: plain call without --mission= works (regression)"
  else
    fail "budget-guard: plain call output unexpected: $out"
  fi
else
  fail "budget-guard: plain call without --mission= should succeed, got: $out"
fi

# Test 8: --mission= call creates a shared counter file (independent of per-task counter)
mission_slug="test-mission-xyz-$SUFFIX"
MISSION_SLUGS+=("$mission_slug")
tid1="test-nesting-guard-m1-$SUFFIX"
BUDGET_TASK_IDS+=("$tid1")
mission_file="$BUDGET_DIR/_mission-total-${mission_slug}"

"$BUDGET_GUARD" "$tid1" 5 "--mission=$mission_slug" "--mission-max=3" >/dev/null 2>&1 || true
if [ -f "$mission_file" ]; then
  pass "budget-guard: --mission= call creates shared counter file"
else
  fail "budget-guard: --mission= call did not create shared counter file $mission_file"
fi

# Test 9: shared mission budget triggers MISSION_BUDGET_EXCEEDED on the 4th call (max=3),
#         even though each individual task-id is well within its own per-task max.
tid2="test-nesting-guard-m2-$SUFFIX"
tid3="test-nesting-guard-m3-$SUFFIX"
tid4="test-nesting-guard-m4-$SUFFIX"
BUDGET_TASK_IDS+=("$tid2" "$tid3" "$tid4")

ok=true
for tid in "$tid2" "$tid3"; do
  if ! out=$("$BUDGET_GUARD" "$tid" 5 "--mission=$mission_slug" "--mission-max=3" 2>&1); then
    ok=false
    fail "budget-guard: call for $tid (2nd/3rd of shared budget) should succeed, got: $out"
  fi
done
if $ok; then
  pass "budget-guard: 2nd and 3rd shared-budget calls (within mission-max=3) succeeded"
fi

if out=$("$BUDGET_GUARD" "$tid4" 5 "--mission=$mission_slug" "--mission-max=3" 2>&1); then
  fail "budget-guard: 4th call should exceed mission-max=3 and exit 1, but succeeded: $out"
else
  if printf '%s' "$out" | grep -q 'MISSION_BUDGET_EXCEEDED'; then
    pass "budget-guard: 4th call correctly triggers MISSION_BUDGET_EXCEEDED"
  else
    fail "budget-guard: 4th call exited nonzero but printed no MISSION_BUDGET_EXCEEDED message: $out"
  fi
fi

# Test 10: --reset <task-id> --mission=<slug> clears BOTH the per-task and shared counters
reset_tid="test-nesting-guard-reset-$SUFFIX"
reset_mission="test-mission-reset-$SUFFIX"
BUDGET_TASK_IDS+=("$reset_tid")
MISSION_SLUGS+=("$reset_mission")
reset_mission_file="$BUDGET_DIR/_mission-total-${reset_mission}"
reset_task_file="$BUDGET_DIR/${reset_tid//\//_}"

"$BUDGET_GUARD" "$reset_tid" 5 "--mission=$reset_mission" "--mission-max=3" >/dev/null 2>&1 || true
"$BUDGET_GUARD" --reset "$reset_tid" "--mission=$reset_mission" >/dev/null 2>&1 || true

if [ ! -f "$reset_task_file" ] && [ ! -f "$reset_mission_file" ]; then
  pass "budget-guard: --reset clears both per-task and shared mission counters"
else
  fail "budget-guard: --reset left counter file(s) behind (task_exists=$([ -f "$reset_task_file" ] && echo yes || echo no) mission_exists=$([ -f "$reset_mission_file" ] && echo yes || echo no))"
fi

echo "== Group 3: budget-guard.sh concurrent shared-mission-counter race regression =="

# Test 11: N parallel budget-guard.sh calls with unique task-ids but the SAME --mission=<slug>
# must all land on the shared mission counter atomically (no lost updates). Without a lock
# around the shared counter's read-modify-write (cat -> +1 -> printf), concurrent invocations
# race (read-then-clobber) and the final counter value undercounts the true number of calls.
# This test is expected to FAIL against the pre-fix budget-guard.sh (RED) and PASS once the
# shared counter's read-modify-write is serialized with flock (GREEN).
concurrent_mission="test-concurrent-mission-$SUFFIX"
MISSION_SLUGS+=("$concurrent_mission")
N_CONCURRENT=20
concurrent_task_ids=()
for i in $(seq 1 "$N_CONCURRENT"); do
  concurrent_task_ids+=("test-concurrent-task-${i}-$SUFFIX")
done
BUDGET_TASK_IDS+=("${concurrent_task_ids[@]}")

pids=()
for tid in "${concurrent_task_ids[@]}"; do
  "$BUDGET_GUARD" "$tid" 100 "--mission=$concurrent_mission" "--mission-max=1000" >/dev/null 2>&1 &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid" || true
done

concurrent_mission_file="$BUDGET_DIR/_mission-total-${concurrent_mission}"
concurrent_final=$(cat "$concurrent_mission_file" 2>/dev/null || echo 0)
if [ "$concurrent_final" -eq "$N_CONCURRENT" ]; then
  pass "budget-guard: $N_CONCURRENT concurrent --mission= calls yield exact shared counter value (no lost updates)"
else
  fail "budget-guard: $N_CONCURRENT concurrent --mission= calls should yield counter=$N_CONCURRENT but got $concurrent_final (lost update / race condition)"
fi

echo "----"
echo "RESULT: pass=$pass_count fail=$fail_count"
if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
exit 0
