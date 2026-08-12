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

lib="$(dirname "${BASH_SOURCE[0]}")/../skills/swarm-implement/scripts/write-scope-lib.sh"
[ -f "$lib" ] || exit 0
# shellcheck disable=SC1090
. "$lib"

real=$(realpath -m "$FILE_PATH" 2>/dev/null || echo "$FILE_PATH")
write_scope_is_protected "$real" || exit 0

# TTLの単一ソース(fable-budget.conf)。swarm-fable-gate.shと同じsourceパターン。
conf="${FABLE_BUDGET_CONF:-$(dirname "${BASH_SOURCE[0]}")/../skills/swarm-implement/scripts/fable-budget.conf}"
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

consumed=""
if [ -d "$grants_dir" ]; then
  for gf in "$grants_dir"/*; do
    [ -f "$gf" ] || continue
    mt=$(stat -c %Y "$gf" 2>/dev/null || echo 0)
    if [ $((now - mt)) -gt "$ttl" ]; then rm -f "$gf"; continue; fi
    gkey="${gf##*/}"; gkey="${gkey#*-}"
    [ "$gkey" = "$key" ] || continue
    tmp="$grants_dir/.consuming.$$"
    if mv "$gf" "$tmp" 2>/dev/null; then
      consumed="$(basename "$gf")"; rm -f "$tmp"; break
    fi
  done
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
