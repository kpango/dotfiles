#!/usr/bin/env bash
# agent/SYSTEM-<tool>-supplement.md(ツール固有: アイデンティティ宣言・冒頭のBehavioral/Operational
# Directives)+ agent/SYSTEM.md(汎用コア: 全ツール共通のSecurity/Teamwork-Preview/Deterministic
# Tool Supremacy)を連結して pi/SYSTEM.md・agy/SYSTEM.md(実体ファイル)を機械生成する。
#
# agent/scripts/gen-tool-agents.sh(AGENTS.md用)と連結順が逆(こちらは supplement が先、core が後)
# なのは意図的: システムプロンプトは「あなたは<ツール名>である」という自己同一化の宣言が
# 常に先頭に来る必要があるため、ツール名を持たない汎用コアを先頭には置けない。
#
# claude には対応する SYSTEM.md 相当ファイルが無い(Claude Codeのsystem promptはユーザーが
# 永続ファイルで上書きする仕組みを持たず、`--append-system-prompt`という都度指定のCLIフラグのみ
# — 2026-09-03、code.claude.com/docs/en/memory実査で確認: 「CLAUDE.md content is delivered as
# a user message after the system prompt, not as part of the system prompt itself」)。
# codex にも同種のファイルは無い(このリポジトリで確認できる範囲では)。よってpi/agyの2ツールのみが
# 対象。
#
# usage: agent/scripts/gen-tool-system.sh [pi|agy|all] [--check]
#   第1引数省略時は "all"(pi・agy両方を対象)。
#   --check: 書き込みは行わず、対象の現行 <tool>/SYSTEM.md との差分有無のみを報告する
#            (exit 1 = 差分あり)。
#
# agent/sync-manifest.json の generate モードは「1 target = 1 script」の呼び出し契約
# (sync-verify.sh が `$script --check` を引数無しで呼ぶ)であるため、pi/agy それぞれの
# manifest entry からは本体を直接ではなく agent/scripts/gen-system-md-for-pi.sh /
# agent/scripts/gen-system-md-for-agy.sh という薄いラッパー経由で呼ぶ
# (agent/scripts/gen-agents-md-for-{pi,agy}.sh と同じパターン)。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
core="$root/agent/SYSTEM.md"
# shellcheck source=agent/scripts/harness-check-lib.sh
source "$(dirname "$0")/harness-check-lib.sh"

# 引数検証(usage・$#検査・--check特例・case文)は harness-check-lib.sh の
# harness_parse_tool_args に集約されている(gen-tool-agents.sh と重複していた約25行)。
harness_parse_tool_args "$0" "$@"
target_arg="$HARNESS_TARGET_ARG"
check_only="$HARNESS_CHECK_ONLY"

gen_one() {
    local tool="$1" dst="$2"
    local supplement="$root/agent/SYSTEM-${tool}-supplement.md"
    local generated
    generated="$(
        cat "$supplement"
        printf '\n'
        printf '> Generated section below — do not edit directly. Canonical source:\n'
        printf '> `agent/SYSTEM.md` (shared directives). Regenerate with\n'
        printf '> `agent/scripts/gen-tool-system.sh %s`.\n\n' "$tool"
        cat "$core"
    )"
    harness_sync_generated_file "$generated" "$dst" "$check_only" \
        "$dst は agent/SYSTEM-${tool}-supplement.md + agent/SYSTEM.md と同期済み"
}

fail=0
case "$target_arg" in
    pi) gen_one "pi" "$root/agent/harnesses/pi/SYSTEM.md" || fail=1 ;;
    agy) gen_one "agy" "$root/agent/harnesses/agy/SYSTEM.md" || fail=1 ;;
    all)
        gen_one "pi" "$root/agent/harnesses/pi/SYSTEM.md" || fail=1
        gen_one "agy" "$root/agent/harnesses/agy/SYSTEM.md" || fail=1
        ;;
    *)
        echo "usage: $0 [pi|agy|all] [--check]" >&2
        exit 2
        ;;
esac

exit "$fail"
