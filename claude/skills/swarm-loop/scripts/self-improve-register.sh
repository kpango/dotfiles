#!/usr/bin/env bash
# 自己改善ミッションを self-improve-registry.tsv へ登録する(GATE 完了時の必須ブックキーピング)。
# これまで手動追記に依存しており、2回連続(all-skills-phrasing-audit・memory-driven-agent-skill-dev)で
# 登録漏れが発生したため機械化した(SWARM.md §5「2回目の学びの機械化」)。
# usage: self-improve-register.sh <slug> <date:YYYY-MM-DD> <targets(comma-separated)>
# 冪等: 同一 slug が既に登録済みなら何もせず exit 0(重複行を作らない)。
set -euo pipefail

slug="${1:?usage: self-improve-register.sh <slug> <date:YYYY-MM-DD> <targets>}"
date_str="${2:?date (YYYY-MM-DD) required}"
targets="${3:?comma-separated targets required}"

if ! printf '%s' "$date_str" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "REFUSE: date=\"$date_str\" must be YYYY-MM-DD" >&2
  exit 1
fi

registry="$(cd "$(dirname "$0")/.." && pwd)/self-improve-registry.tsv"

if [ ! -f "$registry" ]; then
  echo "REFUSE: registry not found at $registry" >&2
  exit 1
fi

# check-then-append を flock で直列化する(budget-guard.sh の共有カウンタと同じパターン)。
# ロック無しだと並行呼び出し(同一 slug の重複起動)が両方 "not found" を読んで二重登録し、
# 冪等性(重複行を作らない)が破れる。
lockfile="$registry.lock"
{
  flock -x 200
  if awk -F'\t' -v s="$slug" '$1 == s { found=1 } END { exit !found }' "$registry"; then
    echo "SKIP: $slug already registered (idempotent no-op)"
    exit 0
  fi

  printf '%s\t%s\t%s\n' "$slug" "$date_str" "$targets" >>"$registry"
  echo "REGISTERED: $slug $date_str $targets"
} 200>"$lockfile"
