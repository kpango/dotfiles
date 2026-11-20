#!/usr/bin/env bash
# Hermes Agent + Oh My Hermes (OMH) Harness Validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../agent/scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

echo "=== Hermes Agent + Oh My Hermes (OMH) Harness Validation ==="
echo

echo "[ Base Configuration Files ]"
if python3 -c 'import yaml, sys; data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); assert isinstance(data, dict)' "$SCRIPT_DIR/config.yaml" 2>/dev/null; then
    check "config.yaml valid YAML" "OK"
else
    check "config.yaml valid YAML" "INVALID"
fi

if python3 -c '
import yaml, sys
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
required = {"model", "terminal", "approvals", "skills", "platform_toolsets", "plugins"}
missing = required - set(data.keys())
assert not missing, f"missing keys: {sorted(missing)}"
omh = data["plugins"]["entries"]["omh"]
assert omh.get("enabled") is True
assert omh["settings"]["omh_home"] == "~/.omh"
' "$SCRIPT_DIR/config.yaml" 2>/dev/null; then
    check "config.yaml schema & omh_home (~/.omh)" "OK"
else
    check "config.yaml schema & omh_home (~/.omh)" "INVALID"
fi

if [[ -f "$SCRIPT_DIR/SOUL.md" ]] && grep -q 'Test · verified' "$SCRIPT_DIR/SOUL.md" \
    && grep -q 'agent/security-rules.json' "$SCRIPT_DIR/SOUL.md" \
    && grep -q 'agent/write-scope-rules.json' "$SCRIPT_DIR/SOUL.md"; then
    check "SOUL.md exists with core invariants" "OK"
else
    check "SOUL.md exists with core invariants" "MISSING or incomplete"
fi

if python3 -m json.tool "$SCRIPT_DIR/omh/category-maestro.json" > /dev/null 2>&1 \
    && python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("schema_version") == "omh_category_maestro/v1"
profs = d.get("profiles", {})
assert "omp" in profs and "claude-code" in profs
for p in ("omp", "claude-code"):
    for cat in ("ultrabrain", "deep", "quick"):
        assert isinstance(profs[p].get(cat), list) and len(profs[p][cat]) >= 1
' "$SCRIPT_DIR/omh/category-maestro.json" 2>/dev/null; then
    check "omh/category-maestro.json valid JSON & schema" "OK"
else
    check "omh/category-maestro.json valid JSON & schema" "INVALID"
fi

if python3 -m json.tool "$SCRIPT_DIR/model-routing.json" > /dev/null 2>&1; then
    check "model-routing.json valid JSON" "OK"
else
    check "model-routing.json valid JSON" "INVALID"
fi

if python3 "$ROOT/agent/scripts/resolve-model-tier.py" --check hermes > /dev/null 2>&1; then
    check "resolve-model-tier.py --check hermes" "OK"
else
    check "resolve-model-tier.py --check hermes" "FAILED"
fi

echo
echo "[ 6 Bot Profiles & OMH Store Isolation ]"
PROFILES=(chief researcher swe perf sec-reviewer ops)
for prof in "${PROFILES[@]}"; do
    pdir="$SCRIPT_DIR/profiles/$prof"
    if python3 -c 'import yaml, sys; data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); assert isinstance(data, dict) and data.get("name") == sys.argv[2]' "$pdir/profile.yaml" "$prof" 2>/dev/null; then
        check "profile[$prof]: profile.yaml valid YAML" "OK"
    else
        check "profile[$prof]: profile.yaml valid YAML" "INVALID"
    fi

    if python3 -c 'import yaml, sys; data = yaml.safe_load(open(sys.argv[1], encoding="utf-8")); assert isinstance(data, dict)' "$pdir/config.yaml" 2>/dev/null; then
        check "profile[$prof]: config.yaml valid YAML" "OK"
    else
        check "profile[$prof]: config.yaml valid YAML" "INVALID"
    fi

    if python3 -c '
import yaml, sys
data = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
expected = f"~/.omh/profiles/{sys.argv[2]}"
omh_home = data["plugins"]["entries"]["omh"]["settings"]["omh_home"]
assert omh_home == expected, f"expected {expected}, got {omh_home}"
' "$pdir/config.yaml" "$prof" 2>/dev/null; then
        check "profile[$prof]: unique omh_home (~/.omh/profiles/$prof)" "OK"
    else
        check "profile[$prof]: unique omh_home (~/.omh/profiles/$prof)" "INVALID"
    fi

    if [[ -f "$pdir/SOUL.md" ]] && grep -q 'Test · verified' "$pdir/SOUL.md" \
        && grep -q 'agent/security-rules.json' "$pdir/SOUL.md" \
        && grep -q 'agent/write-scope-rules.json' "$pdir/SOUL.md"; then
        check "profile[$prof]: SOUL.md exists with core invariants" "OK"
    else
        check "profile[$prof]: SOUL.md exists with core invariants" "MISSING or incomplete"
    fi
done

if python3 -c '
import yaml, sys
root = sys.argv[1]
homes = []
for prof in sys.argv[2:]:
    data = yaml.safe_load(open(f"{root}/profiles/{prof}/config.yaml", encoding="utf-8"))
    homes.append(data["plugins"]["entries"]["omh"]["settings"]["omh_home"])
base = yaml.safe_load(open(f"{root}/config.yaml", encoding="utf-8"))["plugins"]["entries"]["omh"]["settings"]["omh_home"]
assert len(homes) == len(set(homes)) == 6
assert base not in homes
' "$SCRIPT_DIR" "${PROFILES[@]}" 2>/dev/null; then
    check "all 6 profiles have distinct omh_home stores" "OK"
else
    check "all 6 profiles have distinct omh_home stores" "DUPLICATE or collision"
fi

echo
echo "[ Nov 2026 Model Alignment (No Retired Models) ]"
if python3 -c '
import re, sys
from pathlib import Path
root = Path(sys.argv[1])
retired = re.compile(r"(claude-(?:sonnet|opus|haiku)-4-6|claude-3-5-haiku|gemini-3\.[0-9]|gpt-oss-120b)", re.IGNORECASE)
files = [
    root / "config.yaml",
    root / "model-routing.json",
    root / "omh" / "category-maestro.json",
]
for prof in sys.argv[2:]:
    files.append(root / "profiles" / prof / "profile.yaml")
    files.append(root / "profiles" / prof / "config.yaml")
bad = []
for f in files:
    txt = f.read_text(encoding="utf-8")
    m = retired.search(txt)
    if m:
        bad.append(f"{f.name}:{m.group(0)}")
assert not bad, f"retired models found: {bad}"
' "$SCRIPT_DIR" "${PROFILES[@]}" 2>/dev/null; then
    check "zero retired models across Hermes configs & profiles" "OK"
else
    check "zero retired models across Hermes configs & profiles" "RETIRED MODEL FOUND"
fi

echo
echo "[ Systemd User Service Unit (Static INI Check) ]"
SERVICE_FILE="$ROOT/systemd/user/hermes-gateway.service"
if [[ -f "$SERVICE_FILE" ]] && python3 -c '
import configparser, sys
cp = configparser.ConfigParser(interpolation=None)
cp.read(sys.argv[1], encoding="utf-8")
assert cp.has_section("Unit")
assert cp.has_section("Service")
assert cp.has_section("Install")
assert cp.get("Service", "ExecStart") == "%h/.local/bin/hermes gateway run"
assert cp.get("Install", "WantedBy") == "default.target"
' "$SERVICE_FILE" 2>/dev/null; then
    check "systemd/user/hermes-gateway.service valid INI" "OK"
else
    check "systemd/user/hermes-gateway.service valid INI" "MISSING or INVALID"
fi

echo
echo "[ Cron jobs (pre-check gated, 0 tokens when quiet) ]"
CRON_INSTALL="$ROOT/agent/scripts/bot/hermes-cron-install.sh"
if [[ -x "$CRON_INSTALL" ]] && [[ -f "$ROOT/agent/harnesses/hermes/cron/jobs.json" ]] \
    && HERMES_HOME="$(mktemp -u)" bash "$CRON_INSTALL" --dry-run >/dev/null 2>&1; then
    check "cron/jobs.json valid + installer dry-run (make hermes/cron/install registers it)" "OK"
else
    check "cron/jobs.json valid + installer dry-run" "INVALID (see agent/scripts/bot/hermes-cron-install.sh --dry-run)"
fi

echo
echo "[ Style: Zero Trailing Whitespace ]"
if python3 -c '
import sys
from pathlib import Path
root = Path(sys.argv[1])
service = Path(sys.argv[2])
files = [f for f in root.rglob("*") if f.is_file()] + [service]
bad = []
for f in files:
    for idx, line in enumerate(f.read_text(encoding="utf-8").splitlines(), 1):
        if line.endswith((" ", "\t")):
            bad.append(f"{f}:{idx}")
assert not bad, f"trailing whitespace: {bad}"
' "$SCRIPT_DIR" "$SERVICE_FILE" 2>/dev/null; then
    check "zero trailing whitespace in Hermes & systemd files" "OK"
else
    check "zero trailing whitespace in Hermes & systemd files" "TRAILING WHITESPACE FOUND"
fi

echo
echo "[ Optional CLI Binaries ]"
for bin in hermes omh omp claude agy jq python3; do
    if command -v "$bin" &>/dev/null; then
        check "binary available: $bin" "OK"
    else
        check "binary available: $bin" "WARN:not found in PATH"
    fi
done

harness_summary "Hermes Agent + OMH Harness"
