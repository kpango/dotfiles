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

if [ "$model" != "fable" ] && [ "$model" != "Max" ] && [ "$model" != "claude-fable-5" ] && [ "$model" != "claude-fable-5-1" ]; then
    if [ "$subagent" = "debugger" ] && [ -z "$model" ]; then
        info "swarm-fable-gate: debugger を model 未指定で起動しようとしている — debugger の frontmatter は model: inherit のため Fable/Max セッションでは暗黙に Fable/Max を消費する。swarm の Fixer は model: \"High\" (または \"sonnet\") を明示すること (SWARM.md §1)"
    fi
    exit 0
fi

grants_dir="$HOME/.claude/session-data/swarm/budget/.fable-grants"
# ROOT解決(readlink -fでファイル自身のsymlinkを先に解決してからdirnameする)の経緯・理由は
# agent/README.md「既知の限界（fail-open）」節(2026-09-03 CRITICAL回帰の記録)を参照。要点のみ:
# merged directory化(ディレクトリ全体symlink→per-file symlink)後は`dirname`がファイル名を落として
# から評価されるため、`cd -P dirname($BASH_SOURCE)`だけではファイル自身のsymlinkが未解決のまま
# (実測で確認済み)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
# TTL の単一ソース (fable-budget.conf)。欠落時はフォールバック既定値 600s。
# shellcheck disable=SC1090
conf="${FABLE_BUDGET_CONF:-$ROOT/agent/skills/swarm-implement/scripts/fable-budget.conf}"
[ -f "$conf" ] && . "$conf"
: "${FABLE_GRANT_TTL_SECONDS:=600}"
ttl=$FABLE_GRANT_TTL_SECONDS
now=$(date +%s)

block() {
    # exit 2 時、Claude Codeはstdoutを無視しstderrのみ読む(公式仕様) — reasonは必ずstderrへ出力する。
    echo "[swarm-fable-gate] FABLE_GATE: $1" >&2
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

# grant消費ループ(TTL失効チェック+mvによる原子的消費)はswarm-write-scope-gate.shと
# 一字一句同一だったため agent/skills/swarm-implement/scripts/swarm-lint-lib.sh の
# grant_consume() へ統合済み(2026-09-03)。$ROOT は上記conf解決と同じ`cd -P`物理解決由来。
lint_lib="$ROOT/agent/skills/swarm-implement/scripts/swarm-lint-lib.sh"
# shellcheck disable=SC1090
[ -f "$lint_lib" ] && . "$lint_lib"
consumed=""
if command -v grant_consume >/dev/null 2>&1; then
    consumed=$(grant_consume "$grants_dir" "$ttl" "$sanitized_tid") || consumed=""
fi

[ -n "$consumed" ] || block "$no_grant_msg"

info "swarm-fable-gate: fable spot grant consumed ($consumed, task=$tid)"
exit 0
