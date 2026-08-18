#!/usr/bin/env bash
# 現在のリポジトリの canonical root path を解決する。worktree 内から呼ばれても main repo root を
# 返す（mission-init.sh 等が使う `git rev-parse --show-toplevel` はworktree内ではworktree自身の
# rootを返してしまうため、swarm-loop/SKILL.md Phase 0 と同じ `git rev-parse --git-common-dir` から
# 算出する — worktree の .git はファイルで、main repo の .git ディレクトリを指す common-dir を持つ）。
#
# 重要（過剰な期待を防ぐ）: ListAgents/SendMessage はモデル専用ツールであり、シェルスクリプトから
# 直接呼び出すことはできない。本スクリプトの役割はそれらの呼び出しの前段として必要となる「自リポジトリの
# canonical repo path 解決」に留まる。到達可能セッションの発見・同一 repo かどうかの突き合わせ自体は
# 呼び出し元（SKILL.md の手順）が ListAgents の結果とこの出力を比較して行う。
# usage: list-siblings.sh
set -euo pipefail

git_common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
root=$(dirname "$git_common_dir")

echo "repo=$root"
