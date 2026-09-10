#!/usr/bin/env bash
# swarm-implement/scripts/budget-guard.sh・swarm-loop/scripts/self-improve-register.sh・
# swarm-meta/scripts/harness-record.sh の全てが source する単一ソース。3箇所に同一の
# flock 存在ガード + メッセージを重複させない(write-scope-lib.sh と同じ「1箇所修正」パターン)。
#
# flock (util-linux) が PATH に無い環境 (例: Homebrew 未導入の macOS) では `flock -x <fd>` が
# exit 127 でクラッシュしうる。書き込み (カウンタ/registry への追記等) の前に fail-closed で
# 検出するために各呼び出し元が require_flock を呼ぶ (flock 存在時の挙動はここでは変更しない)。
#
# Homebrew での修正 (Homebrew の一次ソースで検証済み): util-linux は
# `keg_only :shadowed_by_macos` (Formula/u/util-linux.rb) であり、デフォルト prefix への
# シンボリックリンク配置は Homebrew 側の cmd/link.rb がそもそも拒否する (force指定でも効果なし)。
# 正しい修正は 'brew install flock' (非keg-only の単体formula。同ファイルの
# `conflicts_with "flock"` が示す通り util-linux 自体も flock バイナリを提供するが、使うには
# prefix 経由 PATH が必要) か、util-linux を prefix 経由 PATH で使うこと。
require_flock() { # <context-noun> (例: "budget-counter writes" / "registry writes")
  local noun="$1"
  if ! command -v flock >/dev/null 2>&1; then
    echo "FLOCK_MISSING: 'flock' is required to serialize $noun but was not found on PATH. Install it: on macOS run 'brew install flock' (simplest fix), or install util-linux via 'brew install util-linux' and add \"\$(brew --prefix util-linux)/bin\" to PATH (util-linux is keg-only/shadowed on macOS and does not support Homebrew's default symlink placement), or run this on Linux/NixOS where flock ships by default." >&2
    exit 1
  fi
}
