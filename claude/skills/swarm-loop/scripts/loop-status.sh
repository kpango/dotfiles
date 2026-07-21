#!/usr/bin/env bash
# 進行中ミッションの状態要約: @fix_plan.md のタスク集計 + 試行予算の消費状況。
# usage: loop-status.sh [mission-slug]   (省略時は @fix_plan.md から自動検出)
set -euo pipefail

root=$(git rev-parse --show-toplevel)
plan="$root/@fix_plan.md"

if [ ! -f "$plan" ]; then
  echo "NO_MISSION: $plan がない — mission-init.sh で新規ミッションを開始せよ"
  exit 0
fi

slug="${1:-$(sed -n 's/^# @fix_plan.md — mission: //p' "$plan" | head -1)}"
budget_dir="$HOME/.claude/session-data/swarm/budget"

# 上限表示の単一ソース (fable-budget.conf)。欠落時はフォールバック既定値。
# shellcheck disable=SC1090
conf="${FABLE_BUDGET_CONF:-$(dirname "${BASH_SOURCE[0]}")/../../swarm-implement/scripts/fable-budget.conf}"
[ -f "$conf" ] && . "$conf"
: "${FABLE_TASK_MAX:=1}" "${FABLE_MISSION_MAX:=2}" "${BUDGET_TASK_MAX_DEFAULT:=5}" "${BUDGET_MISSION_MAX_DEFAULT:=20}"

echo "== mission: ${slug:-unknown}"
sed -n 's/^- goal: /goal: /p; s/^- scale: /scale: /p; s/^- started: /started: /p' "$plan"

echo "== tasks"
# Tasks テーブルの status 列 (5列目) を集計
awk -F'|' '
  /^\|/ && $2 !~ /task-id|---/ {
    gsub(/^[ \t]+|[ \t]+$/, "", $6)
    if ($6 != "") count[$6]++
    total++
  }
  END {
    if (total == 0) { print "  (タスク未登録 — Phase 2 PLAN 未完)"; exit }
    for (s in count) printf "  %-16s %d\n", s, count[s]
    printf "  %-16s %d\n", "TOTAL", total
  }' "$plan"

echo "== blocked / in_progress detail"
awk -F'|' '
  /^\|/ && $2 !~ /task-id|---/ {
    gsub(/^[ \t]+|[ \t]+$/, "", $6)
    if ($6 ~ /blocked|in_progress/) {
      gsub(/^[ \t]+|[ \t]+$/, "", $2); gsub(/^[ \t]+|[ \t]+$/, "", $3)
      printf "  [%s] %s — %s\n", $6, $2, $3
    }
  }' "$plan"

echo "== attempt budgets (default max ${BUDGET_TASK_MAX_DEFAULT}/task)"
if [ -d "$budget_dir" ]; then
  found=0
  for f in "$budget_dir"/*; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      _fable-*) continue ;;  # fable カウンタは下の専用節へ
      _mission-total-*) printf '  %-48s %s/%s (mission, default max)\n' "$(basename "$f")" "$(cat "$f")" "$BUDGET_MISSION_MAX_DEFAULT" ;;
      *) printf '  %-48s %s/%s\n' "$(basename "$f")" "$(cat "$f")" "$BUDGET_TASK_MAX_DEFAULT" ;;
    esac
    found=1
  done
  [ "$found" -eq 0 ] && echo "  (消費なし)"
else
  echo "  (消費なし)"
fi

echo "== fable spots (SWARM.md §1 スポット判断層: max ${FABLE_TASK_MAX}/task, ${FABLE_MISSION_MAX}/mission)"
fable_found=0
for f in "$budget_dir"/_fable-*; do
  [ -f "$f" ] || continue
  b=$(basename "$f")
  case "$b" in
    _fable-mission-total-*) printf '  %-48s %s/%s\n' "$b" "$(cat "$f")" "$FABLE_MISSION_MAX" ;;
    *) printf '  %-48s %s/%s\n' "$b" "$(cat "$f")" "$FABLE_TASK_MAX" ;;
  esac
  fable_found=1
done
[ "$fable_found" -eq 0 ] && echo "  (消費なし)"
spot_log="$HOME/.claude/session-data/swarm/fable-spot-log.jsonl"
if [ -f "$spot_log" ]; then
  echo "== fable spot log (last 3)"
  tail -3 "$spot_log" | sed 's/^/  /'
fi

echo "== active worktrees"
git -C "$root" worktree list | grep -F '.claude/worktrees/' || echo "  (なし)"
