#!/usr/bin/env bash
# Regression test for harness-select.sh DOMAIN_AGENTS keyword matching.
# Guards against partial-match regressions (bare "arch" matching "architecture"
# or "search") and confirms Arch Linux environment signals still dispatch
# arch-ops, and architecture/design goals dispatch swarm-architect.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECT="$SCRIPT_DIR/harness-select.sh"

pass=0
fail=0
check() {
  local name="$1" ok="$2" msg="${3:-}"
  if [[ "$ok" == "ok" ]]; then
    echo "ok: $name"
    pass=$((pass + 1))
  else
    echo "FAIL: $name: $msg"
    fail=$((fail + 1))
  fi
}

lenses_for() {
  "$SELECT" "$1" | python3 -c 'import json,sys; print(",".join(json.load(sys.stdin)["recommendation"]["lenses"]))'
}

# arch-ops must NOT fire for generic architecture/goal text (bare "arch"
# substring regression: "architecture", "search", "arch" alone).
l=$(lenses_for "architecture design review of the routing catalog")
check "architecture-only goal does not dispatch arch-ops" \
  "$([[ "$l" != *"arch-ops"* ]] && echo ok || echo no)" "lenses=$l"
l=$(lenses_for "improve vector search performance")
check "search goal does not dispatch arch-ops" \
  "$([[ "$l" != *"arch-ops"* ]] && echo ok || echo no)" "lenses=$l"
l=$(lenses_for "Pi harness consolidation with automatic routing")
check "generic harness goal does not dispatch arch-ops" \
  "$([[ "$l" != *"arch-ops"* ]] && echo ok || echo no)" "lenses=$l"

# Arch Linux environment signals must still dispatch arch-ops.
l=$(lenses_for "Arch Linux pacman systemd sway environment tuning")
check "Arch Linux env goal dispatches arch-ops" \
  "$([[ "$l" == *"arch-ops"* ]] && echo ok || echo no)" "lenses=$l"
l=$(lenses_for "pacman update and systemd unit review")
check "pacman/systemd goal dispatches arch-ops" \
  "$([[ "$l" == *"arch-ops"* ]] && echo ok || echo no)" "lenses=$l"

# Architecture/design goals dispatch swarm-architect.
l=$(lenses_for "Architecture, ADR, design")
check "architecture/design goal dispatches swarm-architect" \
  "$([[ "$l" == *"swarm-architect"* ]] && echo ok || echo no)" "lenses=$l"

echo "harness-select-regression: $pass passed, $fail failed"
[[ $fail -eq 0 ]]