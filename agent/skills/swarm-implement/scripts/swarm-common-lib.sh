#!/usr/bin/env bash
# swarm-* skill scripts が共有する root/path 解決の単一ソース。
# これまで各スクリプトへ直書きされていた以下2カテゴリの重複を集約する
# (flock-guard-lib.sh / write-scope-lib.sh と同じ「1箇所修正」パターン)。
#
#  (1) swarm 状態ディレクトリのベースパス
#      ($HOME/.claude/session-data/swarm を 10+ スクリプトが直書きしていた)。
#  (2) git root 解決の2系統。**用途で必ず使い分ける** — 両者を混同すると
#      project_dotfiles_swarm_trajectory_log_worktree_fragmentation のような
#      「軌跡ログがworktreeごとに分裂する」バグや、ミッションworktree内の
#      @fix_plan.md を取り違えるバグを生む:
#        - swarm_repo_root      : `git rev-parse --show-toplevel` 相当。呼び出し
#          位置の worktree 根を返す(worktree-local)。@fix_plan.md 等、ミッション
#          worktree 内にあるローカル成果物を扱うスクリプトはこちらを使う。
#        - swarm_canonical_root : worktree/本体間で共有される --git-common-dir から
#          本体リポジトリ根を逆算する(worktree-safe)。worktree を跨いで共有する
#          状態(軌跡ログ・relay・cross-worktree集計)を扱うスクリプトはこちら
#          (agents-log-lib.sh / list-siblings.sh と同一idiom)。
#
# 本ライブラリは sourced 前提のため `set -e` を張らない(呼び出し元の set -e を
# 尊重する)。関数のみを定義し、直接実行時のみ簡易セルフテストを行う。

# swarm 状態ディレクトリのベース。既定は Claude Code の
# $HOME/.claude/session-data/swarm。テスト等では $HOME を隔離するか、
# SWARM_STATE_DIR で明示上書きする(既存の FABLE_BUDGET_CONF/PASS_REPO_ROOT と
# 同様の上書き規約)。
swarm_state_dir() { # -> swarm 状態ディレクトリのベース絶対パス (末尾スラッシュ無し)
  printf '%s' "${SWARM_STATE_DIR:-$HOME/.claude/session-data/swarm}"
}

swarm_repo_root() { # -> 呼び出し位置の worktree 根 (worktree-local)
  git rev-parse --show-toplevel
}

swarm_canonical_root() { # -> 本体リポジトリ根 (worktree-safe canonical)
  local common_dir
  common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd -P) || return 1
  dirname "$common_dir"
}

# 予算定数の単一ソース fable-budget.conf を source する。値のフォールバック
# 既定値(: "${VAR:=...}")は呼び出し元が必要なサブセットのみ宣言する
# (コンフ側は値の SSoT、フォールバックは欠落時の保険)。この関数内の
# ${BASH_SOURCE[0]} は定義元(swarm-common-lib.sh)を指し、fable-budget.conf と
# 同一ディレクトリにあるため、呼び出し元は脆い ../../ 相対パスを
# 再計算しなくてよい。FABLE_BUDGET_CONF で明示上書き可。
swarm_load_budget_conf() {
  local conf
  conf="${FABLE_BUDGET_CONF:-$(dirname "${BASH_SOURCE[0]}")/fable-budget.conf}"
  # shellcheck disable=SC1090
  [ -f "$conf" ] && . "$conf"
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  printf 'state_dir=%s\n' "$(swarm_state_dir)"
  printf 'repo_root=%s\n' "$(swarm_repo_root 2>/dev/null || echo '(not a git repo)')"
  printf 'canonical_root=%s\n' "$(swarm_canonical_root 2>/dev/null || echo '(not a git repo)')"
fi
