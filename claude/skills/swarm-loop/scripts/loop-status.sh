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

echo "== attempt budgets (max 5/task)"
if [ -d "$budget_dir" ]; then
  found=0
  for f in "$budget_dir"/*; do
    [ -f "$f" ] || continue
    printf '  %-48s %s/5\n' "$(basename "$f")" "$(cat "$f")"
    found=1
  done
  [ "$found" -eq 0 ] && echo "  (消費なし)"
else
  echo "  (消費なし)"
fi

echo "== active worktrees"
git -C "$root" worktree list | grep -F '.claude/worktrees/' || echo "  (なし)"
