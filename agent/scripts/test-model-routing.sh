#!/usr/bin/env bash
# Test harness model routing configs and tier resolution
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$ROOT/agent/scripts/resolve-model-tier.py"

echo "=== Model Routing Validation ==="
echo

# 1. Check all harness configs
"$RESOLVER" --check all

echo
echo "[ Tier Resolution Verification ]"

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

check_tier "claude" "Low" "haiku"
check_tier "claude" "Medium" "opusplan"
check_tier "claude" "High" "claude-sonnet-5"
check_tier "claude" "XHigh" "claude-opus-5"
check_tier "claude" "Max" "claude-fable-5-1"
check_tier "claude" "Inherit" "inherit"

check_tier "agy" "Low" "gemini-3.8-flash-low"
check_tier "agy" "Medium" "gemini-3.8-flash-medium"
check_tier "agy" "High" "gemini-3.8-flash-high"
check_tier "agy" "XHigh" "gemini-3.8-flash-high"
check_tier "agy" "Max" "gemini-3.8-flash-high"

check_tier "codex" "Low" "gpt-5.4-mini"
check_tier "codex" "Medium" "gpt-5.4"
check_tier "codex" "High" "gpt-5.3-codex"
check_tier "codex" "XHigh" "gpt-6-astra"
check_tier "codex" "Max" "gpt-6-astra"

check_tier "pi" "Low" "antigravity/gemini-3.8-flash-low"
check_tier "pi" "Low-Code" "opencode-go/qwen3.8-flash"
check_tier "pi" "Low-Web" "antigravity/gemini-3.8-flash-low"
check_tier "pi" "Medium" "opencode-go/kimi-k3"
check_tier "pi" "High" "anthropic/claude-sonnet-5"
check_tier "pi" "XHigh" "codex/gpt-6-astra"
check_tier "pi" "Max" "anthropic/claude-fable-5-1"

check_tier "primeagent" "Low" "opencode-go/qwen3.8-flash"
check_tier "primeagent" "Medium" "opencode-go/kimi-k3"
check_tier "primeagent" "High" "prime-inference/anthropic/claude-sonnet-5"
check_tier "primeagent" "XHigh" "prime-inference/openai/gpt-6-astra"
check_tier "primeagent" "Max" "prime-inference/anthropic/claude-fable-5.1"

check_fallback() {
    local harness="$1"
    local tier="$2"
    local trigger="$3"
    local expected="$4"

    local actual
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
check_fallback "claude" "High" "token_exhaustion" "claude-sonnet-4-6"
check_fallback "agy" "High" "rate_limit" "claude-sonnet-4-6"
check_fallback "codex" "Medium" "token_exhaustion" "gpt-5.4-mini"
check_fallback "pi" "High" "token_exhaustion" "opencode-go/deepseek-v4-pro"
check_fallback "pi" "XHigh" "rate_limit" "antigravity/gemini-3.8-flash-high"
check_fallback "primeagent" "High" "token_exhaustion" "opencode-go/glm-5.3"

echo
echo "[ PrimeAgent: install.sh derivation vs resolver ]"
# primeagent/install.sh derives subagentDefaultModel / auxiliaryModel / allowedModels from model-routing.json
# with its own jq (CONTEXT C-2). Run it against a throwaway HOME and require every model the resolver can
# return for primeagent (each tier, and each tier's fallback through its trigger) to be allowed there.
prime_home="$(mktemp -d)"
trap 'rm -rf "$prime_home"' EXIT
if ! ROOTDIR="$ROOT" HOME="$prime_home" bash "$ROOT/agent/harnesses/primeagent/install.sh" >"$prime_home/install.log" 2>&1; then
    echo "FAIL: primeagent install.sh into a throwaway HOME: $(tail -n 3 "$prime_home/install.log")" >&2
    exit 1
fi
prime_settings="$prime_home/.prime/agent/settings.json"
prime_routing="$ROOT/agent/harnesses/primeagent/model-routing.json"
prime_allowed() { # <model>: in the installed allowedModels?
    jq -e --arg m "$1" '.allowedModels | index($m) != null' "$prime_settings" >/dev/null
}
for key_tier in subagentDefaultModel:High auxiliaryModel:Low; do
    key="${key_tier%%:*}" tier="${key_tier#*:}"
    expected="$("$RESOLVER" primeagent "$tier" --format model)"
    actual="$(jq -r --arg k "$key" '.[$k]' "$prime_settings")"
    if [ "$actual" = "$expected" ]; then
        echo "PASS: primeagent installed $key = resolver $tier ($actual)"
    else
        echo "FAIL: primeagent installed $key = '$actual', resolver $tier = '$expected'" >&2
        exit 1
    fi
done
for tier in Low Medium High XHigh Max; do
    model="$("$RESOLVER" primeagent "$tier" --format model)"
    prime_allowed "$model" || { echo "FAIL: primeagent tier $tier -> $model is not in the installed allowedModels" >&2; exit 1; }
    echo "PASS: primeagent tier $tier -> $model is allowed"
    while IFS= read -r trigger; do
        [ -n "$trigger" ] || continue
        model="$("$RESOLVER" primeagent "$tier" --trigger "$trigger" --format model)"
        prime_allowed "$model" || { echo "FAIL: primeagent fallback ($tier, $trigger) -> $model is not in the installed allowedModels" >&2; exit 1; }
        echo "PASS: primeagent fallback ($tier, trigger: $trigger) -> $model is allowed"
    done < <(jq -r --arg t "$tier" '[.tiers[$t].fallbacks // [] | .[].trigger] | unique | .[]' "$prime_routing")
done

echo
echo "test-model-routing: 全テストPASS"
exit 0
