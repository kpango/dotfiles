#!/usr/bin/env bash
# 探索対象ディレクトリ(またはファイル)を列挙し、対象ごとの出現回数を weight として N 個の
# シャードに分割し JSON で出力する。weight はシャードの情報量の目安であり、swarm-explore が
# Haiku の effort(low/medium)を静的ルーティングする基準として使う。
# usage: shard-targets.sh <repo-root> [num-shards=10] [go|rust|docker|all]
set -euo pipefail

root="${1:?usage: shard-targets.sh <repo-root> [num-shards] [go|rust|docker|all]}"
shards="${2:-10}"
lang="${3:-all}"

cd "$root"

# 各対象の出現回数 = weight (go/rust はディレクトリ内ファイル数、docker はファイル単位で常に1)。
# "  N target" 形式(uniq -c)で出力する。
list_go()     { find . -name '*.go' -not -path './vendor/*' -not -path './.git/*' \
                  -not -path './.claude/*' -not -name '*.pb.go' -printf '%h\n' | sort | uniq -c; }
list_rust()   { find . -name 'Cargo.toml' -not -path './.git/*' -not -path '*/target/*' \
                  -printf '%h\n' | sort | uniq -c; }
list_docker() { find . \( -name '*.Dockerfile' -o -name 'Dockerfile' \) \
                  -not -path './.git/*' | sort | uniq -c; }

case "$lang" in
  go)     weighted=$(list_go) ;;
  rust)   weighted=$(list_rust) ;;
  docker) weighted=$(list_docker) ;;
  all)    weighted=$( { list_go; list_rust; list_docker; } \
            | awk '{n=$1; $1=""; sub(/^[ \t]+/,""); c[$0]+=n} END {for (d in c) print c[d], d}') ;;
  *) echo "unknown lang: $lang" >&2; exit 1 ;;
esac

total=$(printf '%s\n' "$weighted" | grep -c . || true)
if [ "$total" -eq 0 ]; then
  echo '[]'
  exit 0
fi
[ "$shards" -gt "$total" ] && shards="$total"

# weight 降順の貪欲法(LPT: Longest Processing Time First)で N シャードへ配分し、
# 各シャードを {dirs, weight} として JSON 出力する。shard.weight が effort 静的ルーティングの基準。
printf '%s\n' "$weighted" | sort -rn | jq -Rn --argjson n "$shards" '
  [inputs | select(length > 0)
   | capture("^\\s*(?<w>[0-9]+)\\s+(?<d>.+)$")
   | {dir: .d, weight: (.w | tonumber)}]
  | reduce .[] as $item (
      [range($n) | {dirs: [], weight: 0}];
      (map(.weight) | index(min)) as $i
      | .[$i].dirs += [$item.dir]
      | .[$i].weight += $item.weight
    )'
