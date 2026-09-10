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

tool=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$tool" in Write | Edit | MultiEdit | NotebookEdit) ;; *) exit 0 ;; esac

# NotebookEdit の実スキーマは notebook_path (file_path ではない)。
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0
FILE_PATH="${FILE_PATH/#\~/$HOME}"

# ROOT解決(readlink -fでファイル自身のsymlinkを先に解決してからdirnameする)の経緯・理由は
# agent/README.md「既知の限界（fail-open）」節(2026-09-03 CRITICAL回帰の記録)を参照。要点のみ:
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
