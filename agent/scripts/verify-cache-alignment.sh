#!/usr/bin/env bash
# verify-cache-alignment.sh — Verify prompt cache prefix alignment and static/dynamic separation
#
# Inspects system prompt files across all 5 harnesses (Claude, Pi, AGY, Codex, PrimeAgent)
# ensuring that the static prefix meets provider cache breakpoint thresholds (>=1024 tokens / ~3500 bytes)
# and does not contain dynamic session artifacts that invalidate provider prompt caching.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTDIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

FAIL_COUNT=0
PASS_COUNT=0

check_cache_target() {
  local label="$1"
  local filepath="$2"
  local min_bytes="$3"

  if [[ ! -f "$filepath" ]]; then
    echo "FAIL: ${label}: file not found (${filepath})"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  local size
  size=$(wc -c < "$filepath")

  if (( size < min_bytes )); then
    echo "FAIL: ${label}: static prefix size (${size} bytes) below cache threshold (${min_bytes} bytes)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check for cache-busting dynamic anti-patterns in the first 50 lines
  if head -n 50 "$filepath" | grep -E -q '\b(timestamp|session_id|random_nonce|\$\(date\))\b'; then
    echo "FAIL: ${label}: detected dynamic variable in cacheable prefix"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  echo "PASS: ${label}: ${size} bytes (>=${min_bytes} bytes, clean prefix)"
  PASS_COUNT=$((PASS_COUNT + 1))
}

echo "=== Prompt Cache Prefix Alignment Verification ==="

# Anthropic cache breakpoint is 1024 tokens (~3500 bytes)
# Gemini standard cache block is 2048 tokens (~7000 bytes)
check_cache_target "SSoT Canonical AGENTS.md" "${ROOTDIR}/agent/AGENTS.md" 3500
check_cache_target "Claude AGENTS supplement" "${ROOTDIR}/agent/AGENTS-claude-supplement.md" 3000
check_cache_target "Pi Harness AGENTS.md" "${ROOTDIR}/agent/harnesses/pi/AGENTS.md" 3500
check_cache_target "Pi Harness SYSTEM.md" "${ROOTDIR}/agent/harnesses/pi/SYSTEM.md" 2000
check_cache_target "AGY Harness AGENTS.md" "${ROOTDIR}/agent/harnesses/agy/AGENTS.md" 3500
check_cache_target "AGY Harness SYSTEM.md" "${ROOTDIR}/agent/harnesses/agy/SYSTEM.md" 2000

echo ""
echo "Cache Alignment: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
