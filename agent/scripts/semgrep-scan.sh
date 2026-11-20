#!/usr/bin/env bash
# semgrep-scan.sh — run semgrep on the given paths and print a compact, line-oriented summary.
#
# usage: semgrep-scan.sh [--config <cfg>] <path>...
#   --config  semgrep ruleset (default: $SEMGREP_CONFIG, else p/security-audit; registry rulesets need network,
#             pass a local rules file/dir for offline use)
#
# exit: 0 no findings | 1 findings | 2 usage or semgrep error | 3 semgrep not installed (UNAVAILABLE)
# Exit 3 is deliberate: a missing scanner must never read as "scanned, clean".
# SEMGREP_BIN overrides the binary (tests use a fake).
set -euo pipefail

cfg="${SEMGREP_CONFIG:-p/security-audit}"
if [ "${1:-}" = "--config" ]; then
    [ $# -ge 3 ] || { echo "usage: semgrep-scan.sh [--config <cfg>] <path>..." >&2; exit 2; }
    cfg="$2"
    shift 2
fi
[ $# -ge 1 ] || { echo "usage: semgrep-scan.sh [--config <cfg>] <path>..." >&2; exit 2; }

bin="${SEMGREP_BIN:-semgrep}"
if ! command -v "$bin" >/dev/null 2>&1; then
    echo "UNAVAILABLE: semgrep not found ($bin); this is NOT a clean result" >&2
    exit 3
fi

out="$(mktemp)"
trap 'rm -f "$out"' EXIT
# semgrep exits 0 (clean) or 1 (findings, only with --error); anything else is a scan failure.
if ! "$bin" scan --config "$cfg" --metrics=off --disable-version-check --quiet --json --output "$out" -- "$@" >/dev/null 2>"$out.err"; then
    echo "semgrep failed:" >&2
    head -c 2000 "$out.err" >&2 || true
    rm -f "$out.err"
    exit 2
fi
rm -f "$out.err"

python3 -I -B - "$out" <<'PYEOF'
import json, sys

try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError) as e:
    print(f"semgrep produced unreadable output: {e}", file=sys.stderr)
    sys.exit(2)
errors = data.get("errors") or []
results = data.get("results") or []
for r in results:
    sev = (r.get("extra") or {}).get("severity", "?")
    msg = ((r.get("extra") or {}).get("message") or "").splitlines()
    start = (r.get("start") or {}).get("line", "?")
    print(f"{sev}\t{r.get('path','?')}:{start}\t{r.get('check_id','?')}\t{msg[0] if msg else ''}")
print(f"semgrep: {len(results)} finding(s), {len(errors)} scan error(s)")
if errors:
    print("scan errors mean some files were NOT analysed", file=sys.stderr)
    sys.exit(2)
sys.exit(1 if results else 0)
PYEOF
