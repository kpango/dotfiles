#!/usr/bin/env bash
# タスク単位の独立 Git Worktree を <repo>/.claude/worktrees/ に割り当てる。
# usage: worktree-alloc.sh <task-slug> [base-ref=HEAD]
# stdout: 割り当てた worktree の絶対パス (これだけを後続処理に使う)
set -euo pipefail

task="${1:?usage: worktree-alloc.sh <task-slug> [base-ref]}"
base="${2:-HEAD}"

root=$(git rev-parse --show-toplevel)
slug=$(printf '%s' "$task" | tr -c 'a-zA-Z0-9._-' '-' | cut -c1-48)
suffix=$(date +%Y%m%d-%H%M%S)
wt="$root/.claude/worktrees/${slug}-${suffix}"
branch="swarm/${slug}-${suffix}"

mkdir -p "$root/.claude/worktrees"
git -C "$root" worktree add -b "$branch" "$wt" "$base" >/dev/null

echo "$wt"
