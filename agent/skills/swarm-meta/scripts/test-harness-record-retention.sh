#!/usr/bin/env bash
# harness-record.sh の保持上限テスト (一時 registry 上で実行)。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
export HARNESS_REGISTRY="$t/reg.tsv" HARNESS_REGISTRY_KEEP_GRAPH=3 HARNESS_REGISTRY_KEEP_OTHER=2
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected=[$2] actual=[$3]"; fail=1; fi; }
for i in 1 2 3 4 5; do "$here/harness-record.sh" "g$i" swarm-graph parallel m "done=$i blocked=0" >/dev/null; done
for i in 1 2 3 4 5; do "$here/harness-record.sh" "l$i" swarm-loop neutral m "done=$i blocked=0" >/dev/null; done
check "graph rows capped to newest 3" "g3 g4 g5" "$(awk -F'\t' '$3=="swarm-graph"{printf "%s ",$2}' "$HARNESS_REGISTRY" | sed 's/ $//')"
check "other rows capped to newest 2" "l4 l5" "$(awk -F'\t' '$3=="swarm-loop"{printf "%s ",$2}' "$HARNESS_REGISTRY" | sed 's/ $//')"
check "header kept" "1" "$(grep -c '^# date' "$HARNESS_REGISTRY")"
"$here/harness-record.sh" g5 swarm-graph parallel m "done=9 blocked=0" >/dev/null
check "idempotent replace keeps count" "3" "$(awk -F'\t' '$3=="swarm-graph"' "$HARNESS_REGISTRY" | wc -l)"
check "replaced row updated" "done=9 blocked=0" "$(awk -F'\t' '$2=="g5"{print $6}' "$HARNESS_REGISTRY")"
exit "$fail"
