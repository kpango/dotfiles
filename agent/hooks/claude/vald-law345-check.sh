#!/usr/bin/env bash
# PreToolUse:Write|Edit|MultiEdit hook — Vald Law 3/4/5: no panic/log.Fatal, no discarded
# errors, no stdlib log/errors/sync/strings imports in production (non-test) Go code.
#
# ルールデータは agent/vald-law-rules.json (claude/agy/pi 共通) を読む。判定アルゴリズムは
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み(2026-09-03)。本ファイルは
# I/Oプロトコル変換のみを持つ薄いシム。旧実装はPostToolUse(書き込み後にファイルを読んで
# additionalContext で警告するのみ、ブロックしない)だったが、agy実装(PreToolUse hard block)
# との強制力の食い違いを解消するため、PreToolUse ask-tierへ引き上げた(security-rules.jsonの
# git_clean_force_only等と同じ設計判断)。Write/Edit/MultiEditそれぞれのtool_inputフィールド
# (content / old_string+new_string / edits[])は実測で確認したスキーマに基づく。
set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat || true)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || true)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)
[[ -z "$FILE_PATH" ]] && exit 0
[[ "$FILE_PATH" == *.go ]] || exit 0

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成したmerged directory
# (per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/vald-law-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

[[ -f "$RULES_FILE" ]] || exit 0
[[ -f "$DECIDE" ]] || exit 0
command -v python3 &>/dev/null || exit 0

# Writeは新規全文(content)、Editは変更断片(new_string)、MultiEditは各edits[].new_stringを
# 連結して検査する。「この変更が新たに持ち込む違反」に絞る設計(旧PostToolUse実装はWrite/Edit
# 問わずファイル全文を毎回再走査していたため、そのEditが触れていない既存箇所の指摘まで混入して
# いた — 意図的な変更、agent/README.mdに記録)。
case "$TOOL_NAME" in
    Write) CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""') ;;
    Edit) CONTENT=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""') ;;
    MultiEdit) CONTENT=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string // empty] | join("\n")') ;;
    *) exit 0 ;;
esac
[[ -z "$CONTENT" ]] && exit 0

# このhookは vald リポジトリの project-level .claude/settings.json でのみ配線されるため、
# scope_mode="none"(スコープ判定をせず常に評価する、Law2シムと同じ理由)を渡す。
REQUEST=$(jq -n --arg path "$FILE_PATH" --arg content "$CONTENT" --arg rules "$RULES_FILE" \
    '{family: "vald_law345", file_path: $path, content: $content, vald_rules_file: $rules, scope_mode: "none"}')

if command -v timeout &>/dev/null; then
    RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || exit 0
else
    RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || exit 0
fi
DECISION=$(echo "$RESULT" | jq -r '.decision // "allow"' 2>/dev/null || echo "allow")
[[ "$DECISION" == "ask" ]] || exit 0

mapfile -t VIOLATIONS < <(echo "$RESULT" | jq -r '.violations[]? // empty' 2>/dev/null)
[[ ${#VIOLATIONS[@]} -eq 0 ]] && exit 0

REASON="Vald Law violation(s) in ${FILE_PATH##*/}:"
for v in "${VIOLATIONS[@]}"; do
    REASON="$REASON"$'\n'"- $v"
done

jq -n --arg reason "$REASON" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":$reason}}'
exit 0
