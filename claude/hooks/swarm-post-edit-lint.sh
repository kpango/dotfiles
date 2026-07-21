#!/usr/bin/env bash
# PostToolUse(Write|Edit) hook: 編集直後の即時 lint によるクローズドループ形成。
# 失敗時は exit 2 で stderr を Claude に差し戻し、修正ループへ引き戻す。
set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null) || exit 0

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
    cfg=()
    # .hadolint.yaml の ignored ルールは意図的なインフラ固有設定 — 必ず尊重する
    [ -f "$root/.hadolint.yaml" ] && cfg=(--config "$root/.hadolint.yaml")
    out=$(timeout 60 hadolint "${cfg[@]}" "$file" 2>&1)
    if [ $? -ne 0 ] && [ -n "$out" ]; then
      {
        echo "[swarm-post-edit-lint] hadolint failed for $file (config: ${cfg[*]:-none}):"
        printf '%s\n' "$out" | head -40
        echo "NOTE: .hadolint.yaml の ignored ルールを修正・削除して解決してはならない。"
      } >&2
      log_evolve_event "post-edit-lint" "hadolint"
      exit 2
    fi
    ;;
  *.go)
    # vald のみ: 編集したパッケージに限定して golangci-lint を即時実行
    case "$root" in
      */vdaas/vald*) ;;
      *) exit 0 ;;
    esac
    command -v golangci-lint >/dev/null 2>&1 || exit 0
    case "$file" in
      *.pb.go | *_vtproto.pb.go) exit 0 ;;
    esac
    rel=$(realpath --relative-to="$root" "$(dirname "$file")" 2>/dev/null) || exit 0
    out=$(cd "$root" && timeout 120 golangci-lint run "./$rel/" 2>&1)
    rc=$?
    # Build-tag-guarded packages (e.g. //go:build e2e) typecheck to
    # "build constraints exclude all Go files" without the tag; retry with
    # the tags extracted from the package's go:build lines before failing.
    if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "build constraints exclude all Go files"; then
      tags=$(grep -rhoP '(?<=^//go:build )[a-zA-Z0-9_]+$' "$(dirname "$file")"/*.go 2>/dev/null | sort -u | paste -sd, -)
      if [ -n "$tags" ]; then
        out=$(cd "$root" && timeout 120 golangci-lint run --build-tags "$tags" "./$rel/" 2>&1)
        rc=$?
      fi
    fi
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
