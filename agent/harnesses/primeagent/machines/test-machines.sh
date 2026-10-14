#!/usr/bin/env bash
# Validate every MACHINE.md next to this script: spec parses, model selectors
# exist in model-routing.json, and a sandboxed `prime-agent factory import`
# accepts it. Never touches the real ~/.prime/agent.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
routing="$here/../model-routing.json"
sandbox="$(mktemp -d)"
trap 'command rm -r -- "$sandbox"' EXIT

export HOME="$sandbox"
export PRIME_AGENT_CODING_AGENT_DIR="$sandbox/agent"
export PRIME_AGENT_DAEMON_SOCKET="$sandbox/d.sock"
mkdir -p "$PRIME_AGENT_CODING_AGENT_DIR"

fail=0
for machine in "$here"/*/MACHINE.md; do
	name="$(basename "$(dirname "$machine")")"
	if ! python3 -I - "$machine" "$routing" <<'PY'
import json, re, sys

text = open(sys.argv[1], encoding="utf-8").read()
blocks = re.findall(r"^```machine-spec\n(.*?)^```", text, re.S | re.M)
if len(blocks) != 1:
    sys.exit(f"expected exactly one machine-spec block, found {len(blocks)}")
spec = json.loads(blocks[0])
tiers = json.load(open(sys.argv[2], encoding="utf-8"))["tiers"]
allowed = set()
for tier in tiers.values():
    allowed.add(tier["model"])
    allowed.update(fb["model"] for fb in tier.get("fallbacks", []))
bad = [
    f"{s['id']}: {s['subagent'].get('model')!r}"
    for s in spec["states"]
    if not isinstance(s["subagent"], dict) or s["subagent"].get("model") not in allowed
]
if bad:
    sys.exit("model selector not in model-routing.json: " + ", ".join(bad))
PY
	then
		echo "FAIL spec/model check: $name" >&2
		fail=1
		continue
	fi
	if timeout 300 prime-agent factory import "$machine" >"$sandbox/out" 2>&1 && grep -q '^Imported ' "$sandbox/out"; then
		echo "ok   $name"
	else
		echo "FAIL factory import: $name" >&2
		tail -n 5 "$sandbox/out" >&2
		fail=1
	fi
done
exit "$fail"
