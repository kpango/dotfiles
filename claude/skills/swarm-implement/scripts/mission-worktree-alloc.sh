#!/usr/bin/env bash
# ミッション単位(scale=quick|interactive|mission)の独立 Git Worktree を <repo>/.claude/worktrees/ に
# 割り当てる。/swarm-loop・/swarm-graph・/swarm-meta の各エントリポイント Phase 0/G0 が呼ぶ
# (タスク単位の worktree-alloc.sh とは粒度が異なる — 本スクリプトはミッション全体に1つ)。
# usage: mission-worktree-alloc.sh <scale> <slug> [base-ref=HEAD]
# stdout: 割り当てた worktree の絶対パス
# side effect: 起動元ツリーに既存の @fix_plan.md があれば、新worktreeへ
#              @fix_plan.md.inherited としてステージングする
#              (mission-init.sh が Tasks 行を新規骨子へマージしてから消費する。
#              Quick は mission-init.sh を呼ばないため、ステージングされても未使用のまま
#              worktree 破棄時に自然に消える)
set -euo pipefail

scale="${1:?usage: mission-worktree-alloc.sh <quick|interactive|mission> <slug> [base-ref]}"
slug="${2:?usage: mission-worktree-alloc.sh <quick|interactive|mission> <slug> [base-ref]}"
base="${3:-HEAD}"

case "$scale" in quick | interactive | mission) ;; *)
  echo "usage: mission-worktree-alloc.sh <quick|interactive|mission> <slug> [base-ref]" >&2
  exit 1
  ;;
esac

root=$(git rev-parse --show-toplevel)
slug=$(printf '%s' "$slug" | tr -c 'a-zA-Z0-9._-' '-' | cut -c1-48)
suffix=$(date +%Y%m%d-%H%M%S)
wt="$root/.claude/worktrees/${scale}-${slug}-${suffix}"
branch="swarm-${scale}/${slug}-${suffix}"
src_plan="$root/@fix_plan.md"

mkdir -p "$root/.claude/worktrees"
git -C "$root" worktree add -b "$branch" "$wt" "$base" >/dev/null

if [ -f "$src_plan" ]; then
  cp "$src_plan" "$wt/@fix_plan.md.inherited"
fi

echo "$wt"
