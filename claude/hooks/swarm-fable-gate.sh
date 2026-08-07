#!/usr/bin/env bash
# PreToolUse:Task|Agent hook — SWARM.md §1 スポット判断層の機械的ゲート。
# Agent/Task ツールで model:'fable' を指定した起動は、budget-guard.sh --fable が発行した
# 未消費 grant トークン (.fable-grants/) を 1 つ消費して初めて許可される (1 grant = 1 スポーン)。
# grant なし・期限切れ (TTL 600s) はブロック。これにより「発動 4 条件 + 1 タスク 1 回・
# 1 ミッション 2 回」の prose 規範が hook レベルで閉じる (dmi:false 化の非 hook 強制点を解消)。
# subagent_type=debugger を model 未指定で起動する試みには警告のみ (非ブロッキング —
# 「Fixer は model: sonnet を明示」の注意喚起。fork や inherit 全般は判定不能のため対象外)。
# fail-open 方針: jq 欠如・入力パース不能時は exit 0 (security-gate.sh と同じ縮退。
# 本 hook は予算ゲートであり安全ゲートではない)。
set -uo pipefail # -e は意図的に不使用: fail-open 方針 (途中コマンドの失敗でブロックに倒さない)

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

tool=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
case "$tool" in Task | Agent) ;; *) exit 0 ;; esac

model=$(echo "$INPUT" | jq -r '.tool_input.model // empty' 2>/dev/null || true)
subagent=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)

# 非ブロッキングな情報提示は graphify-hint.sh と同じ additionalContext 慣行に従う
info() {
    jq -nc --arg ctx "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $ctx}}' 2>/dev/null || true
}

if [ "$model" != "fable" ]; then
    if [ "$subagent" = "debugger" ] && [ -z "$model" ]; then
        info "swarm-fable-gate: debugger を model 未指定で起動しようとしている — debugger の frontmatter は model: inherit のため Fable セッションでは暗黙に Fable を消費する。swarm の Fixer は model: \"sonnet\" を明示すること (SWARM.md §1)"
    fi
    exit 0
fi

grants_dir="$HOME/.claude/session-data/swarm/budget/.fable-grants"
# TTL の単一ソース (fable-budget.conf)。欠落時はフォールバック既定値 600s。
# shellcheck disable=SC1090
conf="${FABLE_BUDGET_CONF:-$(dirname "${BASH_SOURCE[0]}")/../skills/swarm-implement/scripts/fable-budget.conf}"
[ -f "$conf" ] && . "$conf"
: "${FABLE_GRANT_TTL_SECONDS:=600}"
ttl=$FABLE_GRANT_TTL_SECONDS
now=$(date +%s)

block() {
    jq -nc --arg reason "FABLE_GATE: $1" '{"decision":"block","reason":$reason}' 2>/dev/null ||
        printf '{"decision":"block","reason":"FABLE_GATE: %s"}\n' "$1"
    exit 2
}

# grant は task に束縛される: スポーン prompt の [fable-spot:<task-id>] マーカーと
# grant ファイル名 (<epoch_nanos>-<task-id>) の task-id を突き合わせ、同一 task の grant
# のみ消費する。これが無いと、budget-guard を通していない別 task のスポーンが他 task の
# grant を黙って窃取できてしまう (集約上限は保たれるが帰属が壊れる)。
prompt=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty' 2>/dev/null || true)
marker=$(printf '%s' "$prompt" | grep -oE '\[fable-spot:[^]]+\]' | head -1 || true)
[ -n "$marker" ] || block "fable スポーンの prompt に [fable-spot:<task-id>] マーカーが無い — grant は task に束縛される。budget-guard.sh --fable に渡したのと同一の task-id を prompt に含めること (SWARM.md §1 スポット判断層)"
tid="${marker#\[fable-spot:}"
tid="${tid%\]}"
sanitized_tid="${tid//\//_}"

no_grant_msg="task '$tid' の未消費 fable grant が無い — budget-guard.sh --fable <task-id> [--mission=<slug>] を先に通すこと (発動 4 条件・回数上限は SWARM.md §1 スポット判断層。grant は発行から ${ttl}s で失効・1 grant = 1 スポーン・task 束縛)"

[ -d "$grants_dir" ] || block "$no_grant_msg"

# 当該 task の最も古い grant から消費する (ファイル名先頭が epoch-nanos のため glob の
# 辞書順 = 時刻順)。消費は mv による原子的な奪い合いで直列化し、並行スポーンでの
# 二重消費を防ぐ。一時名は必ずドット始まりにする — mv と rm の間で異常終了しても、
# 残骸が次回の glob (*) にマッチして「消費済み grant の再利用」にならないようにするため。
# 期限切れ掃除は task を問わず全 grant に適用する (機会主義的クリーンアップ)。
consumed=""
for gf in "$grants_dir"/*; do
    [ -f "$gf" ] || continue
    mt=$(stat -c %Y "$gf" 2>/dev/null || echo 0)
    if [ $((now - mt)) -gt "$ttl" ]; then
        rm -f "$gf" # 期限切れ掃除 (全 task 対象)
        continue
    fi
    gtask="$(basename "$gf")"
    gtask="${gtask#*-}"
    [ "$gtask" = "$sanitized_tid" ] || continue # 他 task の grant には触れない
    tmp="$grants_dir/.consuming.$$"
    if mv "$gf" "$tmp" 2>/dev/null; then
        consumed="$(basename "$gf")"
        rm -f "$tmp"
        break
    fi
done

[ -n "$consumed" ] || block "$no_grant_msg"

info "swarm-fable-gate: fable spot grant consumed ($consumed, task=$tid)"
exit 0
