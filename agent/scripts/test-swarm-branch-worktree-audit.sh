#!/usr/bin/env bash
# Regression tests for swarm-branch-worktree-audit.sh.
# 様式: swarm-loop/scripts/test-self-improve-register.sh 準拠
# (mktemp -d 隔離 / check() / PASS・FAIL 集計 / 失敗1件以上でexit 1)。
# 実リポジトリには一切触れない — 使い捨てのローカル git repo を都度組み立てて検証する。
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SCRIPT="$here/swarm-branch-worktree-audit.sh"

pass=0 fail=0
check() { # check <desc> <cond: 0=pass>
  local desc="$1" cond="$2"
  if [ "$cond" -eq 0 ]; then
    echo "ok: $desc"; pass=$((pass+1))
  else
    echo "FAIL: $desc"; fail=$((fail+1))
  fi
}

# 各テストケースを独立した使い捨てrepoで実行する(状態が前後のケースへ漏れないように)。
setup_repo() {
  local repo
  repo="$(mktemp -d)"
  git -C "$repo" init -q -b main
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  echo init > "$repo/f.txt"
  git -C "$repo" add f.txt
  git -C "$repo" commit -q -m init
  printf '%s' "$repo"
}

# --- ケース1: worktree+branchがmainへ完全マージ済み・作業ツリークリーン -> 両方削除される ---
repo="$(setup_repo)"
git -C "$repo" worktree add -q -b feat-merged "$repo/.wt-merged" >/dev/null
git -C "$repo/.wt-merged" commit -q --allow-empty -m "feat work"
git -C "$repo" merge -q --no-ff feat-merged -m "merge feat-merged"
out="$(cd "$repo" && bash "$REAL_SCRIPT" --base main 2>&1)"
check "case1: merged worktree path reported as removed" $([[ "$out" == *".wt-merged"* && "$out" == *"removed (1)"* ]] && echo 0 || echo 1)
check "case1: merged branch reported as deleted" $([[ "$out" == *"branches deleted (1)"* && "$out" == *"feat-merged"* ]] && echo 0 || echo 1)
check "case1: worktree actually gone from disk" $([ ! -d "$repo/.wt-merged" ] && echo 0 || echo 1)
check "case1: branch actually gone" $(git -C "$repo" show-ref --verify -q refs/heads/feat-merged && echo 1 || echo 0)
rm -rf "$repo"

# --- ケース2: worktree+branchが未マージ -> 両方とも温存される ---
repo="$(setup_repo)"
git -C "$repo" worktree add -q -b feat-unmerged "$repo/.wt-unmerged" >/dev/null
git -C "$repo/.wt-unmerged" commit -q --allow-empty -m "unmerged work"
out="$(cd "$repo" && bash "$REAL_SCRIPT" --base main 2>&1)"
check "case2: unmerged worktree skipped, not removed" $([[ "$out" == *"worktrees removed (0)"* ]] && echo 0 || echo 1)
check "case2: unmerged branch skipped, not deleted" $([[ "$out" == *"branches deleted (0)"* ]] && echo 0 || echo 1)
check "case2: worktree still on disk" $([ -d "$repo/.wt-unmerged" ] && echo 0 || echo 1)
check "case2: branch still exists" $(git -C "$repo" show-ref --verify -q refs/heads/feat-unmerged; echo $?)
rm -rf "$repo"

# --- ケース3: mainへマージ済みだが未コミット差分がある worktree -> 削除しない(データ喪失防止) ---
repo="$(setup_repo)"
git -C "$repo" worktree add -q -b feat-dirty "$repo/.wt-dirty" >/dev/null
git -C "$repo/.wt-dirty" commit -q --allow-empty -m "dirty branch work"
git -C "$repo" merge -q --no-ff feat-dirty -m "merge feat-dirty"
echo "uncommitted" > "$repo/.wt-dirty/scratch.txt"
out="$(cd "$repo" && bash "$REAL_SCRIPT" --base main 2>&1)"
check "case3: dirty worktree skipped despite being merged" $([[ "$out" == *"uncommitted changes"* ]] && echo 0 || echo 1)
check "case3: worktree still on disk" $([ -d "$repo/.wt-dirty" ] && echo 0 || echo 1)
check "case3: branch still checked out, not force-deleted" $(git -C "$repo" show-ref --verify -q refs/heads/feat-dirty; echo $?)
rm -rf "$repo"

# --- ケース4: worktreeを伴わない通常branchのみ、マージ済み -> 削除される ---
repo="$(setup_repo)"
git -C "$repo" branch feat-plain-merged
git -C "$repo" checkout -q feat-plain-merged
git -C "$repo" commit -q --allow-empty -m "plain branch work"
git -C "$repo" checkout -q main
git -C "$repo" merge -q --no-ff feat-plain-merged -m "merge feat-plain-merged"
out="$(cd "$repo" && bash "$REAL_SCRIPT" --base main 2>&1)"
check "case4: plain merged branch (no worktree) deleted" $([[ "$out" == *"feat-plain-merged"* && "$out" == *"branches deleted (1)"* ]] && echo 0 || echo 1)
rm -rf "$repo"

# --- ケース5: --dry-run は何も削除しない ---
repo="$(setup_repo)"
git -C "$repo" worktree add -q -b feat-dryrun "$repo/.wt-dryrun" >/dev/null
git -C "$repo/.wt-dryrun" commit -q --allow-empty -m "dry-run work"
git -C "$repo" merge -q --no-ff feat-dryrun -m "merge feat-dryrun"
out="$(cd "$repo" && bash "$REAL_SCRIPT" --base main --dry-run 2>&1)"
check "case5: dry-run reports would-remove, not removed count" $([[ "$out" == *"would remove"* ]] && echo 0 || echo 1)
check "case5: dry-run leaves worktree on disk" $([ -d "$repo/.wt-dryrun" ] && echo 0 || echo 1)
check "case5: dry-run leaves branch intact" $(git -C "$repo" show-ref --verify -q refs/heads/feat-dryrun; echo $?)
rm -rf "$repo"

# --- ケース6: base branch自体は(理論上マージ済み判定になっても)対象から除外される ---
repo="$(setup_repo)"
out="$(cd "$repo" && bash "$REAL_SCRIPT" --base main 2>&1)"
check "case6: base branch itself untouched" $(git -C "$repo" show-ref --verify -q refs/heads/main; echo $?)
check "case6: no branches deleted when only base exists" $([[ "$out" == *"branches deleted (0)"* ]] && echo 0 || echo 1)
rm -rf "$repo"

echo
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
