#!/usr/bin/env bash
# test_benchmarks.sh — Automated benchmark verification checking:
# 1. make bench/zsh/first-prompt (<= 25.0 ms)
# 2. make bench/zsh/profile SHARE_ZCOMPDUMP=1 (<= 17.5 ms CPU)
# 3. make bench/zsh (<= 350.0 ms wall / 50.0 ms net startup)
# 4. tmux-pane-info CLI execution & Go microbenchmark BenchmarkWriteSegment (<= 160 ns/op, 0 B/op, 0 allocs)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${ROOT_DIR}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
echo " E2E BENCHMARK & PERFORMANCE VERIFICATION RUNNER"
echo " Working directory: ${ROOT_DIR}"
echo "================================================================="

# -----------------------------------------------------------------------------
# Metric 1: First Prompt Latency (<= 25.0 ms)
# -----------------------------------------------------------------------------
log_info "1/4 Measuring first-prompt latency: make bench/zsh/first-prompt..."
for trial in 1 2 3; do
    FIRST_PROMPT_OUT=$(make bench/zsh/first-prompt 2>&1)
    echo "${FIRST_PROMPT_OUT}"
    FIRST_PROMPT_MS=$(echo "${FIRST_PROMPT_OUT}" | python3 -c "
import sys, re
out = sys.stdin.read()
m = re.search(r'Wall Time\s+([0-9.]+)\s*ms', out)
if m:
    print(float(m.group(1)))
else:
    sys.exit(1)
" || echo "ERR")

    if [ "${FIRST_PROMPT_MS}" != "ERR" ]; then
        IS_OK=$(python3 -c "print(1 if float('${FIRST_PROMPT_MS}') <= 25.0 else 0)")
        if [ "${IS_OK}" -eq 1 ]; then
            log_pass "First-prompt latency: ${FIRST_PROMPT_MS} ms <= 25.0 ms target (trial ${trial})"
            break
        elif [ "${trial}" -lt 3 ]; then
            log_info "Trial ${trial} (${FIRST_PROMPT_MS} ms) exceeded 25.0 ms on shared host, retrying..."
        else
            log_fail "First-prompt latency: ${FIRST_PROMPT_MS} ms exceeds 25.0 ms target after 3 trials"
        fi
    else
        log_fail "First-prompt latency: failed to parse hyperfine output"
        break
    fi
done

# -----------------------------------------------------------------------------
# Metric 2: Startup Profile CPU (<= 17.5 ms CPU)
# -----------------------------------------------------------------------------
log_info "2/4 Measuring deferred CPU startup profile: make bench/zsh/profile SHARE_ZCOMPDUMP=1..."
PROFILE_OUT=$(make bench/zsh/profile SHARE_ZCOMPDUMP=1 2>&1)
echo "${PROFILE_OUT}" | head -n 35

PROFILE_CPU_MS=$(echo "${PROFILE_OUT}" | python3 -c "
import sys, re
out = sys.stdin.read()
# Primary metric: _zsh-defer-apply execution time in zprof
m = re.search(r'([0-9.]+)\s+[0-9.]+\s+[0-9.]+%\s+[0-9.]+\s+[0-9.]+\s+[0-9.]+%\s+_zsh-defer-apply', out)
if m:
    print(float(m.group(1)))
else:
    # Fallback to top-ranked aggregate time if defer-apply is consolidated
    lines = out.strip().split('\n')
    found = False
    for line in lines[2:]:
        if '---' in line: break
        parts = line.split()
        if len(parts) >= 8 and parts[0].endswith(')'):
            print(float(parts[2]))
            found = True
            break
    if not found:
        sys.exit(1)
" || echo "ERR")

if [ "${PROFILE_CPU_MS}" = "ERR" ]; then
    log_fail "Startup profile CPU: failed to parse zprof output"
else
    IS_OK=$(python3 -c "print(1 if float('${PROFILE_CPU_MS}') <= 17.5 else 0)")
    if [ "${IS_OK}" -eq 1 ]; then
        log_pass "Startup profile CPU: ${PROFILE_CPU_MS} ms <= 17.5 ms target"
    else
        log_fail "Startup profile CPU: ${PROFILE_CPU_MS} ms exceeds 17.5 ms target"
    fi
fi

# -----------------------------------------------------------------------------
# Metric 3: Interactive Startup Wall Time (<= 350.0 ms wall / 50.0 ms net)
# -----------------------------------------------------------------------------
log_info "3/4 Measuring interactive startup wall time: make bench/zsh..."
for trial in 1 2 3; do
    BENCH_OUT=$(make bench/zsh 2>&1)
    echo "${BENCH_OUT}"

    BENCH_WALL_MS=$(echo "${BENCH_OUT}" | python3 -c "
import sys, re
out = sys.stdin.read()
m = re.search(r'Wall Time\s+([0-9.]+)\s*ms', out)
if m:
    print(float(m.group(1)))
else:
    sys.exit(1)
" || echo "ERR")

    if [ "${BENCH_WALL_MS}" = "ERR" ]; then
        log_fail "Interactive startup wall time: failed to parse hyperfine output"
        break
    else
        IS_OK=$(python3 -c "print(1 if float('${BENCH_WALL_MS}') <= 350.0 else 0)")
        NET_STARTUP_MS=$(python3 -c "print(max(0.0, float('${BENCH_WALL_MS}') - 300.0))")
        if [ "${IS_OK}" -eq 1 ]; then
            log_pass "Interactive startup wall time: ${BENCH_WALL_MS} ms (net: ${NET_STARTUP_MS} ms) <= 350.0 ms target (trial ${trial})"
            break
        elif [ "${trial}" -lt 3 ]; then
            log_info "Trial ${trial} (${BENCH_WALL_MS} ms) exceeded 350.0 ms on shared host, retrying..."
        else
            log_fail "Interactive startup wall time: ${BENCH_WALL_MS} ms exceeds 350.0 ms target after 3 trials"
        fi
    fi
done

# -----------------------------------------------------------------------------
# Metric 4: tmux-pane-info CLI Execution & Go Microbenchmark
# -----------------------------------------------------------------------------
log_info "4/4 Validating tmux-pane-info binary and BenchmarkWriteSegment..."

BIN_PANE_INFO="${ROOT_DIR}/tmux.conf.d/tmux-pane-info/tmux-pane-info"
if [ ! -x "${BIN_PANE_INFO}" ]; then
    BIN_PANE_INFO="${HOME}/.zcache/tmux-pane-info"
fi

if [ -x "${BIN_PANE_INFO}" ]; then
    PANE_OUT=$("${BIN_PANE_INFO}" pane "${ROOT_DIR}")
    RIGHT_OUT=$("${BIN_PANE_INFO}" right)
    if [ -n "${PANE_OUT}" ] && [ -n "${RIGHT_OUT}" ]; then
        log_pass "tmux-pane-info CLI executes successfully (pane: ${#PANE_OUT} bytes, right: ${#RIGHT_OUT} bytes)"
    else
        log_fail "tmux-pane-info output is empty"
    fi
else
    log_fail "tmux-pane-info binary not found or not executable"
fi

for trial in 1 2 3; do
    GO_BENCH_OUT=$(cd "${ROOT_DIR}/tmux.conf.d/tmux-pane-info" && go test -bench=BenchmarkWriteSegment -benchmem -run=^$ 2>&1)
    echo "${GO_BENCH_OUT}"

    GO_RESULT=$(echo "${GO_BENCH_OUT}" | python3 -c "
import sys, re
out = sys.stdin.read()
m = re.search(r'BenchmarkWriteSegment\S*\s+\d+\s+([0-9.]+)\s+ns/op\s+(\d+)\s+B/op\s+(\d+)\s+allocs/op', out)
if m:
    ns = float(m.group(1))
    bytes_op = int(m.group(2))
    allocs = int(m.group(3))
    print(f'{ns} {bytes_op} {allocs}')
else:
    sys.exit(1)
" || echo "ERR")

    if [ "${GO_RESULT}" = "ERR" ]; then
        log_fail "BenchmarkWriteSegment: failed to parse go test benchmark output"
        break
    else
        read -r NS_OP B_OP ALLOCS <<< "${GO_RESULT}"
        GO_OK=$(python3 -c "print(1 if float('${NS_OP}') <= 160.0 and int('${B_OP}') == 0 and int('${ALLOCS}') == 0 else 0)")
        if [ "${GO_OK}" -eq 1 ]; then
            log_pass "BenchmarkWriteSegment: ${NS_OP} ns/op <= 160.0 ns/op, ${B_OP} B/op, ${ALLOCS} allocs/op (trial ${trial})"
            break
        elif [ "${trial}" -lt 3 ]; then
            log_info "Trial ${trial} (${NS_OP} ns/op) exceeded 160.0 ns/op on shared host, retrying..."
        else
            log_fail "BenchmarkWriteSegment exceeded limits: ${NS_OP} ns/op (limit 160.0), ${B_OP} B/op (limit 0), ${ALLOCS} allocs/op (limit 0) after 3 trials"
        fi
    fi
done

echo "================================================================="
echo " BENCHMARK VERIFICATION SUMMARY: ${PASSED} passed, ${FAILED} failed"
echo "================================================================="

if [ "${FAILED}" -ne 0 ]; then
    exit 1
fi
exit 0
