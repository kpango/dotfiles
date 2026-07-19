#!/usr/bin/env bash
# リリース前の強制検証。詳細ログはセッションスコープの一時ディレクトリに書き、標準出力には要約のみ返す。
# usage: verify.sh [repo-root]  (省略時はカレントの git root)
set -uo pipefail

root="${1:-$(git rev-parse --show-toplevel)}"
tmpdir="/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm"
mkdir -p "$tmpdir"
log=$(mktemp "$tmpdir/swarm-verify.XXXXXX.log")
fail=0

run() {
  local desc="$1"; shift
  echo "== $desc"
  if (cd "$root" && timeout 1800 "$@") >>"$log" 2>&1; then
    echo "   OK"
  else
    echo "   FAIL: $* (log: $log)"
    echo "---- last 40 lines ----"
    tail -40 "$log"
    fail=1
  fi
}

case "$root" in
  */vdaas/vald*)
    # Makefile 構造は不可侵 — 既存ターゲットのみ使用
    run "make test/pkg"      make test/pkg
    run "make test/internal" make test/internal
    ;;
  */kpango/dotfiles*)
    while IFS= read -r f; do
      python3 -m json.tool "$f" >/dev/null 2>>"$log" || { echo "   FAIL: JSON invalid: $f"; fail=1; }
    done < <(find "$root" -name '*.json' -not -path '*/.git/*' -not -path '*/node_modules/*')
    echo "== JSON validity: done"

    if command -v hadolint >/dev/null 2>&1; then
      cfg=()
      [ -f "$root/.hadolint.yaml" ] && cfg=(--config "$root/.hadolint.yaml")
      while IFS= read -r f; do
        hadolint "${cfg[@]}" "$f" >>"$log" 2>&1 || { echo "   FAIL: hadolint: $f"; tail -20 "$log"; fail=1; }
      done < <(find "$root" \( -name '*.Dockerfile' -o -name 'Dockerfile' \) -not -path '*/.git/*')
      echo "== hadolint (.hadolint.yaml respected): done"
    fi

    for f in "$root/zshrc" "$root/zshenv"; do
      [ -f "$f" ] || continue
      zsh -n "$f" 2>>"$log" || { echo "   FAIL: zsh -n: $f"; fail=1; }
    done
    while IFS= read -r f; do
      zsh -n "$f" 2>>"$log" || { echo "   FAIL: zsh -n: $f"; fail=1; }
    done < <(find "$root/zsh" -type f 2>/dev/null)
    echo "== zsh syntax: done"
    ;;
  *)
    echo "unknown repo: $root — 検証セットが未定義。人間に確認せよ" >&2
    exit 1
    ;;
esac

if [ "$fail" -ne 0 ]; then
  echo "VERIFY FAILED (log: $log)"
  exit 1
fi
echo "ALL CHECKS PASSED (log: $log)"
