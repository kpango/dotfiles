#!/usr/bin/env bash
# 探索対象ディレクトリを列挙して N 個のシャードに分割し JSON で出力する。
# usage: shard-targets.sh <repo-root> [num-shards=10] [go|rust|docker|all]
set -euo pipefail

root="${1:?usage: shard-targets.sh <repo-root> [num-shards] [go|rust|docker|all]}"
shards="${2:-10}"
lang="${3:-all}"

cd "$root"

list_go()     { find . -name '*.go' -not -path './vendor/*' -not -path './.git/*' \
                  -not -path './.claude/*' -not -name '*.pb.go' -printf '%h\n' | sort -u; }
list_rust()   { find . -name 'Cargo.toml' -not -path './.git/*' -not -path '*/target/*' \
                  -printf '%h\n' | sort -u; }
list_docker() { find . \( -name '*.Dockerfile' -o -name 'Dockerfile' \) \
                  -not -path './.git/*' | sort -u; }

case "$lang" in
  go)     targets=$(list_go) ;;
  rust)   targets=$(list_rust) ;;
  docker) targets=$(list_docker) ;;
  all)    targets=$( { list_go; list_rust; list_docker; } | sort -u) ;;
  *) echo "unknown lang: $lang" >&2; exit 1 ;;
esac

total=$(printf '%s\n' "$targets" | grep -c . || true)
if [ "$total" -eq 0 ]; then
  echo '[]'
  exit 0
fi
[ "$shards" -gt "$total" ] && shards="$total"

# round-robin で N シャードに分割した JSON (配列の配列) を出力
printf '%s\n' "$targets" | jq -Rn --argjson n "$shards" '
  [inputs | select(length > 0)]
  | to_entries
  | group_by(.key % $n)
  | map(map(.value))'
