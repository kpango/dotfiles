#!/usr/bin/env bash
# PreToolUse:Write|Edit|MultiEdit|NotebookEdit — Tier B ガバナンスファイルへの直接書き込みを
# ブロックする。swarm-evolve Step5(人間承認後)が発行する budget-guard.sh --write-scope-grant の
# 単発grantが無い限り拒否する(SWARM.md §2 既知の未機械化ギャップへの対応)。
#
# 既知の限界(overclaim防止のため明記): grant発行自体(budget-guard.sh --write-scope-grant)は
# エージェントがBashで直接呼び出せるため、本機構は「人間承認そのものを暗号学的に証明する」もの
# ではない。達成しているのは (a)偶発的・カジュアルな直接編集の防止 (b)明示的な1アクションを
# 要求することでswarm-evolve Step4の人間提示を経由する運用上のインターロック
# (c)write-scope-log.jsonlによる監査証跡、の3点のみ。swarm-fable-gate.shのgrant機構と同じ
# 限界を共有する。
set -euo pipefail

INPUT=$(cat || true)
command -v jq &>/dev/null || exit 0

# tool_name と file_path(NotebookEdit の実スキーマは notebook_path。file_path ではない)を
# jq 1 回で取り出す(旧: 2 回起動)。旧実装と挙動を一致させるための要点:
#  - 旧は式ごとの `jq -r '<式>'` で、jq は実行時エラー(非オブジェクト値等)の入力だけを読み飛ばして
#    次の入力へ進み、パースエラーでのみ打ち切られる。per-doc の try/catch empty が同じ挙動になる。
#  - 値は NUL 区切りのレコード(タグ NUL 値 "\n" NUL)で受け取る。@tsv と違い値中のタブ・改行・
#    バックスラッシュをエスケープしないため、復元が不要。非文字列値は旧 `-r` と同じ pretty 出力。
#  - 値中の U+0000 は旧実装では $() が捨てていたため jq 側で除去する(区切りとの衝突回避)。
#  - jq への入力・出力は `printf | jq | { read … }` のパイプだけで受け渡す(一時ファイルも /dev/fd も
#    使わない)。here-string/here-doc は bash が約 64KB 超で一時ファイルを使い、process substitution は
#    /dev/fd(procfs)に依存する。いずれも使えない環境ではリダイレクト失敗で jq の出力が空になり、
#    空のまま `exit 0`(fail-open)に落ちる(旧 `echo | jq` はパイプのみで deny した)。read グループは
#    `shopt -s lastpipe` でパイプ最後の要素として現在のシェルで走り、変数が残る(非対話シェルなので有効)。
#  - 送信側は `{ … } 2>/dev/null` で包む。lastpipe だとシェル自身が「強制終了」「Broken pipe」等のジョブ状態を
#    stderr に出すため(jq 異常終了時や jq が入力を読み切らず終わるとき)、旧と同じ静かな stderr に保つ。
#  - U+0000 は jq 側で `split("\u0000")[]` により、結合せずに出力ストリームへ順に流して除去する(線形)。
#    gsub と split|join は NUL が多いと二次式で遅く hook timeout(fail-open)に達した。
#  - 末尾改行の除去は `$(printf '%s' "$x")`(旧 $() と同じ線形の意味)。`${x%"${x##*[!$'\n']}"}` 形は
#    末尾の改行数に対して二次式で、3 万個で hook timeout に達した。
#  - lastpipe はジョブ制御が有効だと効かない(SHELLOPTS=monitor 等で read ループが subshell になり、値が
#    空のまま `exit 0`=fail-open になる)。`set +m` で無効化し、それでも効かない場合は自己検査
#    (`: | _lp=1`)で検出して、旧実装と同一の 2 回 jq 方式へフォールバックする(base と同じ判定になる側)。
#  - 制約(既知): `read -d ''` は 1 バイトずつ読むため、16MB 級の値では hook timeout(5 秒)を超えうる。
#  - jq 自体の失敗は旧と同じく空文字(=許可側)扱い。
set +m
shopt -s lastpipe
_lp=0
: | _lp=1
tool="" FILE_PATH=""
if [ "$_lp" = 1 ]; then
{ printf '%s\n' "$INPUT" | jq -j '
  def c: if type == "string" then split("\u0000")[] else . end;
  ((try (.tool_name // empty) catch empty) | ("t\u0000", c, "\n\u0000")),
  ((try (.tool_input.file_path // .tool_input.notebook_path // empty) catch empty) | ("f\u0000", c, "\n\u0000"))
' 2>/dev/null; } 2>/dev/null | {
  while IFS= read -r -d '' _tag && IFS= read -r -d '' _val; do
    case "$_tag" in t) tool+="$_val" ;; f) FILE_PATH+="$_val" ;; esac
  done
} || true
  tool=$(printf '%s' "$tool")
  FILE_PATH=$(printf '%s' "$FILE_PATH")
else
  # lastpipe 無効: 旧実装と同一の抽出(2 回 jq)
  tool=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
fi
case "$tool" in Write | Edit | MultiEdit | NotebookEdit) ;; *) exit 0 ;; esac
[ -z "$FILE_PATH" ] && exit 0
FILE_PATH="${FILE_PATH/#\~/$HOME}"

# ROOT解決(readlink -fでファイル自身のsymlinkを先に解決してからdirnameする)の理由:
# merged directory化(ディレクトリ全体symlink→per-file symlink)後は`dirname`がファイル名を落として
# から評価されるため、`cd -P dirname($BASH_SOURCE)`だけではファイル自身のsymlinkが未解決のまま
# (実測で確認済み)。
# 本ファイル固有の重大な経緯(2026-09-03発見・修正): 上記とは別種の旧バグ
# (`$(dirname "${BASH_SOURCE[0]}")/../skills/...` という素朴な文字列連結)により、本hookは
# 新設から一度もTier Bガバナンスファイル保護が機能していなかった(常に`[ -f "$lib" ] || exit 0`の
# フォールバックを取っていた)。既知の限界として明記されている「暗号学的な証明ではない」を超えて、
# 実質的に一度も機能していなかったというより深刻な既存バグだった。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
lib="$ROOT/agent/skills/swarm-implement/scripts/write-scope-lib.sh"
[ -f "$lib" ] || exit 0
# shellcheck disable=SC1090
. "$lib"

real=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
write_scope_is_protected "$real" || exit 0

# TTLの単一ソース(fable-budget.conf)。swarm-fable-gate.shと同じsourceパターン。
conf="${FABLE_BUDGET_CONF:-$ROOT/agent/skills/swarm-implement/scripts/fable-budget.conf}"
[ -f "$conf" ] && . "$conf"
: "${WRITE_SCOPE_GRANT_TTL_SECONDS:=300}"
ttl=$WRITE_SCOPE_GRANT_TTL_SECONDS

key=$(write_scope_key "$real")
grants_dir="$HOME/.claude/session-data/swarm/budget/.write-scope-grants"
audit_log="$HOME/.claude/session-data/swarm/write-scope-log.jsonl"
now=$(date +%s)

log_audit() { # <decision: consumed|denied>
  mkdir -p "$(dirname "$audit_log")" 2>/dev/null || true
  jq -nc --arg ts "$(date -Is)" --arg path "$real" --arg decision "$1" \
    '{ts:$ts,path:$path,decision:$decision}' >>"$audit_log" 2>/dev/null || true
}

# grant消費ループ(TTL失効チェック+mvによる原子的消費)はswarm-fable-gate.shと一字一句同一
# だったため agent/skills/swarm-implement/scripts/swarm-lint-lib.sh の grant_consume() へ
# 統合済み(2026-09-03)。set -e下のため `|| true` を必ず付ける(grant_consumeが1を返す=
# 未消費のケースでset -eによる意図しない即時終了を防ぐ、post-write.shで実際に踏んだ罠と同種)。
lint_lib="$ROOT/agent/skills/swarm-implement/scripts/swarm-lint-lib.sh"
# shellcheck disable=SC1090
[ -f "$lint_lib" ] && . "$lint_lib"
consumed=""
if command -v grant_consume >/dev/null 2>&1; then
  consumed=$(grant_consume "$grants_dir" "$ttl" "$key") || consumed=""
fi

if [ -n "$consumed" ]; then
  log_audit consumed
  exit 0
fi

log_audit denied
# exit 2 時、Claude Codeはstdoutを無視しstderrのみ読む。swarm-post-edit-lint.shと同じ規約
# (平文+stderr)に揃える。
{
  echo "[swarm-write-scope-gate] Tier B governance file write blocked: $real"
  echo "requires human-approved diff via /swarm-evolve (Step4 approval, then Step5"
  echo "budget-guard.sh --write-scope-grant before Edit)."
} >&2
exit 2
