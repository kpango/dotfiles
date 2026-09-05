#!/usr/bin/env bash
# ミッション軌跡ログ(旧: プロジェクトルート AGENTS.md)の書き込み先を返す単一ソース。
# 背景: 一部のコーディングエージェントは "AGENTS.md" をプロジェクトルートで自動検出し
# CLAUDE.md と同格の指示ファイルとして読み込む。プロジェクトルートの AGENTS.md を巨大な
# 追記専用ログに転用すると、そうしたツールに壊れた/無関係な指示として渡ってしまうため、
# 軌跡ログはリポジトリ外の kpango/pass リポジトリへ退避する(個人環境固有の前提。他環境では
# 下記 PASS_REPO_ROOT を上書きすること)。
set -euo pipefail

: "${PASS_REPO_ROOT:=$HOME/go/src/github.com/kpango/pass}"

agents_log_path() { # -> 現在のリポジトリ用ミッション軌跡ログの絶対パス
  local root slug dir
  # `git rev-parse --show-toplevel` はミッションworktree内ではworktree自身の絶対パスを返し、
  # 本体リポジトリと異なるslugになって軌跡ログが分裂する(2026-08-26 agent-skill-evolution-research・
  # 2026-08-27 swarm-workflow-optimization で2回独立に観測、swarm-evolve提案2026-09-03採択)。
  # worktree/本体リポジトリ間で共有される --git-common-dir(常にmain repoの.gitディレクトリを指す)
  # から本体rootを逆算し、常に本体リポジトリの絶対パスへ正規化する
  # (swarm-relay/scripts/list-siblings.sh と同一idiom)。
  local common_dir
  common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd -P) || return 1
  root=$(dirname "$common_dir")
  slug="${root//\//-}"   # Claude Code の claude/projects/<slug> 命名規則に揃える
  slug="${slug//./-}"    # (例: github.com -> github-com)
  dir="$PASS_REPO_ROOT/claude/swarm-history"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s/%s.md\n' "$dir" "$slug"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  agents_log_path
fi
