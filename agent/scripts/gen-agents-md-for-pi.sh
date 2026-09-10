#!/usr/bin/env bash
# agent/sync-manifest.json の generate モード呼び出し契約(`$script --check` を追加引数無しで
# 呼ぶ)に合わせた薄いラッパー。実体は agent/scripts/gen-tool-agents.sh pi
# (pi/AGENTS.md 自体を生成する。pi/agents/*.mdのtools:frontmatter変換は2026-09-03以降
# pi/extensions/subagents.tsの実行時変換へ移行しており、本スクリプトとは無関係)。
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gen-tool-agents.sh" pi "$@"
