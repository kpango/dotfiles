#!/usr/bin/env bash
# swarm-memory-sync が auto-memory へ書く前に必ず実行する決定論的チェック。
# 「重複チェック・肥大化防止を LLM の自己判断だけに委ねない」(SWARM.md §2/§6 の
# 決定論的ツール第一権威原則)ための機械的な情報提供。判定(書くか書かないか)自体はしない —
# 候補の提示と閾値超過の警告のみ。exit codeは常に0(ブロックしない、判断材料の提示のみ)。
# usage: memory-guard.sh <topic-keyword> [<topic-keyword> ...]
set -euo pipefail

memory_dir="$HOME/.claude/memory"
index="$memory_dir/MEMORY.md"

if [ "$#" -eq 0 ]; then
  echo "usage: memory-guard.sh <topic-keyword> [<topic-keyword> ...]" >&2
  exit 1
fi

echo "=== MEMORY.md size check ==="
if [ -f "$index" ]; then
  lines=$(wc -l <"$index")
  bytes=$(wc -c <"$index")
  echo "lines=$lines bytes=$bytes (auto-load limit: first 200 lines / 25KB)"
  if [ "$lines" -ge 180 ] || [ "$bytes" -ge 23000 ]; then
    echo "WARNING: MEMORY.md is approaching the auto-load limit — consolidate before adding more entries."
  fi
else
  echo "MEMORY.md not found at $index"
fi

echo
echo "=== duplicate-topic candidates ==="
found=0
for kw in "$@"; do
  matches=$(grep -ril -- "$kw" "$memory_dir"/*.md 2>/dev/null | grep -v "/MEMORY.md$" || true)
  if [ -n "$matches" ]; then
    echo "keyword \"$kw\" matches existing files:"
    echo "$matches" | sed 's/^/  /'
    found=1
  fi
done
if [ "$found" -eq 0 ]; then
  echo "no existing file matched the given keywords — likely safe to create a new file."
else
  echo "NOTE: prefer Edit-ing an existing match above over creating a new file."
fi
