#!/usr/bin/env bash
# Session stop-verify dispatcher (advisory): lint a set of target files by type,
# reusing swarm-lint-lib.sh (swarm_lint_dockerfile=hadolint / swarm_lint_go_package=
# golangci-lint / swarm_lint_is_vald_repo). json=python3 -m json.tool、zsh=zsh -n、
# .sh=bash -n、.go=gofmt -l(+vald限定 golangci-lint)。各ツール欠落時は当該チェックを
# skip(fail-open)。
#
# 種別別 dispatch は claude の agent/hooks/claude/swarm-stop-verify.sh と**一致**させてある
# (Phase 4.5 で pi 版の非等価—.sh/.go/gofmt 欠落・関数存在チェック欠落・vald限定ゲート
# 欠落・Dockerfile glob 緩和—が指摘され修正)。golangci-lint は swarm_lint_is_vald_repo ゲート下で
# timeout 180 + --new-from-rev=HEAD。ブロッキングの有無は呼び出し側の違い(claude=Stop hook
# exit 2 強制 / pi=session_shutdown の助言通知)であり、lint ロジック自体は同一。
#
# usage: stop-verify-lint.sh <root> <file>...
# stdout: 診断メッセージ(空 = クリーン)。exit 0=完了、2=usage、3=swarm-lint-lib.sh 欠落(infra)。
set -uo pipefail

HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
lint_lib="$HERE/swarm-lint-lib.sh"
if [ ! -f "$lint_lib" ]; then
  echo "__INFRA__: swarm-lint-lib.sh not found next to stop-verify-lint.sh" >&2
  exit 3
fi
# shellcheck disable=SC1090
. "$lint_lib"

root="${1:-}"
if [ -z "$root" ]; then
  echo "usage: stop-verify-lint.sh <root> <file>..." >&2
  exit 2
fi
shift

# 以下の種別別 dispatch は claude の swarm-stop-verify.sh と**一致**させる（docs-comment/
# shell-config の Phase 4.5 指摘で、以前の簡易版は (a) *.sh の bash -n ・.go の gofmt 欠落
# (b) swarm_lint_dockerfile/swarm_lint_go_package の関数存在チェック欠落（`||` が関数未定義時の
# exit 127 を拾い誤報告する既知バグの再導入）(c) vald 限定ゲート欠落（非valdで誤検出）
# (d) `*Dockerfile` の境界なし glob など claude 版と非等価だったため。
errors=""
go_dirs=""
append_err() { errors="${errors}${errors:+$'\n'}$1"; }

for f in "$@"; do
  [ -f "$f" ] || continue
  case "$f" in
  *.json)
    command -v python3 >/dev/null 2>&1 || continue
    out=$(python3 -m json.tool "$f" 2>&1 >/dev/null) || append_err "JSON invalid: $f"$'\n'"$(printf '%s' "$out" | head -5)"
    ;;
  *.Dockerfile | */Dockerfile)
    # 関数未定義時(lint_lib source 失敗)に `||` が exit 127 を拾って誤報告するのを防ぐため
    # hadolint と swarm_lint_dockerfile の両方を command -v で確認する（claude 版と同一）。
    if command -v hadolint >/dev/null 2>&1 && command -v swarm_lint_dockerfile >/dev/null 2>&1; then
      out=$(swarm_lint_dockerfile "$f" "$root") || append_err "hadolint failed: $f"$'\n'"$(printf '%s' "$out" | head -20)"
    fi
    ;;
  */zsh/* | *.zsh | */zshrc | */zshenv)
    command -v zsh >/dev/null 2>&1 || continue
    out=$(zsh -n "$f" 2>&1) || append_err "zsh syntax error: $f"$'\n'"$(printf '%s' "$out" | head -10)"
    ;;
  *.go)
    case "$f" in *.pb.go | *_vtproto.pb.go) continue ;; esac
    if command -v gofmt >/dev/null 2>&1; then
      fmt=$(gofmt -l "$f" 2>/dev/null)
      [ -n "$fmt" ] && append_err "gofmt required: $f"
    fi
    d=$(dirname "$f")
    case "$go_dirs" in *"$d"*) ;; *) go_dirs="${go_dirs}${go_dirs:+ }$d" ;; esac
    ;;
  *.sh)
    out=$(bash -n "$f" 2>&1) || append_err "bash syntax error: $f"$'\n'"$(printf '%s' "$out" | head -10)"
    ;;
  esac
done

# vald: 編集した Go パッケージに限定した golangci-lint。swarm_lint_is_vald_repo ゲートで
# 非vald リポジトリでは呼ばない（claude 版と同一。非vald の Go で誤検出しない）。
# timeout 180 + --new-from-rev=HEAD も claude 版に合わせる（既存 issue での誤 block を避ける）。
if command -v swarm_lint_is_vald_repo >/dev/null 2>&1 && swarm_lint_is_vald_repo "$root"; then
  if [ -n "$go_dirs" ] && command -v golangci-lint >/dev/null 2>&1 && command -v swarm_lint_go_package >/dev/null 2>&1; then
    for d in $go_dirs; do
      rel=$(realpath --relative-to="$root" "$d" 2>/dev/null) || continue
      out=$(swarm_lint_go_package "$d" "$root" 180 --new-from-rev=HEAD)
      rc=$?
      [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && append_err "golangci-lint failed: ./$rel/"$'\n'"$(printf '%s' "$out" | head -40)"
    done
  fi
fi

printf '%s' "$errors"
exit 0
