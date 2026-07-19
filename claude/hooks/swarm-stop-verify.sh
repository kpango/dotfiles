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
      out=$(python3 -m json.tool "$f" 2>&1 >/dev/null) \
        || append_err "JSON invalid: $f"$'\n'"$(printf '%s' "$out" | head -5)"
      ;;
    *.Dockerfile | */Dockerfile)
      if command -v hadolint >/dev/null 2>&1; then
        cfg=()
        [ -f "$root/.hadolint.yaml" ] && cfg=(--config "$root/.hadolint.yaml")
        out=$(timeout 60 hadolint "${cfg[@]}" "$f" 2>&1) \
          || append_err "hadolint failed: $f"$'\n'"$(printf '%s' "$out" | head -20)"
      fi
      ;;
    */zsh/* | *.zsh | */zshrc | */zshenv)
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

# vald: 編集した Go パッケージに限定した golangci-lint
case "$root" in
  */vdaas/vald*)
    if [ -n "$go_dirs" ] && command -v golangci-lint >/dev/null 2>&1; then
      for d in $go_dirs; do
        rel=$(realpath --relative-to="$root" "$d" 2>/dev/null) || continue
        # --new-from-rev=HEAD scopes issues to lines changed since HEAD, so
        # pre-existing issues in an otherwise-untouched struct (e.g.
        # fieldalignment on a type whose fields were never edited) don't
        # block Stop on every subsequent touch of that package.
        out=$(cd "$root" && timeout 180 golangci-lint run --new-from-rev=HEAD "./$rel/" 2>&1)
        rc=$?
        [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] \
          && append_err "golangci-lint failed: ./$rel/"$'\n'"$(printf '%s' "$out" | head -40)"
      done
    fi
    ;;
esac

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
  printf '{"systemMessage":"[swarm] Stop 検証が %s 回連続で失敗しました。試行予算を超過したためループを停止します。AGENTS.md に失敗の軌跡 (エラー内容・試した対処) を記録し、人間の判断を仰いでください。"}\n' "$max"
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
