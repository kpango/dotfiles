#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook: 編集直後の即時 lint によるクローズドループ形成。
# 失敗時は exit 2 で stderr を Claude に差し戻し、修正ループへ引き戻す。
set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0

# hadolint/golangci-lint呼び出しはswarm-lint-lib.shの共有実装を使う(swarm-stop-verify.shと重複
# していたロジックを統合、2026-09-04、claude-hooks-full-agent-consolidationミッション)。欠落時は
# fail-open(既存の「lintツール自体が無ければ何もしない」方針と同じ縮退)。
# 重要: swarm-lint-lib.shの場所は編集対象ファイルの$root(vald等、任意のリポジトリになりうる)
# ではなく、本フック自身の実配置(常にdotfiles配下)から解決する — $rootベースで解決すると
# dotfiles以外のリポジトリを編集した際に常にlib欠落扱いになりバグる(実測で発見)。
# パフォーマンス上の理由(Phase 4.5 Round 3敵対的レビューで実測発見: readlink -f/cd -P×2の
# fork costが+6.6-6.9ms/呼び出しで、Dockerfile/Go以外の全Write/Edit〈本hookはPostToolUseで
# 全編集ごとに同期実行される〉にも無条件に課されていた)により、sourceはcase分岐の中でDockerfile/
# Go分岐に入った時だけ遅延実行する(下記`_source_lint_lib`)。
_source_lint_lib() {
  local here
  here="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
  local lib="$(cd -P "$here/../.." && pwd)/skills/swarm-implement/scripts/swarm-lint-lib.sh"
  # shellcheck disable=SC1090
  [ -f "$lib" ] && . "$lib"
}

# swarm-evolve 用の証拠ログ: rejection の要旨のみ追記 (機密なし・軽量)
log_evolve_event() {
  local hook="$1" category="$2"
  local log="$HOME/.claude/session-data/swarm/evolve-log.jsonl"
  mkdir -p "$(dirname "$log")"
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg repo "$(basename "$root")" \
    --arg hook "$hook" --arg category "$category" \
    '{ts:$ts,repo:$repo,hook:$hook,category:$category}' >>"$log" 2>/dev/null || true
}

case "$file" in
  *.Dockerfile | */Dockerfile)
    command -v hadolint >/dev/null 2>&1 || exit 0
    _source_lint_lib
    # lint_libのsource失敗時(fail-open方針)は関数自体が未定義のため、呼び出し前に必ず
    # command -vで存在確認する(Phase 4.5 Round 2敵対的レビューで発見: 未定義関数呼び出しは
    # exit 127になり、判定ロジックによっては誤って「lint失敗」として扱われるバグになりうる)。
    command -v swarm_lint_dockerfile >/dev/null 2>&1 || exit 0
    # .hadolint.yaml の ignored ルールは意図的なインフラ固有設定 — 必ず尊重する(swarm_lint_dockerfile
    # 内部で$root/.hadolint.yamlの存在を見て自動的に反映する)。
    out=$(swarm_lint_dockerfile "$file" "$root")
    if [ $? -ne 0 ] && [ -n "$out" ]; then
      {
        echo "[swarm-post-edit-lint] hadolint failed for $file:"
        printf '%s\n' "$out" | head -40
        echo "NOTE: .hadolint.yaml の ignored ルールを修正・削除して解決してはならない。"
      } >&2
      log_evolve_event "post-edit-lint" "hadolint"
      exit 2
    fi
    ;;
  *.go)
    # vald のみ: 編集したパッケージに限定して golangci-lint を即時実行(PostToolUse、1ファイル単位で
    # 即block)。swarm-stop-verify.sh(Stop、セッション全体をバッチ収集)とはtimeout値・
    # --new-from-revフラグの有無が意図的に異なる(swarm_lint_go_packageの引数で表現する)。
    _source_lint_lib
    command -v swarm_lint_is_vald_repo >/dev/null 2>&1 || exit 0
    swarm_lint_is_vald_repo "$root" || exit 0
    command -v golangci-lint >/dev/null 2>&1 || exit 0
    command -v swarm_lint_go_package >/dev/null 2>&1 || exit 0
    case "$file" in
      *.pb.go | *_vtproto.pb.go) exit 0 ;;
    esac
    rel=$(realpath --relative-to="$root" "$(dirname "$file")" 2>/dev/null) || exit 0
    out=$(swarm_lint_go_package "$(dirname "$file")" "$root" 120)
    rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
      {
        echo "[swarm-post-edit-lint] golangci-lint failed for ./$rel/ :"
        printf '%s\n' "$out" | head -60
      } >&2
      log_evolve_event "post-edit-lint" "golangci-lint"
      exit 2
    fi
    ;;
  */zsh/* | *.zsh | */zshrc | */zshenv)
    command -v zsh >/dev/null 2>&1 || exit 0
    out=$(zsh -n "$file" 2>&1)
    if [ $? -ne 0 ]; then
      {
        echo "[swarm-post-edit-lint] zsh syntax check failed for $file:"
        printf '%s\n' "$out" | head -20
      } >&2
      log_evolve_event "post-edit-lint" "zsh-syntax"
      exit 2
    fi
    ;;
esac

exit 0
