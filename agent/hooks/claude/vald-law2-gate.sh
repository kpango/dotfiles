#!/usr/bin/env bash
# PreToolUse:Bash hook — Vald Law 2: no direct toolchain invocation
#
# ルールデータは agent/vald-law-rules.json (claude/agy/pi 共通) を読む。判定アルゴリズムは
# agent/scripts/hooks/rule_engine.py + decide.py へ統合済み(2026-09-03)。本ファイルは
# I/Oプロトコル変換のみを持つ薄いシム。
set -euo pipefail

if ! command -v jq &>/dev/null; then
    exit 0
fi

INPUT=$(cat || true)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[[ -z "$COMMAND" ]] && exit 0

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

# このhookは vald リポジトリの project-level .claude/settings.json でのみ配線される
# (CLAUDE.md「### Vald Project Hooks」参照) ため、scope_mode="none"(スコープ判定をせず
# 常に評価する)を渡す。security-audit指摘(2026-09-03)により、一時的にcwdベースのvald判定を
# 追加していたことが逆に `cd /other-repo && ...` のようなセッション中の作業ディレクトリ移動で
# Law2 チェック自体を丸ごとスキップさせるbypass経路になっていたため削除した経緯を持つ
# (配線されている限り無条件にチェックする、という元のclaude実装の設計をscope_mode="none"で
# 保持する)。$COMMAND 自身に埋め込まれた `cd <vald-path> && <prohibited command>` のような
# bypassは、rule_engine.evaluate_vald_law2 が $COMMAND 全体に対して判定パターンをそのまま
# 当てるため(cwdを経由しない)引き続き検出される。
REQUEST=$(jq -n --arg cmd "$COMMAND" --arg cwd "$(pwd)" --arg rules "$RULES_FILE" \
    '{family: "vald_law2", command: $cmd, cwd: $cwd, vald_rules_file: $rules, scope_mode: "none"}')

if command -v timeout &>/dev/null; then
    RESULT=$(echo "$REQUEST" | timeout 10 python3 "$DECIDE" 2>/dev/null) || exit 0
else
    RESULT=$(echo "$REQUEST" | python3 "$DECIDE" 2>/dev/null) || exit 0
fi
DECISION=$(echo "$RESULT" | jq -r '.decision // "allow"' 2>/dev/null || echo "allow")

if [[ "$DECISION" == "block" ]]; then
    REASON=$(echo "$RESULT" | jq -r '.reason // "Vald Law 2 violation"' 2>/dev/null || echo "Vald Law 2 violation")
    jq -n --arg reason "$REASON" '{"decision":"block","reason":$reason}'
    exit 2
fi

exit 0
