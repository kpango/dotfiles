#!/usr/bin/env bash
# Test harness model routing configs, SSoT catalog sync, and dynamic tier resolution
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$ROOT/agent/scripts/resolve-model-tier.py"
UPDATER="$ROOT/agent/scripts/update-model-catalog.py"
CATALOG="$ROOT/agent/models/catalog.json"

echo "=== Model Routing Validation ==="
echo

# 1. Check all harness configs & SSoT catalog sync
python3 "$UPDATER" --check
"$RESOLVER" --check all

catalog_field() {
    python3 - "$CATALOG" "$@" <<'PY'
import json, sys

cat = json.loads(open(sys.argv[1], encoding="utf-8").read())
mode = sys.argv[2]
harness = sys.argv[3]
tier = sys.argv[4]
tcfg = cat["harnesses"][harness]["tiers"][tier]

if mode == "model":
    print(tcfg["model"])
elif mode == "sub_route":
    sr = sys.argv[5]
    print(tcfg["sub_routes"][sr]["model"])
elif mode == "fallback":
    trig = sys.argv[5]
    matches = [f["model"] for f in tcfg.get("fallbacks", []) if f.get("trigger") == trig]
    print(matches[0] if matches else "")
elif mode == "compaction":
    trig = sys.argv[5] if len(sys.argv) > 5 else ""
    if trig:
        matches = [f for f in tcfg.get("fallbacks", []) if f.get("trigger") == trig]
        print(matches[0].get("compaction_threshold", "") if matches else "")
    else:
        print(tcfg.get("compaction_threshold", ""))
PY
}

echo
echo "[ Tier Resolution Verification (Dynamic vs catalog.json) ]"

check_tier() {
    local harness="$1" tier="$2" expected_model="$3"
    local actual
    actual="$("$RESOLVER" "$harness" "$tier" --format model)"
    if [ "$actual" = "$expected_model" ]; then
        echo "PASS: $harness tier $tier -> $actual"
    else
        echo "FAIL: $harness tier $tier -> expected '$expected_model', got '$actual'" >&2
        exit 1
    fi
}

for harness in claude agy omp hermes; do
    for tier in Low Medium High XHigh Max; do
        expected="$(catalog_field model "$harness" "$tier")"
        if [ -z "$expected" ]; then
            echo "FAIL: catalog.json missing primary model for $harness/$tier" >&2
            exit 1
        fi
        check_tier "$harness" "$tier" "$expected"
    done
    check_tier "$harness" "Inherit" "inherit"
done

for harness in omp hermes; do
    check_tier "$harness" "Low-Code" "$(catalog_field sub_route "$harness" Low code_research)"
    check_tier "$harness" "Low-Web" "$(catalog_field sub_route "$harness" Low web_research)"
done

# Role & legacy aliases on omp
check_tier "omp" "@smol" "$(catalog_field model omp Low)"
check_tier "omp" "@fast" "$(catalog_field model omp Low)"
check_tier "omp" "@good" "$(catalog_field model omp High)"
check_tier "omp" "@review" "$(catalog_field model omp XHigh)"
check_tier "omp" "@slow" "$(catalog_field model omp Max)"
check_tier "omp" "@plan" "$(catalog_field model omp Max)"
check_tier "omp" "haiku" "$(catalog_field model omp Low)"
check_tier "omp" "sonnet" "$(catalog_field model omp High)"
check_tier "omp" "opus" "$(catalog_field model omp XHigh)"
check_tier "omp" "fable" "$(catalog_field model omp Max)"

check_fallback() {
    local harness="$1"
    local tier="$2"
    local trigger="$3"
    local expected actual
    expected="$(catalog_field fallback "$harness" "$tier" "$trigger")"
    actual=$(python3 "$RESOLVER" "$harness" "$tier" --trigger "$trigger" --format model)
    if [ "$actual" = "$expected" ]; then
        echo "PASS: $harness fallback ($tier, trigger: $trigger) -> $actual"
    else
        echo "FAIL: $harness fallback ($tier, trigger: $trigger) -> got '$actual', expected '$expected'" >&2
        exit 1
    fi
}

echo
echo "[ Fallback Resolution Verification ]"
check_fallback "claude" "High" "token_exhaustion"
check_fallback "claude" "Medium" "token_exhaustion"
check_fallback "agy" "Low" "rate_limit"
check_fallback "agy" "High" "rate_limit"
check_fallback "agy" "High" "token_exhaustion"
check_fallback "agy" "XHigh" "rate_limit"
check_fallback "omp" "High" "rate_limit"
check_fallback "omp" "High" "token_exhaustion"
check_fallback "omp" "XHigh" "rate_limit"
check_fallback "hermes" "High" "token_exhaustion"
check_fallback "hermes" "Max" "unavailability"

echo
echo "[ Pricing Cliff Compaction Limits Verification ]"
check_compaction() {
    local harness="$1" tier="$2" trigger="$3" expected_limit actual
    expected_limit="$(catalog_field compaction "$harness" "$tier" "$trigger")"
    if [ -n "$trigger" ]; then
        actual=$(python3 -c '
import json, subprocess, sys
out = subprocess.check_output([sys.argv[1], sys.argv[2], sys.argv[3], "--trigger", sys.argv[4], "--format", "json"], text=True)
print(json.loads(out).get("compaction_threshold", ""))
' "$RESOLVER" "$harness" "$tier" "$trigger")
    else
        actual=$(python3 -c '
import json, subprocess, sys
out = subprocess.check_output([sys.argv[1], sys.argv[2], sys.argv[3], "--format", "json"], text=True)
print(json.loads(out).get("compaction_threshold", ""))
' "$RESOLVER" "$harness" "$tier")
    fi
    if [ "$actual" = "$expected_limit" ]; then
        echo "PASS: $harness $tier${trigger:+ ($trigger)} compaction_threshold -> $actual"
    else
        echo "FAIL: $harness $tier${trigger:+ ($trigger)} compaction_threshold -> got '$actual', expected '$expected_limit'" >&2
        exit 1
    fi
}

check_compaction "agy" "Low" "rate_limit"
check_compaction "agy" "High" "token_exhaustion"
check_compaction "agy" "XHigh" "rate_limit"
check_compaction "omp" "XHigh" ""
check_compaction "claude" "Low" ""
check_compaction "hermes" "XHigh" ""

echo
echo "test-model-routing: 全テストPASS"
exit 0
