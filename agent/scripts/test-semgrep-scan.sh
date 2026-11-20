#!/usr/bin/env bash
# Tests semgrep-scan.sh with a fake semgrep (the real one is not required, and nothing here touches the network).
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAN="$ROOT/agent/scripts/semgrep-scan.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0

check() { # name expected_rc actual_rc
    if [ "$2" = "$3" ]; then echo "PASS: $1 (rc=$3)"; else echo "FAIL: $1 (want rc=$2, got $3)"; fails=$((fails + 1)); fi
}

# fake semgrep: writes $FAKE_JSON to the --output file; FAKE_RC is its exit code. Records argv in $T/argv.
cat >"$T/semgrep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$FAKE_ARGV"
out=""
while [ $# -gt 0 ]; do [ "$1" = "--output" ] && out="$2"; shift; done
[ -n "$out" ] && printf '%s' "${FAKE_JSON:-}" >"$out"
exit "${FAKE_RC:-0}"
EOF
chmod +x "$T/semgrep"
export SEMGREP_BIN="$T/semgrep" FAKE_ARGV="$T/argv"

run() { set +e; "$@" >"$T/stdout" 2>"$T/stderr"; rc=$?; set -e; }

run env SEMGREP_BIN=/nonexistent/semgrep "$SCAN" x.go
check "missing semgrep is UNAVAILABLE, never clean" 3 "$rc"
grep -q UNAVAILABLE "$T/stderr" || { echo "FAIL: UNAVAILABLE message missing"; fails=$((fails + 1)); }

run "$SCAN"
check "no path -> usage" 2 "$rc"

FAKE_JSON='{"results":[],"errors":[]}' run "$SCAN" a.go
check "clean scan" 0 "$rc"

FAKE_JSON='{"results":[{"check_id":"r.sqli","path":"a.go","start":{"line":7},"extra":{"severity":"ERROR","message":"bad\nmore"}}],"errors":[]}' run "$SCAN" a.go
check "finding" 1 "$rc"
grep -q $'ERROR\ta.go:7\tr.sqli\tbad' "$T/stdout" || { echo "FAIL: finding line malformed: $(cat "$T/stdout")"; fails=$((fails + 1)); }

FAKE_JSON='{"results":[],"errors":[{"message":"parse error"}]}' run "$SCAN" a.go
check "scan errors are not clean" 2 "$rc"

FAKE_JSON='not json' run "$SCAN" a.go
check "unreadable output" 2 "$rc"

FAKE_RC=2 FAKE_JSON='{}' run "$SCAN" a.go
check "semgrep failure" 2 "$rc"

FAKE_JSON='{"results":[],"errors":[]}' run "$SCAN" --config ./rules.yml -- -weird
grep -qx -- '--config' "$T/argv" && grep -qx './rules.yml' "$T/argv" && grep -qx -- '--metrics=off' "$T/argv" \
    || { echo "FAIL: argv missing config/metrics-off: $(tr '\n' ' ' <"$T/argv")"; fails=$((fails + 1)); }
grep -qx -- '--' "$T/argv" || { echo "FAIL: paths not separated by --"; fails=$((fails + 1)); }

[ "$fails" -eq 0 ] || { echo "test-semgrep-scan: $fails FAIL"; exit 1; }
echo "test-semgrep-scan: 全テストPASS"
