#!/usr/bin/env bash
# swarm-parallel-gate.sh (hook) が作るスロットファイルの解放・状態確認用。
# タスクのMaker/Checker/Fixerループが完全に終わった時点(完了処理 or ESCALATE)で
# --release を呼ぶ(worktree-release.sh / mission-cleanup.sh と同じ「オーケストレーターが
# 明示的にライフサイクルを終端する」設計)。呼び忘れてもhook側のTTL(既定1800s)で自動失効する。
# usage: parallel-gate.sh --release <task-id>
#        parallel-gate.sh --status
set -euo pipefail

slots_dir="$HOME/.claude/session-data/swarm/.parallel-slots"

case "${1:-}" in
--release)
  task_id="${2:?usage: parallel-gate.sh --release <task-id>}"
  rm -f "$slots_dir/$task_id"
  echo "released slot for task '$task_id'"
  ;;
--status)
  mkdir -p "$slots_dir"
  count=$(find "$slots_dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "active slots: $count/3"
  find "$slots_dir" -maxdepth 1 -type f -exec basename {} \; 2>/dev/null | sed 's/^/  /'
  ;;
*)
  echo "usage: parallel-gate.sh --release <task-id> | --status" >&2
  exit 1
  ;;
esac
