#!/usr/bin/env bash
# Regression tests for loop-status.sh の Tasks 集計 (TDAD RED — 現行の awk 実装は節スコープを
# 持たず全 "|" 行を集計するため、節スコープ・不整形行ガードを要求するケースは FAIL する)。
# 仕様: impl-loop-spec.md 変更6。節スコープ・不整形行ガードの意味論は
# claude/skills/swarm-graph/scripts/graph-compile.sh の TASKS_HEADING_RE / ANY_HEADING_RE /
# malformed row 判定を移植したもの。
# 様式: claude/skills/swarm-implement/scripts/test-fable-guard.sh 準拠
#   (set -u / mktemp -d 隔離 + trap 削除 / check() ヘルパ / PASS-FAIL 集計)。
# fixture 方針: loop-status.sh は git repo 前提 (root=git rev-parse --show-toplevel) のため、
# fixture は tmp 内に `git init` した実リポジトリを作り、その中に @fix_plan.md を置く。
set -u

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/loop-status.sh"

export HOME="$(mktemp -d)"  # budget/fable-spot-log 等の実データを汚さない隔離 HOME
TMP_REPOS=()
trap 'for r in "${TMP_REPOS[@]:-}"; do [ -n "$r" ] && rm -rf "$r"; done; rm -rf "$HOME"' EXIT

pass=0 fail=0
check() { # check <desc> <expected-exit> <actual-exit> [<must-match-pattern> <output>]
  local desc="$1" want="$2" got="$3" pat="${4:-}" out="${5:-}"
  if [ "$want" != "$got" ]; then
    echo "FAIL: $desc (exit want=$want got=$got)"
    [ -n "$out" ] && echo "  output: $out"
    fail=$((fail + 1))
    return
  fi
  if [ -n "$pat" ] && ! grep -q -- "$pat" <<<"$out"; then
    echo "FAIL: $desc (output missing '$pat'): $out"
    fail=$((fail + 1))
    return
  fi
  echo "ok: $desc"
  pass=$((pass + 1))
}
check_not() { # check_not <desc> <must-NOT-match-pattern> <output>
  local desc="$1" pat="$2" out="$3"
  if grep -q -- "$pat" <<<"$out"; then
    echo "FAIL: $desc (output unexpectedly contains '$pat'): $out"
    fail=$((fail + 1))
    return
  fi
  echo "ok: $desc"
  pass=$((pass + 1))
}

new_tmp_repo() {
  local d
  d=$(mktemp -d)
  git -C "$d" init -q
  TMP_REPOS+=("$d")
  printf '%s' "$d"
}

run_status() { # run_status <repo> -> sets OUT (stdout+stderr combined), RC
  local repo="$1"
  OUT=$(cd "$repo" && bash "$SCRIPT" 2>&1)
  RC=$?
}

run_status_env() { # run_status_env <repo> <ENV=val>... -> sets OUT, RC
  local repo="$1"
  shift
  OUT=$(cd "$repo" && env "$@" bash "$SCRIPT" 2>&1)
  RC=$?
}

new_tmp_dir() { # new_tmp_dir -> git 初期化しない素の tmp dir (non-git 実行のため)
  local d
  d=$(mktemp -d)
  TMP_REPOS+=("$d")
  printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# case1: 単一 Tasks 節の正常集計
repo=$(new_tmp_repo)
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case1-normal

- goal: normal aggregation test
- scale: mission

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| t1 | task one | - | - | done | 1 | impl | - |
| t2 | task two | - | - | in_progress | 1 | impl | - |
| t3 | task three | - | - | blocked(design) | 3 | impl | - |
PLAN
run_status "$repo"
check "case1: exit 0" 0 "$RC" "" "$OUT"
check "case1: TOTAL is 3" 0 "$RC" "TOTAL *3" "$OUT"
check "case1: done counted" 0 "$RC" "done *1" "$OUT"
check "case1: blocked detail present" 0 "$RC" "\[blocked(design)\] t3 — task three" "$OUT"
check "case1: in_progress detail present" 0 "$RC" "\[in_progress\] t2 — task two" "$OUT"
check_not "case1: done task not in blocked/in_progress detail" "\] t1 —" "$OUT"

# ---------------------------------------------------------------------------
# case2: Secretary Report の表が混在しても集計されない (節スコープ)
repo=$(new_tmp_repo)
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case2-secretary

- goal: secretary report must not leak into task aggregation
- scale: mission

## Secretary Report
| priority | note |
|----------|------|
| P0 | secret-row should not be a task node |

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | real task | - | - | pending | 0 | impl | - |
PLAN
run_status "$repo"
check "case2: exit 0" 0 "$RC" "" "$OUT"
check "case2: TOTAL is 1 (secretary row excluded)" 0 "$RC" "TOTAL *1" "$OUT"
check_not "case2: secretary report cell not counted as status" "P0" "$OUT"

# ---------------------------------------------------------------------------
# case3: 複数 `## Tasks` 節では最後の節のみ集計
repo=$(new_tmp_repo)
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case3-multi-tasks

- goal: only the last Tasks section counts
- scale: mission

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| old | stale v1 node | - | - | blocked(design) | 5 | impl | - |

## Tasks (v2)
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| new | current v2 node | - | - | done | 1 | impl | - |
PLAN
run_status "$repo"
check "case3: exit 0" 0 "$RC" "" "$OUT"
check "case3: TOTAL is 1 (only v2 section)" 0 "$RC" "TOTAL *1" "$OUT"
check_not "case3: v1 node (old) not counted in blocked detail" "\] old —" "$OUT"

# ---------------------------------------------------------------------------
# case4: 不整形行 (9セル、summary に生 "|") が除外され warning 表示
repo=$(new_tmp_repo)
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case4-malformed

- goal: malformed row must be excluded with a warning
- scale: mission

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | normal task | - | - | pending | 0 | impl | - |
| b | broken|summary | - | - | pending | 0 | impl | - |
PLAN
run_status "$repo"
check "case4: exit 0" 0 "$RC" "" "$OUT"
check "case4: TOTAL is 1 (malformed row excluded)" 0 "$RC" "TOTAL *1" "$OUT"
check "case4: malformed row warning shown (ncells=9)" 0 "$RC" "warning: malformed row (ncells=9)" "$OUT"

# ---------------------------------------------------------------------------
# case5: Tasks 節なし → 既存挙動 (エラーにしない)
repo=$(new_tmp_repo)
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case5-no-tasks

- goal: no Tasks section yet (Phase 2 PLAN not done)
- scale: mission

## Definition of Done
- N/A (test fixture, no Tasks section present)
PLAN
run_status "$repo"
check "case5: exit 0 (not an error)" 0 "$RC" "" "$OUT"
check "case5: shows not-yet-registered message" 0 "$RC" "タスク未登録" "$OUT"
check "case5: blocked/in_progress detail header still present" 0 "$RC" "== blocked / in_progress detail" "$OUT"

# ---------------------------------------------------------------------------
# case6: git repo でないディレクトリで実行 (root=git rev-parse --show-toplevel の前提が崩れる)
nogit=$(new_tmp_dir)
run_status "$nogit"
check "case6: non-git dir exits with git's fatal exit code" 128 "$RC" "not a git repository" "$OUT"

# ---------------------------------------------------------------------------
# case7: FABLE_BUDGET_CONF が存在しないファイルを指す → 既定値へフォールバックし成功する
repo=$(new_tmp_repo)
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case7-conf-missing

- goal: FABLE_BUDGET_CONF missing must fall back to defaults
- scale: mission

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | task a | - | - | pending | 0 | impl | - |
PLAN
run_status_env "$repo" "FABLE_BUDGET_CONF=$repo/no-such-fable-budget.conf"
check "case7: exit 0 (missing conf falls back to defaults)" 0 "$RC" "" "$OUT"
check "case7: fallback fable task max shown" 0 "$RC" "max 1/task, 2/mission" "$OUT"
check "case7: fallback attempt budget max shown" 0 "$RC" "default max 5/task" "$OUT"

# ---------------------------------------------------------------------------
# case8: FABLE_BUDGET_CONF が構文エラーのファイルを指す → 既知の制約として現状フォールバックせず
# 失敗する (loop-status.sh 側の修正はこのタスクの対象外。将来 loop-status.sh を直す場合の
# 回帰検知用に現状の挙動を固定しておく)
repo=$(new_tmp_repo)
badconf="$repo/bad-fable-budget.conf"
printf 'FABLE_TASK_MAX=1\nif [ 1 -eq 1 ]\n' >"$badconf"
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case8-conf-syntax-error

- goal: FABLE_BUDGET_CONF with a syntax error is a known non-graceful gap
- scale: mission

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | task a | - | - | pending | 0 | impl | - |
PLAN
run_status_env "$repo" "FABLE_BUDGET_CONF=$badconf"
check "case8: syntax-error conf currently fails hard (known gap, not fixed here)" 2 "$RC" "syntax error" "$OUT"

# ---------------------------------------------------------------------------
# case9: Tasks 節あり + budget ディレクトリなし (どのタスクも予算消費していない状態)
repo=$(new_tmp_repo)
cat >"$repo/@fix_plan.md" <<'PLAN'
# @fix_plan.md — mission: case9-no-budget-dir

- goal: Tasks present but budget dir has not been created yet
- scale: mission

## Tasks
| task-id | summary | depends | worktree | status | attempts | domain | note |
|---------|---------|---------|----------|--------|----------|--------|------|
| a | task a | - | - | pending | 0 | impl | - |
| b | task b | - | - | done | 1 | impl | - |
PLAN
run_status "$repo"
check "case9: exit 0" 0 "$RC" "" "$OUT"
check "case9: TOTAL is 2" 0 "$RC" "TOTAL *2" "$OUT"
check "case9: attempt budgets show no consumption" 0 "$RC" "== attempt budgets" "$OUT"
check "case9: fable spots show no consumption" 0 "$RC" "== fable spots" "$OUT"
n_no_consumption=$(grep -c '(消費なし)' <<<"$OUT")
check "case9: both budget sections report (消費なし) (count=$n_no_consumption)" 0 "$([ "$n_no_consumption" -eq 2 ] && echo 0 || echo 1)" "" "$OUT"

echo "----"
echo "pass=$pass fail=$fail"
if [ "$fail" -gt 0 ]; then
  exit 1
fi
exit 0
