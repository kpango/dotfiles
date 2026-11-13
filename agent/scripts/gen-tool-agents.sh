#!/usr/bin/env bash
# agent/AGENTS.md(汎用コア、AGENTS.md仕様準拠)+ agent/AGENTS-<tool>-supplement.md(ツール固有補完)を
# 連結して pi/AGENTS.md・agy/AGENTS.md(実体ファイル)を機械生成する。
#
# 背景: claude だけは CLAUDE.md の `@path` インポート構文で agent/AGENTS.md と
# agent/AGENTS-claude-supplement.md を実行時に動的合成できる(claude/CLAUDE.md 参照)。
# pi/agy にはこの種のインポート構文が無い(2026-09-03、pi.dev公式クイックスタート・agy公式ドキュメント
# 実査で確認済み)ため、生成パターンをAGENTS.mdにも適用する(pi/agents/*.mdのtools:frontmatter変換は
# 2026-09-03以降 pi/extensions/subagents.ts の実行時変換へ移行済みで本スクリプトとは別物)。
#
# usage: agent/scripts/gen-tool-agents.sh [pi|agy|all] [--check]
#   第1引数省略時は "all"(pi・agy両方を対象)。
#   --check: 書き込みは行わず、対象の現行 <tool>/AGENTS.md との差分有無のみを報告する
#            (exit 1 = 差分あり)。
#
# agent/sync-manifest.json の generate モードは「1 target = 1 script」の呼び出し契約
# (sync-verify.sh が `$script --check` を引数無しで呼ぶ)であるため、pi/agy それぞれの
# manifest entry からは本体を直接ではなく agent/scripts/gen-agents-md-for-pi.sh /
# agent/scripts/gen-agents-md-for-agy.sh という薄いラッパー経由で呼ぶ(下記参照)。
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
core="$root/agent/AGENTS.md"
# shellcheck source=agent/scripts/harness-check-lib.sh
source "$(dirname "$0")/harness-check-lib.sh"

# 引数検証(usage・$#検査・--check特例・case文)は harness-check-lib.sh の
# harness_parse_tool_args に集約されている(gen-tool-system.sh と重複していた約25行)。
harness_parse_tool_args "$0" "$@"
target_arg="$HARNESS_TARGET_ARG"
check_only="$HARNESS_CHECK_ONLY"

gen_one() {
    local tool="$1" dst="$2"
    local supplement="$root/agent/AGENTS-${tool}-supplement.md"
    local generated
    generated="$(
        printf '> Generated file — do not edit directly. Canonical sources: `agent/AGENTS.md`\n'
        printf '> (generic core) + `agent/AGENTS-%s-supplement.md` (tool-specific supplement).\n' "$tool"
        printf '> Regenerate with `agent/scripts/gen-tool-agents.sh %s`.\n\n' "$tool"
        cat "$core"
        printf '\n'
        cat "$supplement"
    )"
    harness_sync_generated_file "$generated" "$dst" "$check_only" \
        "$dst は agent/AGENTS.md + agent/AGENTS-${tool}-supplement.md と同期済み"
}

fail=0
case "$target_arg" in
    pi) gen_one "pi" "$root/agent/harnesses/pi/AGENTS.md" || fail=1 ;;
    agy) gen_one "agy" "$root/agent/harnesses/agy/AGENTS.md" || fail=1 ;;
    all)
        gen_one "pi" "$root/agent/harnesses/pi/AGENTS.md" || fail=1
        gen_one "agy" "$root/agent/harnesses/agy/AGENTS.md" || fail=1
        ;;
    *)
        echo "usage: $0 [pi|agy|all] [--check]" >&2
        exit 2
        ;;
esac

exit "$fail"
