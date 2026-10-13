#!/usr/bin/env bash
# PreToolUse:Write|Edit — block writes to sensitive system paths
#
# ルールデータは agent/security-rules.json (claude/agy/pi 共通) の sensitive_write_path_rules を
# 読む。判定アルゴリズム(パス候補生成・照合)は agent/scripts/hooks/rule_engine.py + decide.py へ
# 統合済み(2026-09-03)。本ファイルはI/Oプロトコル変換のみ。
set -euo pipefail

INPUT=$(cat || true)

if ! command -v jq &>/dev/null; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0

# ~/.claude/hooks は claude/hooks/ と agent/hooks/claude/ の2ソースを合成したmerged directory
# (per-file symlink、2026-09-03以降)であり、ディレクトリ自体はsymlinkではない —
# `readlink -f`でファイル自身のsymlinkを先に解決してから`dirname`する必要がある
# (GNU coreutils限定、実測で確認済み。security-gate.sh と同じ理由)。
HERE="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$HERE/../../.." && pwd)"
RULES_FILE="$ROOT/agent/security-rules.json"
DECIDE="$ROOT/agent/scripts/hooks/decide.py"

[[ -f "$RULES_FILE" ]] || exit 0
[[ -f "$DECIDE" ]] || exit 0
command -v python3 &>/dev/null || exit 0

REQUEST=$(jq -n --arg path "$FILE_PATH" --arg cwd "$(pwd)" --arg home "$HOME" --arg rules "$RULES_FILE" \
    '{family: "security_write", file_path: $path, cwd: $cwd, home: $home, rules_file: $rules}')

# timeout: agy(subprocess timeout=10)・pi(execFileSync timeout:10000)と揃える(security-audit
# 指摘2026-09-03、security-gate.shと同じ理由)。
if command -v timeout &>/dev/null; then
    RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || exit 0
else
    RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || exit 0
fi
DECISION=$(echo "$RESULT" | jq -r '.decision // "allow"' 2>/dev/null || echo "allow")

if [[ "$DECISION" == "block" ]]; then
    # 報告するパス文字列は旧実装どおり realpath -m (ローカル解決) を使う — decide.pyが返す
    # resolved_path はpi実装の「cwd結合のみ、realpath未解決」の値であり、claudeの過去の
    # メッセージ文言(realpath -m 適用済み)とは異なるため、メッセージ整形はこのシムで行う。
    REPORT_PATH="${FILE_PATH/#\~/$HOME}"
    REPORT_PATH=$(realpath -m -- "$REPORT_PATH" 2>/dev/null || echo "$REPORT_PATH")
    jq -n --arg path "$REPORT_PATH" \
        '{"decision":"block","reason":("Write to sensitive path blocked by security gate: "+$path)}'
    exit 2
fi

exit 0
