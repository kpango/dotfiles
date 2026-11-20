#!/usr/bin/env bash
# _swarm-common の回帰テスト: load.sh の once/force/TTL と、CORE.md の節インデックスが SWARM.md と一致すること。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
swarm_md="$(cd "$here/../.." && pwd -P)/SWARM.md"
fail=0
ok() { echo "PASS $1"; }
ng() { echo "FAIL $1"; fail=1; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else ng "$1: expected=[$2] actual=[$3]"; fi; }

export XDG_RUNTIME_DIR; XDG_RUNTIME_DIR="$(mktemp -d)"; trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
export SWARM_SESSION_KEY="t-$$"

for n in core handoff memory skill-state; do
  [ "$("$here/load.sh" "$n" | wc -c)" -gt 200 ] && ok "load $n" || ng "load $n"
done
if "$here/load.sh" nope >/dev/null 2>&1; then ng "reject unknown doc"; else ok "reject unknown doc"; fi

full="$("$here/load.sh" core --once | wc -c)"
stub="$("$here/load.sh" core --once | wc -c)"
[ "$full" -gt 1000 ] && ok "first --once prints body" || ng "first --once prints body ($full)"
[ "$stub" -lt 300 ] && ok "second --once prints stub ($stub bytes)" || ng "second --once prints stub ($stub)"
check "--force prints body" "$full" "$("$here/load.sh" core --once --force | wc -c)"
check "no --once always prints body" "$full" "$("$here/load.sh" core | wc -c)"
check "ttl expiry reprints body" "$full" "$(SWARM_COMMON_TTL_MIN=-1 "$here/load.sh" core --once | wc -c)"
SWARM_SESSION_KEY="other-$$" "$here/load.sh" handoff --once >/dev/null
[ "$(SWARM_SESSION_KEY="third-$$" "$here/load.sh" handoff --once | wc -c)" -gt 300 ] && ok "per-session key" || ng "per-session key"

# CORE.md の節インデックス: 行 a が「## N.」開始、行 b の次が次の「## 」または EOF
total="$(wc -l <"$swarm_md")"
while IFS='|' read -r _ sec _ range _; do
  sec="$(echo "$sec" | tr -d ' ')"; range="$(echo "$range" | tr -d ' ')"
  [[ "$sec" =~ ^§([0-9]+)$ ]] || continue
  n="${BASH_REMATCH[1]}"
  [[ "$range" =~ ^([0-9]+)-([0-9]+)$ ]] || continue
  a="${BASH_REMATCH[1]}"; b="${BASH_REMATCH[2]}"
  line_a="$(sed -n "${a}p" "$swarm_md")"
  [[ "$line_a" == "## $n."* ]] && ok "index §$n start line $a" || ng "index §$n start line $a is [$line_a]"
  if [ "$b" -ge "$total" ]; then ok "index §$n end=EOF"; else
    nxt="$(sed -n "$((b+1))p" "$swarm_md")"
    [[ "$nxt" == "## "* ]] && ok "index §$n end line $b" || ng "index §$n end line $b next=[$nxt]"
  fi
done <"$here/CORE.md"
exit "$fail"
