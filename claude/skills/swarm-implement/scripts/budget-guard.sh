#!/usr/bin/env bash
# Unified Credit Feedback: タスクごとの試行回数を計数し、上限超過で exit 1。
# usage: budget-guard.sh <task-id> [max-attempts=5]
#        budget-guard.sh --reset <task-id>
set -euo pipefail

dir="$HOME/.claude/session-data/swarm/budget"
mkdir -p "$dir"

if [ "${1:-}" = "--reset" ]; then
  task="${2:?task-id required}"
  rm -f "$dir/${task//\//_}"
  echo "reset: $task"
  exit 0
fi

task="${1:?usage: budget-guard.sh <task-id> [max-attempts]}"
max="${2:-5}"
f="$dir/${task//\//_}"

n=$(cat "$f" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s\n' "$n" >"$f"

if [ "$n" -gt "$max" ]; then
  echo "BUDGET_EXCEEDED: task=$task attempts=$n max=$max — 即座に停止し、@fix_plan.md に軌跡を書き出して人間に報告せよ" >&2
  exit 1
fi

echo "attempt $n/$max (task=$task)"
