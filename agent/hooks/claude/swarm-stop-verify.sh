#!/usr/bin/env bash
# Stop hook: 「完了しました」の自己申告終了を禁止する強制検証ゲート。
# - セッション中に Write/Edit したファイル ∩ git 未コミット変更 のみを検証対象にする
#   (無関係な dirty ファイルで Q&A セッションをブロックしない)
# - 失敗時は exit 2 でエラーログと共に修正ループへ引き戻す
# - SWARM_MAX_STOP_RETRIES (既定 5) 回連続で失敗したら Unified Credit Feedback として
#   停止を許可し、人間へのエスカレーションを指示する
set -uo pipefail

input=$(cat)
session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
[ -z "$cwd" ] && exit 0

root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0

# hadolint/golangci-lint呼び出しはswarm-lint-lib.shの共有実装を使う(swarm-post-edit-lint.shと重複
# していたロジックを統合、2026-09-04、claude-hooks-full-agent-consolidationミッション)。欠落時は
# fail-open(既存の「lintツール自体が無ければ何もしない」方針と同じ縮退)。
# 重要: swarm-lint-lib.shの場所は検証対象の$root(vald等、任意のリポジトリになりうる)ではなく、
# 本フック自身の実配置(常にdotfiles配下)から解決する — $rootベースで解決するとdotfiles以外の
# リポジトリを検証対象にした際に常にlib欠落扱いになりバグる(swarm-post-edit-lint.sh側で実測発見)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
lint_lib="$(cd -P "$HERE/../.." && pwd)/skills/swarm-implement/scripts/swarm-lint-lib.sh"
# shellcheck disable=SC1090
[ -f "$lint_lib" ] && . "$lint_lib"

state_dir="$HOME/.claude/session-data/swarm"
mkdir -p "$state_dir"
counter_file="$state_dir/stop-retries-${session}-$(basename "$root")"
max=${SWARM_MAX_STOP_RETRIES:-5}

# swarm-evolve 用の証拠ログ: rejection のカテゴリのみ追記 (機密なし・軽量)
log_evolve_event() {
  local category="$1"
  local log="$state_dir/evolve-log.jsonl"
  jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg repo "$(basename "$root")" \
    --arg hook "stop-verify" --arg category "$category" \
    '{ts:$ts,repo:$repo,hook:$hook,category:$category}' >>"$log" 2>/dev/null || true
}

# --- セッション中に編集されたファイルを transcript から抽出 ---
edited=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  edited=$(jq -r '
    .message.content[]?
    | select(.type == "tool_use")
    | select(.name == "Write" or .name == "Edit" or .name == "MultiEdit" or .name == "NotebookEdit")
    | .input.file_path // empty
  ' "$transcript" 2>/dev/null | sort -u)
fi
[ -z "$edited" ] && { rm -f "$counter_file"; exit 0; }

# --- git 未コミット変更との積集合 ---
changed=$(git -C "$root" status --porcelain --untracked-files=all 2>/dev/null \
  | sed 's/^...//' | sed "s|^|$root/|")
targets=$(comm -12 <(printf '%s\n' "$edited" | sort -u) <(printf '%s\n' "$changed" | sort -u))
[ -z "$targets" ] && { rm -f "$counter_file"; exit 0; }

errors=""
append_err() { errors="${errors}${errors:+$'\n'}$1"; }

# --- リポジトリ別の検証 ---
go_dirs=""
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$f" in
    *.json)
      # python3欠如時のfail-open(Phase 4.5 Round 3敵対的レビューで発見: このガードは本ミッションの
      # 対象外だが同ファイル内のswarm_lint_*呼び出しと同じ失敗モード〈`||`は未発見コマンドのexit 127も
      # 拾い誤検出する〉のため、一貫性のため合わせて修正した。本ガード自体は2026-09-03以前から存在した
      # 既存の穴)。
      command -v python3 >/dev/null 2>&1 || continue
      out=$(python3 -m json.tool "$f" 2>&1 >/dev/null) \
        || append_err "JSON invalid: $f"$'\n'"$(printf '%s' "$out" | head -5)"
      ;;
    *.Dockerfile | */Dockerfile)
      # lint_libのsource失敗時(fail-open方針)は関数自体が未定義のため、呼び出し前に必ず
      # command -vで存在確認する(Phase 4.5 Round 2敵対的レビューで発見: `||`は関数未定義時の
      # exit 127も真として拾ってしまい、$outが空でも無条件に「hadolint failed」を誤報告する
      # バグだった)。
      if command -v hadolint >/dev/null 2>&1 && command -v swarm_lint_dockerfile >/dev/null 2>&1; then
        out=$(swarm_lint_dockerfile "$f" "$root") \
          || append_err "hadolint failed: $f"$'\n'"$(printf '%s' "$out" | head -20)"
      fi
      ;;
    */zsh/* | *.zsh | */zshrc | */zshenv)
      # zsh欠如時のfail-open(直上のjsonブランチと同じ理由・同じタイミングで発見・修正)。
      command -v zsh >/dev/null 2>&1 || continue
      out=$(zsh -n "$f" 2>&1) \
        || append_err "zsh syntax error: $f"$'\n'"$(printf '%s' "$out" | head -10)"
      ;;
    *.go)
      case "$f" in *.pb.go | *_vtproto.pb.go) continue ;; esac
      fmt=$(gofmt -l "$f" 2>/dev/null)
      [ -n "$fmt" ] && append_err "gofmt required: $f"
      d=$(dirname "$f")
      case "$go_dirs" in *"$d"*) ;; *) go_dirs="${go_dirs}${go_dirs:+ }$d" ;; esac
      ;;
    *.sh)
      out=$(bash -n "$f" 2>&1) \
        || append_err "bash syntax error: $f"$'\n'"$(printf '%s' "$out" | head -10)"
      ;;
  esac
done <<<"$targets"

# vald: 編集した Go パッケージに限定した golangci-lint(Stop、セッション全体をバッチ収集して報告)。
# swarm-post-edit-lint.sh(PostToolUse、1ファイル単位で即block)とはtimeout値・--new-from-rev
# フラグの有無が意図的に異なる(swarm_lint_go_packageの引数で表現する)。
# --new-from-rev=HEAD scopes issues to lines changed since HEAD, so pre-existing issues in an
# otherwise-untouched struct (e.g. fieldalignment on a type whose fields were never edited)
# don't block Stop on every subsequent touch of that package.
if command -v swarm_lint_is_vald_repo >/dev/null 2>&1 && swarm_lint_is_vald_repo "$root"; then
  if [ -n "$go_dirs" ] && command -v golangci-lint >/dev/null 2>&1 && command -v swarm_lint_go_package >/dev/null 2>&1; then
    for d in $go_dirs; do
      rel=$(realpath --relative-to="$root" "$d" 2>/dev/null) || continue
      out=$(swarm_lint_go_package "$d" "$root" 180 --new-from-rev=HEAD)
      rc=$?
      [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] \
        && append_err "golangci-lint failed: ./$rel/"$'\n'"$(printf '%s' "$out" | head -40)"
    done
  fi
fi

# 任意の追加検証 (make test/pkg 等) — リポジトリごとにオプトイン
conf="$root/.claude/swarm-stop-check.conf"
if [ -f "$conf" ]; then
  while IFS= read -r cmd; do
    case "$cmd" in ''|'#'*) continue ;; esac
    out=$(cd "$root" && timeout 600 bash -c "$cmd" 2>&1)
    [ $? -ne 0 ] && append_err "stop-check command failed: $cmd"$'\n'"$(printf '%s' "$out" | tail -40)"
  done <"$conf"
fi

# --- 判定 ---
if [ -z "$errors" ]; then
  rm -f "$counter_file"
  exit 0
fi

n=$(cat "$counter_file" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s\n' "$n" >"$counter_file"

if [ "$n" -ge "$max" ]; then
  # Unified Credit Feedback: 予算超過 — 停止を許可し人間へエスカレーション
  rm -f "$counter_file"
  printf '{"systemMessage":"[swarm] Stop 検証が %s 回連続で失敗しました。試行予算を超過したためループを停止します。軌跡ログに失敗の軌跡 (エラー内容・試した対処) を記録し、人間の判断を仰いでください。"}\n' "$max"
  exit 0
fi

for cat in "JSON invalid" "hadolint failed" "golangci-lint failed" "gofmt required" \
           "zsh syntax error" "bash syntax error" "stop-check command failed"; do
  case "$errors" in *"$cat"*) log_evolve_event "$cat" ;; esac
done

{
  echo "[swarm-stop-verify] 検証失敗 (試行 $n/$max)。完了申告は許可されない。以下を修正してから終了すること:"
  printf '%s\n' "$errors"
} >&2
exit 2
