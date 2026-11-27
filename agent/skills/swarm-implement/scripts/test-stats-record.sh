#!/usr/bin/env bash
# stats-record.sh の回帰テスト (一時ディレクトリ上で実行。実 SKILL.stats.json は変更しない)。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
src_root="$(cd "$here/../.." && pwd -P)"
t="$(mktemp -d)"; trap 'rm -rf "$t"' EXIT
mkdir -p "$t/skills/swarm-implement/scripts" "$t/skills/swarm-explore"
cp "$here/stats-record.sh" "$t/skills/swarm-implement/scripts/"
cp "$src_root/swarm-explore/SKILL.stats.json" "$t/skills/swarm-explore/"
s="$t/skills/swarm-implement/scripts/stats-record.sh"; f="$t/skills/swarm-explore/SKILL.stats.json"
fail=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected=$2 actual=$3"; fail=1; fi
}
rejects() { if "$s" "$@" >/dev/null 2>&1; then echo "FAIL reject $*"; fail=1; else echo "PASS reject $*"; fi; }

"$s" swarm-explore ok 100 "" swarm-loop >/dev/null
"$s" swarm-explore fail 300 shard_timeout swarm-loop >/dev/null
"$s" swarm-explore fail 50 shard_timeout human >/dev/null
check exec_count 3 "$(jq .metrics.execution_count "$f")"
check success 1 "$(jq .metrics.success_count "$f")"
check failure 2 "$(jq .metrics.failure_count "$f")"
check min 50 "$(jq .metrics.min_duration_ms "$f")"
check max 300 "$(jq .metrics.max_duration_ms "$f")"
check called_by_loop 2 "$(jq '.metrics.called_by["swarm-loop"]' "$f")"
check sig_count 2 "$(jq '.failure_signatures[0].count' "$f")"
check valid_json true "$(jq -e . "$f" >/dev/null && echo true)"
rejects swarm-x_y ok
rejects swarm-explore bad
rejects swarm-explore ok 1 "a b"
rejects swarm-explore ok abc
rejects ../etc ok
rejects swarm-explore ok 1 "" notaskill
exit "$fail"
