# TEST_READY — Automated E2E Verification Suite & Test Readiness

**Date**: 2026-11-05
**Author**: test_writer_1 (teamwork_preview_test_writer)
**Milestone**: M1 (Baseline Benchmark & Invariant Harness)
**Repository**: `kpango/dotfiles`

---

## 1. Test Runner Command

The complete automated test suite can be executed via the master runner or individual Makefile targets:

```bash
# Master Test Runner (Runs Tiers 1-4 + Adversarial Challenger Suite)
/home/kpango/go/src/github.com/kpango/dotfiles/tests/e2e/run_all.sh

# Or via Make targets:
make test/e2e          # All Tiers (1-4)
make test/e2e/tier1    # Tier 1: 5 Strict UX Invariants
make test/e2e/tier2    # Tier 2: 4 Benchmark Performance Thresholds
make test/e2e/tier3    # Tier 3: Guardrails, Syntax & Boundary Integrity
make test/e2e/tier4    # Tier 4: Real-World Scenarios
make test/adversarial  # Adversarial Challenger Attacks
```

---

## 2. Coverage Summary Table (Tiers 1–4 & Adversarial)

| Tier | Category | Test Script / Suite | Tests / Checks | Status | Baseline Result |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tier 1** | Functional & UX Invariants | `tests/e2e/test_ux_invariants.py` | 5 test cases | **PASSED (100%)** | Validated under real PTY session |
| **Tier 2** | Benchmark Performance Thresholds | `tests/e2e/test_benchmarks.sh` | 5 metric assertions | **PASSED (100%)** | All 4 suites within variance limits |
| **Tier 3** | Guardrails & Boundary Integrity | `tests/e2e/test_guardrails.sh` | 9 verification checks | **PASSED (100%)** | `zsh -n`, formatting, 6 boundary files |
| **Adv. (M1)** | Adversarial Challenger Suite (Zsh) | `tests/e2e/test_challenger_m1_adversarial.py` | 5 attack vectors | **PASSED (100%)** | Prompt injection, flow control, leaks |
| **Adv. (M2)** | Adversarial Challenger Suite (Tmux) | `tests/e2e/test_challenger_m2_adversarial.py` | 3 attack vectors | **PASSED (100%)** | Concurrency, race condition, reload burst |

---

## 3. Feature & Invariant Checklist

### Strict UX Invariants (ORIGINAL_REQUEST R2)
- [x] **Invariant 1: Zsh Completion UX** (`test_invariant_1_completion_ux`)
  - `zstyle ':completion:*' menu select` configured and active in interactive ZLE.
  - `bindkey '^[[Z'` maps to `reverse-menu-complete` (Shift+Tab backwards cycling).
  - `zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'` preserves strict common prefix match before fuzzy/case expansion.
  - Interactive PTY test verifies Tab expands exact prefix (`prefix_`) and Shift+Tab reverses selection in completion menu.

- [x] **Invariant 2: Autosuggestions UX** (`test_invariant_2_autosuggestions_ux`)
  - `forward-char` (Right Arrow) and `end-of-line` (End key / Ctrl+E) perform full suggestion acceptance.
  - `forward-word` (Alt+f) performs single-word partial acceptance.
  - `zle-line-pre-redraw` is verified to NOT be defined or wrapped (prevents redisplay overhead).

- [x] **Invariant 3: Terminal Flow Control & Options** (`test_invariant_3_flow_control_options`)
  - Real PTY terminal startup executes synchronous `stty -ixon -ixoff`.
  - Kernel termios inspection confirms `IXON` and `IXOFF` are disabled on the PTY terminal.
  - Zsh option `no_flow_control` is active (`[[ -o no_flow_control ]]`).
  - Active foreground execution verifies receiving Ctrl+S (`\x13`) does not freeze terminal output.

- [x] **Invariant 4: Tmux Status Interval** (`test_invariant_4_tmux_status_interval`)
  - `set -g status-interval 5` verified in `tmux.conf.d/status.conf`.
  - Live isolated tmux daemon verifies `status-interval` option is reported as `5`.

- [x] **Invariant 5: Prompt Visual Match & Delayed Teardown** (`test_invariant_5_prompt_visual_and_stale_fd`)
  - 3-line visual match verified under interactive PTY:
    - Line 1: Clock indicator `🕙 HH:MM:SS`.
    - Line 2: User/host and directory `╭─user@host: in path`, branch with dirty flags (`*+?`), badges (`🐹`), execution duration (`took >= 1.0s`).
    - Line 3: Exit code formatting (`╰─λ ` on exit 0, `╰─✗ <code> ` on non-zero exit).
  - Delayed `_prmt_stale_fd` closing contract verified: fd closed only on subsequent `_prmt_precmd` or via deferred `_prmt_stale_fd_close`, preventing ZLE fd recycling race.

---

### Performance Benchmarks (ORIGINAL_REQUEST R1 & PROJECT.md)
- [x] **Benchmark 1: First Prompt Latency** (`make bench/zsh/first-prompt`)
  - Target: `<= 25.0 ms`
  - Baseline Measured: `24.0 ms ± 0.7 ms` (min: `22.2 ms`, max: `25.7 ms`)
  - Verification: Automated check in `test_benchmarks.sh`.

- [x] **Benchmark 2: Startup Profile CPU** (`make bench/zsh/profile SHARE_ZCOMPDUMP=1`)
  - Target: `<= 17.5 ms CPU`
  - Baseline Measured: `15.87 ms` - `16.08 ms` CPU (`_zsh-defer-apply`)
  - Verification: Automated check in `test_benchmarks.sh`.

- [x] **Benchmark 3: Interactive Startup Wall Time** (`make bench/zsh`)
  - Target: `<= 350.0 ms wall / 50.0 ms net startup`
  - Baseline Measured: `344.3 ms ± 0.8 ms wall` (`44.3 ms` net startup with 300 ms quiet window)
  - Verification: Automated check in `test_benchmarks.sh`.

- [x] **Benchmark 4: Tmux Status Indicator & Microbenchmark**
  - Targets:
    - `tmux-pane-info pane` and `tmux-pane-info right` CLI execution exit 0 with non-empty Powerline segments.
    - `BenchmarkWriteSegment`: `<= 160.0 ns/op, 0 B/op, 0 allocs/op`.
  - Baseline Measured: `148.1 ns/op, 0 B/op, 0 allocs/op`.
  - Verification: Automated check in `test_benchmarks.sh`.

---

### Guardrails & Layout Boundaries (ORIGINAL_REQUEST R3)
- [x] **Guardrail 1: Syntax Validation** (`test_guardrails.sh`)
  - `zsh -n` passes with 0 syntax errors across all `.zsh`, `zshrc`, `zshenv`, and `zfunc/*` files.

- [x] **Guardrail 2: Formatting Idempotency** (`test_guardrails.sh`)
  - `make format/zsh` followed by `git diff --exit-code` produces 0 modifications on tracked zsh files.

- [x] **Guardrail 3: Boundary Files Immutability** (`test_guardrails.sh`)
  - SHA256 checksums verified for protected boundary files:
    - `Makefile.d/install.mk`
    - `agent/harnesses/agy/settings.json`
    - `agent/harnesses/agy/validate-harness.sh`
    - `agent/harnesses/agy/install.sh`
    - `agent/sync-manifest.json`
    - `zsh/20-docker.zsh`
  - 100% preserved unchanged.

---

### Adversarial Challenger Verification (`test_challenger_m1_adversarial.py` & `test_challenger_m2_adversarial.py`)
- [x] **Adv 1 (M1)**: Git branch names containing prompt formatting tokens (`%F{red}%m`) or subshell strings (`$(...)`) do not trigger code injection.
- [x] **Adv 2 (M1)**: Rapid bursts of Ctrl-S / Ctrl-Q during active foreground execution do not hang or deadlock the PTY driver.
- [x] **Adv 3 (M1)**: 40-level deep nested directory traversal safely terminates `_prmt_scan_cwd` within limits.
- [x] **Adv 4 (M1)**: Rapid consecutive prompt/precmd cycles (20+ iterations) do not leak file descriptors.
- [x] **Adv 5 (M1)**: Inputting 600+ character command buffers does not crash or destabilize `zsh-autosuggestions`.
- [x] **Adv 6 (M2 - Concurrency Stress)**: 20 rapid sequential `tmux start-server` and `kill-server` cycles on isolated sockets. Verified zero hangs, zero crashes, zero zombie processes, and clean socket re-binding.
- [x] **Adv 7 (M2 - Race Condition Attack)**: Immediate injection of `prefix + I` and `prefix + U` within 2.5 ms (< 5 ms) of server launch. Verified zero socket panics, zero crashes, immediate responsiveness (ping < 5 ms), and clean deferred registration of TPM keybindings.
- [x] **Adv 8 (M2 - High-Frequency Reload Burst)**: 50 rapid `tmux source-file` commands executed in 431.6 ms (< 1.0 s). Verified zero deadlocks, post-burst ping responsiveness < 4 ms, zero file descriptor leaks (<= 7 open FDs), and 0 zombie subshell processes.

---

## 4. Verification Reproducibility

To independently reproduce the entire test suite on a fresh session:

```bash
cd /home/kpango/go/src/github.com/kpango/dotfiles
./tests/e2e/run_all.sh
```

Expected exit code: `0`.
