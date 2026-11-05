#!/usr/bin/env bash
# test_guardrails.sh — Guardrail, syntax, and boundary verification checking:
# 1. zsh -n syntax check on all zsh configuration and autoloaded files
# 2. make format/zsh formatting idempotency check
# 3. Boundary files integrity check (Makefile.d/install.mk, agent/harnesses/agy/*, agent/sync-manifest.json, zsh/20-docker.zsh)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${ROOT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

FAILED=0
PASSED=0

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $*"
    PASSED=$((PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $*"
    FAILED=$((FAILED + 1))
}

echo "================================================================="
echo " E2E GUARDRAILS & BOUNDARY VERIFICATION RUNNER"
echo " Working directory: ${ROOT_DIR}"
echo "================================================================="

# -----------------------------------------------------------------------------
# Guardrail 1: zsh -n syntax check on all shell files
# -----------------------------------------------------------------------------
log_info "1/3 Running zsh -n syntax check across all zsh files and autoloaded functions..."
SYNTAX_ERRORS=0

# Check zshrc, zshenv, and all files under zsh/ and zfunc/
while IFS= read -r -d '' file; do
    if ! zsh -n "${file}" 2>&1; then
        log_fail "Syntax error in ${file}"
        SYNTAX_ERRORS=$((SYNTAX_ERRORS + 1))
    fi
done < <(find "${ROOT_DIR}" -type f \( -name "*.zsh" -o -name "zshrc" -o -name "zshenv" -o -path "*/zfunc/*" \) -not -path "*/.git/*" -not -name "*.zwc" -print0)

if [ "${SYNTAX_ERRORS}" -eq 0 ]; then
    log_pass "zsh -n syntax check passed on all files (0 errors)"
else
    log_fail "zsh -n syntax check found ${SYNTAX_ERRORS} invalid file(s)"
fi

# -----------------------------------------------------------------------------
# Guardrail 2: make format/zsh & git diff --exit-code check
# -----------------------------------------------------------------------------
log_info "2/3 Verifying formatting idempotency: make format/zsh..."
make format/zsh

# Check git diff for formatted zsh files (excluding the protected 20-docker.zsh boundary file)
if git diff --exit-code -- '*.zsh' 'zshrc' 'zshenv' ':(exclude)zsh/20-docker.zsh' >/dev/null 2>&1; then
    log_pass "Formatting idempotency: make format/zsh produced no diff on zsh files"
else
    log_fail "make format/zsh produced unexpected formatting changes"
    git diff --stat -- '*.zsh' 'zshrc' 'zshenv' ':(exclude)zsh/20-docker.zsh'
fi

# -----------------------------------------------------------------------------
# Guardrail 3: Boundary files immutability check
# -----------------------------------------------------------------------------
log_info "3/3 Verifying boundary files immutability..."

# Expected SHA256 hashes of boundary files at project start (R3.3 & PROJECT.md layout boundaries)
declare -A BOUNDARY_HASHES=(
    ["Makefile.d/install.mk"]="4eb80ac1aa3aad67bc4eb517dd2fbe39b1fd5c0a52dfe4380a0151822f16202f"
    ["agent/harnesses/agy/settings.json"]="ca68a4743fbb1aefb20fbed063c2bc8273978cda7ddc3a93da3390c3a8e01fb5"
    ["agent/harnesses/agy/validate-harness.sh"]="1c645f4ce258074731f9567f48641d9fac47c710a3ceda6c8fd58b630bb18008"
    ["agent/harnesses/agy/install.sh"]="4e2f9085cc039444366eccbcb71b2161bc3f1bbff971b8c0fe9243350c1c667e"
    ["agent/sync-manifest.json"]="11a53e7533d237fb773e59206ab7f5258e8db02ed0293b5004ed552b6d77fba8"
    ["zsh/20-docker.zsh"]="10906d3da006347822cedd499c30220ae289708777d7005e3a4f44d790c0384b"
)

BOUNDARY_FAILURES=0

for b_file in "${!BOUNDARY_HASHES[@]}"; do
    if [ ! -f "${ROOT_DIR}/${b_file}" ]; then
        log_fail "Boundary file missing: ${b_file}"
        BOUNDARY_FAILURES=$((BOUNDARY_FAILURES + 1))
        continue
    fi

    CURRENT_HASH=$(sha256sum "${ROOT_DIR}/${b_file}" | awk '{print $1}')
    EXPECTED_HASH="${BOUNDARY_HASHES[${b_file}]}"

    if [ "${CURRENT_HASH}" = "${EXPECTED_HASH}" ]; then
        log_pass "Boundary file preserved unchanged: ${b_file}"
    else
        log_fail "Boundary file modified or corrupted: ${b_file} (got ${CURRENT_HASH}, expected ${EXPECTED_HASH})"
        BOUNDARY_FAILURES=$((BOUNDARY_FAILURES + 1))
    fi
done

if [ "${BOUNDARY_FAILURES}" -eq 0 ]; then
    log_pass "Boundary files check passed: 100% of protected files preserved unchanged"
else
    log_fail "Boundary files check failed: ${BOUNDARY_FAILURES} boundary file(s) altered"
fi

echo "================================================================="
echo " GUARDRAILS VERIFICATION SUMMARY: ${PASSED} passed, ${FAILED} failed"
echo "================================================================="

if [ "${FAILED}" -ne 0 ]; then
    exit 1
fi
exit 0
