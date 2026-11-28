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

for harness in claude agy pi hermes; do
    for tier in Low Medium High XHigh Max; do
        expected="$(catalog_field model "$harness" "$tier")"
        if [ -z "$expected" ]; then
            echo "FAIL: catalog.json missing primary model for $harness/$tier" >&2
            exit 1
        fi
        check_tier "$harness" "$tier" "$expected"
    done
    # Inherit with no env/primary falls through to default_tier's resolved model (D12)
    default_tier="$(python3 -I -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["default_tier"])' "$ROOT/agent/harnesses/$harness/model-routing.json")"
    check_tier "$harness" "Inherit" "$(catalog_field model "$harness" "$default_tier")"
done

for harness in pi hermes; do
    check_tier "$harness" "Low-Code" "$(catalog_field sub_route "$harness" Low code_research)"
    check_tier "$harness" "Low-Web" "$(catalog_field sub_route "$harness" Low web_research)"
done

# Role & legacy aliases on pi
check_tier "pi" "@smol" "$(catalog_field model pi Low)"
check_tier "pi" "@fast" "$(catalog_field model pi Low)"
check_tier "pi" "@good" "$(catalog_field model pi High)"
check_tier "pi" "@review" "$(catalog_field model pi XHigh)"
check_tier "pi" "@slow" "$(catalog_field model pi Max)"
check_tier "pi" "@plan" "$(catalog_field model pi Max)"
check_tier "pi" "haiku" "$(catalog_field model pi Low)"
check_tier "pi" "sonnet" "$(catalog_field model pi High)"
check_tier "pi" "opus" "$(catalog_field model pi XHigh)"
check_tier "pi" "fable" "$(catalog_field model pi Max)"

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
check_fallback "pi" "High" "rate_limit"
check_fallback "pi" "High" "token_exhaustion"
check_fallback "pi" "XHigh" "rate_limit"
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
check_compaction "pi" "XHigh" ""
check_compaction "claude" "Low" ""
check_compaction "hermes" "XHigh" ""

echo
echo "[ Inherit Tier Resolution Order / Negative Cases ]"
INH_DEFAULT="$("$RESOLVER" pi Inherit --format model)"
INH_FAIL=0
inh_expect() {
    local desc="$1" expected="$2" actual
    shift 2
    actual="$(env -u PI_PARENT_MODEL -u OMP_PARENT_MODEL -u CLAUDE_PARENT_MODEL -u PARENT_MODEL "$@" "$RESOLVER" pi Inherit --format model)"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: Inherit $desc -> $actual"
    else
        echo "FAIL: Inherit $desc -> expected '$expected', got '$actual'" >&2
        INH_FAIL=1
    fi
}
inh_expect "PI_PARENT_MODEL wins over all" "pi/m1" PI_PARENT_MODEL=pi/m1 OMP_PARENT_MODEL=omp/m0 CLAUDE_PARENT_MODEL=cl/m2 PARENT_MODEL=p/m3
inh_expect "CLAUDE_PARENT_MODEL wins over PARENT_MODEL" "cl/m2" CLAUDE_PARENT_MODEL=cl/m2 PARENT_MODEL=p/m3
inh_expect "PARENT_MODEL alone" "p/m3" PARENT_MODEL=p/m3
inh_expect "empty PI_PARENT_MODEL is skipped" "cl/m2" PI_PARENT_MODEL= CLAUDE_PARENT_MODEL=cl/m2
inh_expect "whitespace-only PI_PARENT_MODEL is skipped" "p/m3" "PI_PARENT_MODEL=   " PARENT_MODEL=p/m3
inh_expect "all unset -> default_tier result" "$INH_DEFAULT"
inh_expect "bracketed model id accepted" "claude-opus-5-5[1m]" "PI_PARENT_MODEL=claude-opus-5-5[1m]"
[ "$INH_FAIL" -eq 0 ] || exit 1

inh_reject() {
    local desc="$1" var="$2" value="$3" rc=0 out
    out="$(env -u PI_PARENT_MODEL -u OMP_PARENT_MODEL -u CLAUDE_PARENT_MODEL -u PARENT_MODEL "$var=$value" "$RESOLVER" pi Inherit --format model 2>&1)" || rc=$?
    if [ "$rc" -ne 0 ] && [ -z "$(printf '%s' "$out" | grep -v '^Error:')" ]; then
        echo "PASS: Inherit rejects $desc (rc=$rc)"
    else
        echo "FAIL: Inherit accepted $desc (rc=$rc out='$out')" >&2
        exit 1
    fi
}
inh_reject "embedded newline" PI_PARENT_MODEL $'a/b\nc'
inh_reject "control char" CLAUDE_PARENT_MODEL $'a/b\x1b[31m'
inh_reject "inner whitespace" PARENT_MODEL "a b"
inh_reject "shell metachar" PI_PARENT_MODEL 'a;id'
inh_reject "leading dash (flag injection)" PI_PARENT_MODEL '-x'
inh_reject "over-long value" PI_PARENT_MODEL "$(printf 'a%.0s' $(seq 1 201))"

echo
echo "[ Schema backward compatibility (Inherit optional) ]"
python3 -I -B - "$ROOT" <<'PYEOF'
import json, sys
root = sys.argv[1]
schema = json.load(open(f"{root}/agent/models/schema.json", encoding="utf-8"))
tiers = schema["properties"]["tiers"]
assert "Inherit" in tiers["properties"], "schema missing tiers.Inherit"
assert "Inherit" not in tiers["required"], "Inherit must stay optional"
inh = schema["definitions"]["InheritTierConfig"]["properties"]
for k in ("inheritFromParent", "preservePromptCachePrefix", "primary", "fallback", "description"):
    assert k in inh, f"InheritTierConfig missing {k}"
for h in ("claude", "agy", "pi", "hermes"):
    cfg = json.load(open(f"{root}/agent/harnesses/{h}/model-routing.json", encoding="utf-8"))
    assert set(tiers["required"]) <= set(cfg["tiers"]), h
    assert set(cfg["tiers"]) <= set(tiers["properties"]), h
PYEOF
echo "PASS: schema keeps 5-tier configs valid and Inherit optional"

echo
echo "[ Quota guard (routingPolicy.openCodeGoQuotaGuard) ]"
QG_HOME="$(mktemp -d)"
trap 'rm -rf "$QG_HOME"' EXIT
qg() { env -u OPENCODE_GO_USAGE_5H_PCT -u OPENCODE_GO_USAGE_WEEK_PCT HOME="$QG_HOME" "$@" python3 "$RESOLVER" --quota-guard pi; }
qg_field() { python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$1"; }
[ "$(qg | qg_field over)" = "None" ] || { echo "FAIL: no usage must be unknown (null), not fine"; exit 1; }
[ "$(qg OPENCODE_GO_USAGE_5H_PCT=1 OPENCODE_GO_USAGE_WEEK_PCT=1 | qg_field over)" = "False" ] || { echo "FAIL: low usage must not be over"; exit 1; }
[ "$(qg OPENCODE_GO_USAGE_5H_PCT=100 | qg_field over)" = "True" ] || { echo "FAIL: 5h at 100% must be over"; exit 1; }
[ "$(qg OPENCODE_GO_USAGE_WEEK_PCT=100 | qg_field over)" = "True" ] || { echo "FAIL: weekly at 100% must be over"; exit 1; }
[ "$(qg OPENCODE_GO_USAGE_5H_PCT=abc OPENCODE_GO_USAGE_WEEK_PCT=999 | qg_field over)" = "None" ] || { echo "FAIL: garbage usage must stay unknown"; exit 1; }
python3 -I -B - "$RESOLVER" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rmt", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
good = {"openCodeGoQuotaGuard": {"enabled": True, "fiveHourMaxPct": 20, "weeklyMaxPct": 50, "highVolumeSubagentDefault": "a/b"}}
assert m.validate_routing_policy(good) == [], m.validate_routing_policy(good)
assert m.validate_routing_policy([]), "non-object must be rejected"
assert m.validate_routing_policy({"x": 1}), "unknown property must be rejected"
bad = {"openCodeGoQuotaGuard": dict(good["openCodeGoQuotaGuard"], fiveHourMaxPct=0)}
assert m.validate_routing_policy(bad), "0% limit must be rejected"
PYEOF
echo "PASS: quota guard decides over/under/unknown and validates the policy"

echo
echo "test-model-routing: 全テストPASS"
exit 0
