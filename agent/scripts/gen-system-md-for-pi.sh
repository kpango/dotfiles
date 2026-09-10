#!/usr/bin/env bash
# agent/sync-manifest.json の generate モード呼び出し契約(`$script --check` を追加引数無しで
# 呼ぶ)に合わせた薄いラッパー。実体は agent/scripts/gen-tool-system.sh pi。
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gen-tool-system.sh" pi "$@"
