#!/usr/bin/env bash
# PreToolUse:Bash hook — blocks catastrophic and irreversible commands
#
# ルールデータは agent/security-rules.json (claude/agy/pi 共通) を読む。判定アルゴリズム自体
# (all_of/any_of/not_any_of の評価・force_push/git_reset_hard の特別扱い)は
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み(2026-09-03、claude/agy/piで3回
# 独立に再実装されていたロジックを1箇所化)。本ファイルはI/Oプロトコル変換のみを持つ薄いシム:
# stdin JSON → decide.pyへの正規化リクエスト → decide.pyの3値決定(allow/ask/block)を
# claude固有の出力形式(block: exit 2、ask: hookSpecificOutput、allow: 無出力+exit 0)へ変換する。
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
    exit 0
fi

COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -z "$COMMAND" ]] && exit 0

# claude/hooks は ~/.claude/hooks へのsymlinkのため、BASH_SOURCEのdirnameを素朴に
# `..`で辿ると(bashの論理cdがsymlinkを跨いでシンボリック経路の文字列上でしか`..`を
# 解決しない場合がある)実体と異なるディレクトリに着地しうる。`cd -P`(物理解決)で
# symlinkを辿った実体ディレクトリを得てから`..`するのが安全(実測で確認済み)。
# 追記(2026-09-03、agent-hooks-and-pi-agents-unificationミッション): ~/.claude/hooksがmerged
# directory(per-file symlink、claude/hooks/とagent/hooks/claude/の2ソース合成)化されたことで、
# `dirname`がファイル名を落としてから評価される点が新たな問題になった — ディレクトリ自体は
# symlinkではなくなったため`cd -P dirname($BASH_SOURCE)`だけではファイル自身のsymlinkが未解決の
# まま実体ディレクトリへ到達しない(実測で確認済み)。`readlink -f`でファイル自身のsymlinkを
# 先に解決してから`dirname`する(GNU coreutils限定、sync-verify.shの既存コメントと同じ制約)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/security-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

# ルールデータ/エンジン欠落時は fail-open(jq欠落時と同じ方針、致命的にしない)。
[[ -f "$RULES_FILE" ]] || exit 0
[[ -f "$DECIDE" ]] || exit 0
command -v python3 &>/dev/null || exit 0

# git_reset_hard_protected_branch のcd/-Cターゲット抽出は、claude旧実装が「抽出した(相対のままの)
# 文字列をそのまま git -C へ渡し、hookプロセス自身のcwd基準でgitに解決させる」設計だった
# (pi実装のみ path.resolve(ctx.cwd, targetDir) で明示的に絶対化する)。resolve_command_target=false
# でこの挙動を保持する — decide.py側のsubprocess.runもcwd引数を渡さないため、Pythonプロセス自身の
# cwd(=このhookを起動したシェルのcwdをそのまま継承)を基準にgit -Cが解決する点で意味論は同一。
REQUEST=$(jq -n --arg cmd "$COMMAND" --arg cwd "$(pwd)" --arg rules "$RULES_FILE" \
    '{family: "security_shell", command: $cmd, cwd: $cwd, rules_file: $rules, resolve_command_target: false}')

# timeout: agy(subprocess timeout=10)・pi(execFileSync timeout:10000)と揃える(security-audit
# 指摘2026-09-03: claude側のみdecide.py呼び出しにtimeoutが無く、3実装で非対称だった)。
# `timeout`コマンド自体が無い環境ではそのまま素通り(fail-openの既存方針を維持)。
if command -v timeout &>/dev/null; then
    RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || exit 0
else
    RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || exit 0
fi
DECISION=$(echo "$RESULT" | jq -r '.decision // "allow"' 2>/dev/null || echo "allow")
REASON=$(echo "$RESULT" | jq -r '.reason // ""' 2>/dev/null || echo "")

case "$DECISION" in
    block)
        jq -n --arg reason "SECURITY GATE: $REASON" '{"decision":"block","reason":$reason}' 2>/dev/null || \
            printf '{"decision":"block","reason":"SECURITY GATE: %s"}\n' "$REASON"
        exit 2
        ;;
    ask)
        jq -n --arg reason "SECURITY GATE: $REASON" \
            '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":$reason}}' 2>/dev/null || \
            printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"SECURITY GATE: %s"}}\n' "$REASON"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
