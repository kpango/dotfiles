#!/usr/bin/env bash
# swarm ミッションのローカルマージ完了後、残存 worktree/branch を機械的に棚卸しし、
# base branch へ完全にマージ済み(=内容が失われない)ものだけを安全に削除する。
# 「マージ済みのものから消していって」という定型依頼を毎回人手で行っていたのを
# 1コマンドへ集約する(swarm-loop SKILL.md Phase 5 の完了処理から呼ばれる想定。
# 単独手動実行も可)。
#
# 安全性の核: 削除は2段とも「本当に merge 済みか」を git 自身に判定させる
# (--is-ancestor / branch -d の自己拒否)。worktree に未コミット差分があれば
# そもそも触らない。base branch 自体・現在チェックアウト中の branch は対象外。
# force 系オプションは一切持たない — 判定を誤っても壊れる側に倒れない設計。
#
# usage: swarm-branch-worktree-audit.sh [--base <branch>] [--dry-run]
set -euo pipefail

DRY_RUN=false
BASE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --base) BASE="${2:?--base requires a branch name}"; shift 2 ;;
    *) echo "usage: swarm-branch-worktree-audit.sh [--base <branch>] [--dry-run]" >&2; exit 1 ;;
  esac
done

# worktree/branch はどこから呼ばれても本体リポジトリ全体を対象にするため、
# ミッションworktree内から呼ばれても canonical root(本体根)へ移動する
# (swarm-common-lib.sh の swarm_canonical_root と同一idiom — worktree-local な
# swarm_repo_root ではなく、worktree を跨いだ操作なのでこちらが正しい)。
common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || { echo "not a git repo" >&2; exit 1; }
root=$(cd "$(dirname "$common_dir")" && pwd -P)
cd "$root"

if [ -z "$BASE" ]; then
  # origin/HEAD があればその指す branch、無ければ main へフォールバック
  # (このリポジトリの既存 swarm スクリプト群と同じ既定値)。
  BASE=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##') || true
  [ -n "$BASE" ] || BASE="main"
fi
git show-ref --verify --quiet "refs/heads/$BASE" || { echo "base branch '$BASE' does not exist locally" >&2; exit 1; }

removed_worktrees=()
skipped_worktrees=()
deleted_branches=()
skipped_branches=()

echo "=== swarm-branch-worktree-audit: base=$BASE dry_run=$DRY_RUN ==="

git worktree prune

# --- worktree 側 ---
while IFS= read -r wt_path; do
  [ -n "$wt_path" ] || continue
  [ "$wt_path" != "$root" ] || continue # 本体自身は対象外

  wt_branch=$(git -C "$wt_path" branch --show-current 2>/dev/null || true)
  if [ -z "$wt_branch" ]; then
    skipped_worktrees+=("$wt_path (detached HEAD, skip)")
    continue
  fi
  if [ "$wt_branch" = "$BASE" ]; then
    skipped_worktrees+=("$wt_path (checked out on base branch, skip)")
    continue
  fi
  if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
    skipped_worktrees+=("$wt_path (uncommitted changes, skip)")
    continue
  fi
  if ! git merge-base --is-ancestor "$wt_branch" "$BASE" 2>/dev/null; then
    skipped_worktrees+=("$wt_path (branch '$wt_branch' not merged into $BASE, skip)")
    continue
  fi

  if $DRY_RUN; then
    removed_worktrees+=("$wt_path (branch '$wt_branch', would remove)")
  else
    git worktree remove "$wt_path"
    removed_worktrees+=("$wt_path (branch '$wt_branch')")
  fi
done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

git worktree prune

# --- branch 側 (worktree 削除で checkout 解除された分も含め、この時点で再列挙) ---
while IFS= read -r br; do
  [ -n "$br" ] || continue
  [ "$br" != "$BASE" ] || continue
  git rev-parse --verify -q "refs/heads/$br" >/dev/null || continue

  # 現在いずれかの worktree でチェックアウト中なら触らない
  # (削除に失敗させて機械的に守らせるより、事前に skip で明示する)。
  if git worktree list --porcelain | grep -qx "branch refs/heads/$br"; then
    skipped_branches+=("$br (still checked out in a worktree, skip)")
    continue
  fi

  if ! git merge-base --is-ancestor "$br" "$BASE" 2>/dev/null; then
    skipped_branches+=("$br (not merged into $BASE, skip)")
    continue
  fi

  if $DRY_RUN; then
    deleted_branches+=("$br (would delete)")
  else
    # -d (force無し): 万一 --is-ancestor の判定と食い違っても git 自身が
    # 二重に拒否する fail-safe。
    git branch -d "$br"
    deleted_branches+=("$br")
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

echo
echo "--- worktrees removed (${#removed_worktrees[@]}) ---"
printf '  %s\n' "${removed_worktrees[@]:-}"
echo "--- worktrees skipped (${#skipped_worktrees[@]}) ---"
printf '  %s\n' "${skipped_worktrees[@]:-}"
echo "--- branches deleted (${#deleted_branches[@]}) ---"
printf '  %s\n' "${deleted_branches[@]:-}"
echo "--- branches skipped (${#skipped_branches[@]}) ---"
printf '  %s\n' "${skipped_branches[@]:-}"
