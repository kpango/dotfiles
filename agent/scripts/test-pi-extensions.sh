#!/usr/bin/env bash
# Deterministic gate: run the Pi extension unit test suite (bun test).
#
# Motivation: ~12 `agent/harnesses/pi/extensions/lib/*.test.ts` files import an
# extension entrypoint that depends on pi runtime-only packages (`typebox`,
# `@earendil-works/pi-tui`). Under a bare `bun test` these previously errored at
# module-load and silently never ran, so no deterministic gate covered the
# extension logic. `extensions/bunfig.toml` now registers virtual-module stubs
# (`lib/test-preload.ts`) so every test loads and runs; this script wires the
# whole suite into `validate-harness.sh` as an enforced gate.
#
# IMPORTANT (2026-09-07): the suite must be run **one file at a time**, NOT via a
# bare directory-mode `bun test`. These test files use module-level assertions
# (a `check()` accumulator + `process.exit(1)` on failure) rather than bun's
# `test()` API. Under directory-mode parallel execution bun NONDETERMINISTICALLY
# drops such zero-`test()`-block files from the run (empirically the aggregate
# fluctuated 671<->674 across runs and a deliberately injected failure went
# UNDETECTED, exit 0). Single-file `bun test <file>` reliably executes each file
# and propagates its `process.exit(1)` as a non-zero exit. Iterating every file
# is what makes this gate actually deterministic (39 files / 938 assertions, vs
# the ~25 files / ~671 the directory mode silently covered).
#
# Contract: exit 0 on all-pass OR when bun is unavailable (graceful skip, matching
# the other bun-dependent shared tests); exit 1 on any test failure or a
# module-load error (which would indicate a new runtime-only import escaped the
# preload). Deliberately NOT `set -e` to avoid a cascade abort inside the
# command-substitution used by harness_run_shared_test.
set -uo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"
EXT_DIR="$ROOT/harnesses/pi/extensions"

if ! command -v bun &>/dev/null; then
    echo "[SKIP] bun not found, Pi extension unit tests skipped"
    exit 0
fi

if [[ ! -d "$EXT_DIR" ]]; then
    echo "[FAIL] Pi extensions dir not found: $EXT_DIR"
    exit 1
fi

shopt -s nullglob
test_files=("$EXT_DIR"/lib/*.test.ts)
shopt -u nullglob
if [[ ${#test_files[@]} -eq 0 ]]; then
    echo "[FAIL] No Pi extension test files found under $EXT_DIR/lib"
    exit 1
fi

total_passed=0
nfiles=0
failed_files=()
load_error_files=()

for f in "${test_files[@]}"; do
    nfiles=$((nfiles + 1))
    # Run each file in single-file mode so bun deterministically executes it and
    # propagates its process.exit(1) (see header note).
    out="$(cd "$EXT_DIR" && bun test "$f" 2>&1)"
    status=$?
    rel="${f#"$EXT_DIR"/}"

    # Module-load errors: a runtime-only import escaped lib/test-preload.ts.
    if echo "$out" | grep -qE "Cannot find package|Cannot find module|Export named .* not found"; then
        load_error_files+=("$rel")
        continue
    fi

    # Failure signal: non-zero exit (file called process.exit(1)) OR an explicit
    # "FAIL:" line / "N failed" (N>=1) summary.
    if [[ "$status" -ne 0 ]] || echo "$out" | grep -qE "^FAIL|[1-9][0-9]* failed"; then
        failed_files+=("$rel")
        continue
    fi

    # Sum this file's self-reported "<N> passed" (module summary uses 'passed';
    # bun's own summary uses 'pass', so this matches only the file's count).
    n="$(echo "$out" | grep -oE "[0-9]+ passed" | awk '{s+=$1} END{print s+0}')"
    total_passed=$((total_passed + n))
done

if [[ ${#load_error_files[@]} -gt 0 ]]; then
    echo "[FAIL] Pi extension test module-load error(s) (a runtime-only import likely escaped lib/test-preload.ts):"
    printf '  %s\n' "${load_error_files[@]}"
    exit 1
fi

if [[ ${#failed_files[@]} -gt 0 ]]; then
    echo "[FAIL] Pi extension unit tests failed in ${#failed_files[@]} file(s):"
    printf '  %s\n' "${failed_files[@]}"
    exit 1
fi

echo "[OK] Pi extension unit tests: ${total_passed} assertions passed across ${nfiles} files, 0 failed"
exit 0
