#!/usr/bin/env bash
# OpenAI Codex CLI Harness Validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../agent/scripts/harness-check-lib.sh
source "$ROOT/agent/scripts/harness-check-lib.sh"

echo "=== OpenAI Codex CLI Harness Validation ==="
echo

echo "[ Configuration Files ]"
[[ -f "$SCRIPT_DIR/config.toml" ]] && check "config.toml exists" "OK" || check "config.toml" "MISSING"
[[ -f "$SCRIPT_DIR/model-routing.json" ]] && check "model-routing.json exists" "OK" || check "model-routing.json" "MISSING"

python3 -m json.tool "$SCRIPT_DIR/model-routing.json" > /dev/null 2>&1 \
    && check "model-routing.json valid JSON" "OK" \
    || check "model-routing.json valid JSON" "INVALID"

echo
echo "[ Shared SSoT Files ]"
[[ -f "$ROOT/agent/AGENTS.md" ]] && check "agent/AGENTS.md exists" "OK" || check "agent/AGENTS.md" "MISSING"
[[ -f "$ROOT/agent/RTK.md" ]]    && check "agent/RTK.md exists" "OK"    || check "agent/RTK.md" "MISSING"
[[ -f "$ROOT/agent/SWARM.md" ]]  && check "agent/SWARM.md exists" "OK"  || check "agent/SWARM.md" "MISSING"

echo
echo "[ CLI Binaries ]"
for bin in codex rtk jq flock git hx; do
    if command -v "$bin" &>/dev/null; then
        check "binary available: $bin" "OK"
    else
        check "binary available: $bin" "WARN:not found in PATH"
    fi
done

echo
echo "[ Shared Security & Governance Tests ]"
harness_run_shared_test "security-rules.json (shared engine)" "$ROOT/agent/scripts/test-security-rules.sh"
harness_run_shared_test "model-routing.json (shared engine)" "$ROOT/agent/scripts/test-model-routing.sh"

harness_summary "OpenAI Codex"
