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
  */Atrae/wevox-common-backends-prototype*)
    # 既存 make 構造を尊重する(vald ケースと同方針)。
    # lint.mk の `ci: fmt/check vet lint proto/lint test` がリポジトリ正準のマージ前検証セット。
    run "make fmt/check"  make fmt/check
    run "make vet"        make vet
    run "make proto/lint" make proto/lint
    run "make test"       make test
    run "make lint"       make lint
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
    done < <(find "$root/zsh" -type f -not -name '*.zwc' 2>/dev/null)
    # *.zwc は zcompile 済みバイトコードで zsh -n では構文解析できない (偽陽性)。
    # ソースの *.zsh は引き続き全件検査対象。
    echo "== zsh syntax: done"

    # swarm スクリプトの回帰テスト (fable budget/gate・nesting guard・graph compile・
    # harness guard・self-improve register、計 251 件規模)。
    # 各テストは HOME/registry/fixture を mktemp へ隔離するため実カウンタ・grant・ログを汚さない。
    for t in \
      "$root/claude/skills/swarm-implement/scripts/test-fable-guard.sh" \
      "$root/claude/skills/swarm-implement/scripts/test-fable-gate.sh" \
      "$root/claude/skills/swarm-loop/scripts/test-nesting-guards.sh" \
      "$root/claude/skills/swarm-loop/scripts/test-loop-status.sh" \
      "$root/claude/skills/swarm-loop/scripts/test-self-improve-register.sh" \
      "$root/claude/skills/swarm-graph/scripts/test-graph-compile.sh" \
      "$root/claude/skills/swarm-meta/scripts/test-harness-guard.sh" \
      "$root/claude/skills/swarm-implement/scripts/test-parallel-gate.sh"; do
      [ -f "$t" ] || continue
      run "swarm tests: $(basename "$t")" bash "$t"
    done
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
