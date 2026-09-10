#!/usr/bin/env bash
# worktree-alloc.sh で割り当てた worktree を回収する。ブランチはデフォルトで保持。
# usage: worktree-release.sh <worktree-path> [--delete-branch]
set -euo pipefail

wt="${1:?usage: worktree-release.sh <worktree-path> [--delete-branch]}"
case "$wt" in
  */.claude/worktrees/*) ;;
  *) echo "refuse: $wt is not under .claude/worktrees/" >&2; exit 1 ;;
esac

branch=$(git -C "$wt" branch --show-current 2>/dev/null || true)
root=$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir | sed 's|/\.git$||')

git -C "$root" worktree remove --force "$wt"

if [ "${2:-}" = "--delete-branch" ] && [ -n "$branch" ]; then
  git -C "$root" branch -D "$branch"
  echo "released: $wt (branch $branch deleted)"
else
  echo "released: $wt (branch $branch kept)"
fi
