#!/usr/bin/env bash
# swarm-memory-sync が auto-memory へ書く前に必ず実行する決定論的チェック。
# 「重複チェック・肥大化防止を LLM の自己判断だけに委ねない」(SWARM.md §2/§6 の
# 決定論的ツール第一権威原則)ための機械的な情報提供。判定(書くか書かないか)自体はしない —
# 候補の提示と閾値超過の警告のみ。exit codeは常に0(ブロックしない、判断材料の提示のみ)。
# usage: memory-guard.sh <topic-keyword> [<topic-keyword> ...]
#        memory-guard.sh --record <file-name> <created|updated>
set -euo pipefail

memory_dir="$HOME/.claude/memory"
index="$memory_dir/MEMORY.md"
edit_log="$memory_dir/.edit-log.jsonl"

# --record モード: swarm-memory-sync が Write/Edit した直後に呼ぶ。継続更新による劣化
# (arXiv:2605.12978: LLM が継続的に上書き更新するメモリは ground truth から drift する)を
# 検出するための唯一のソースがこのログ — auto-memory は git 管理されないため file mtime だけでは
# 「何回書き換えたか」を追えない。
if [ "${1:-}" = "--record" ]; then
  file="${2:?usage: memory-guard.sh --record <file-name> <created|updated>}"
  op="${3:?usage: memory-guard.sh --record <file-name> <created|updated>}"
  case "$op" in created|updated) ;; *) echo "op must be 'created' or 'updated'" >&2; exit 1 ;; esac
  mkdir -p "$memory_dir"
  printf '{"ts":"%s","file":"%s","op":"%s"}\n' "$(date -Is)" "$file" "$op" >>"$edit_log"
  # 肥大化防止(このログ自体が auto-memory の一部ではないため MEMORY.md の 200行/25KB 制約は適用外だが、
  # 無制限成長を避けるため 2000 行超で直近 1000 行へ自動ローテーションする(write-scope-log.jsonl と同型)。
  if [ -f "$edit_log" ] && [ "$(wc -l <"$edit_log")" -gt 2000 ]; then
    tail -n 1000 "$edit_log" >"$edit_log.tmp" && mv "$edit_log.tmp" "$edit_log"
  fi
  exit 0
fi

if [ "$#" -eq 0 ]; then
  echo "usage: memory-guard.sh <topic-keyword> [<topic-keyword> ...]" >&2
  echo "       memory-guard.sh --record <file-name> <created|updated>" >&2
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

echo
echo "=== continuous-update degradation risk (arXiv:2605.12978) ==="
if [ -f "$edit_log" ]; then
  for kw in "$@"; do
    matches=$(grep -ril -- "$kw" "$memory_dir"/*.md 2>/dev/null | grep -v "/MEMORY.md$" || true)
    for m in $matches; do
      bn=$(basename "$m")
      update_count=$(grep -c "\"file\":\"$bn\".*\"op\":\"updated\"" "$edit_log" 2>/dev/null || true)
      update_count=${update_count:-0}
      if [ "$update_count" -ge 3 ]; then
        echo "WARNING: $bn has been rewritten $update_count times — repeated free-form overwriting risks drift from ground truth (arXiv:2605.12978). Prefer appending a dated addendum (e.g. a new bullet or '## 追記' subsection) over further in-place rewriting of existing sentences."
      fi
    done
  done
else
  echo "no edit-log yet (no --record calls recorded)"
fi
