#!/usr/bin/env python3
"""E2E Test Runner orchestrating Tiers 1-4 for Zsh & Tmux optimization project.

Tiers:
- Tier 1: Functional & UX Invariant Coverage (test_ux_invariants.py)
- Tier 2: Benchmark & Performance Verification (test_benchmarks.sh)
- Tier 3: Guardrails, Syntax & Boundary Integrity (test_guardrails.sh)
- Tier 4: Real-World Scenarios & Multi-Component Integration
"""

import argparse
import fcntl
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "..", ".."))

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BLUE = "\033[0;34m"
BOLD = "\033[1m"
NC = "\033[0m"


def strip_ansi(text: str) -> str:
    ansi_regex = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    return ansi_regex.sub("", text)


class Tier4RealWorldScenarios(unittest.TestCase):
    """Tier 4: End-to-end integration and real-world developer workflows."""

    def test_scenario_4_1_interactive_shell_lifecycle(self):
        """Scenario 4.1: Interactive shell boot, command execution, prompt refresh, and clean exit."""
        master, slave = pty.openpty()
        winsize = struct.pack("HHHH", 24, 120, 0, 0)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        env["TMUX"] = "mock_tier4"
        env["DOTFILES_DIR"] = PROJECT_ROOT

        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.chdir(PROJECT_ROOT)
            os.execvpe("zsh", ["zsh", "-i"], env)
            os._exit(1)

        os.close(slave)
        try:
            # 1. Wait for initial prompt
            time.sleep(0.5)
            out = b""
            while True:
                r, _, _ = select.select([master], [], [], 0.3)
                if not r:
                    break
                out += os.read(master, 2048)
            clean = strip_ansi(out.decode("utf-8", errors="replace"))
            self.assertIn("╭─", clean)
            self.assertIn("╰─λ", clean)

            # 2. Run sequential commands
            os.write(master, b"echo HELLO_TIER4\n")
            time.sleep(0.3)
            os.write(master, b"ls -d tmux.conf.d\n")
            time.sleep(0.3)

            out_cmds = b""
            while True:
                r, _, _ = select.select([master], [], [], 0.3)
                if not r:
                    break
                out_cmds += os.read(master, 2048)
            clean_cmds = strip_ansi(out_cmds.decode("utf-8", errors="replace"))
            self.assertIn("HELLO_TIER4", clean_cmds)
            self.assertIn("tmux.conf.d", clean_cmds)

            # 3. Clean exit with SIGHUP (preserves history invariant)
            os.kill(pid, 1)
        finally:
            try:
                os.kill(pid, 9)
            except OSError:
                pass
            try:
                os.waitpid(pid, 0)
            except OSError:
                pass
            os.close(master)

    def test_scenario_4_2_git_worktree_status_transitions(self):
        """Scenario 4.2: Dynamic git status dirty indicator transitions across directories."""
        tmpdir = tempfile.mkdtemp(prefix="tier4_git_")
        try:
            subprocess.run(["git", "init", "-q", tmpdir], check=True)
            test_file = os.path.join(tmpdir, "file.txt")
            with open(test_file, "w") as f:
                f.write("initial\n")
            subprocess.run(["git", "-C", tmpdir, "add", "file.txt"], check=True)
            subprocess.run(
                ["git", "-C", tmpdir, "commit", "-q", "-m", "initial", "--no-gpg-sign"],
                check=True,
                env=dict(os.environ, GIT_AUTHOR_NAME="T", GIT_AUTHOR_EMAIL="t@e.com", GIT_COMMITTER_NAME="T", GIT_COMMITTER_EMAIL="t@e.com"),
            )

            # Launch zsh in clean git repo
            master, slave = pty.openpty()
            winsize = struct.pack("HHHH", 24, 120, 0, 0)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env["TMUX"] = "mock_tier4"
            env["DOTFILES_DIR"] = PROJECT_ROOT

            pid = os.fork()
            if pid == 0:
                os.close(master)
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
                os.dup2(slave, 0)
                os.dup2(slave, 1)
                os.dup2(slave, 2)
                os.close(slave)
                os.chdir(tmpdir)
                os.execvpe("zsh", ["zsh", "-i"], env)
                os._exit(1)

            os.close(slave)
            time.sleep(0.5)

            # Read clean prompt
            out1 = b""
            while True:
                r, _, _ = select.select([master], [], [], 0.3)
                if not r:
                    break
                out1 += os.read(master, 2048)

            # Add an untracked file to trigger dirty marker '?'
            with open(os.path.join(tmpdir, "untracked.txt"), "w") as f:
                f.write("new\n")

            os.write(master, b"\n")  # press enter to refresh prompt
            time.sleep(0.5)

            out2 = b""
            while True:
                r, _, _ = select.select([master], [], [], 0.3)
                if not r:
                    break
                out2 += os.read(master, 2048)

            os.kill(pid, 9)
            os.waitpid(pid, 0)
            os.close(master)

            clean2 = strip_ansi(out2.decode("utf-8", errors="replace"))
            # Expect dirty indicator '?' to appear in prompt after untracked file added
            self.assertTrue("?" in clean2 or "*" in clean2)
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_scenario_4_3_polyglot_badge_transitions(self):
        """Scenario 4.3: Polyglot language badge display transitions in nested directories."""
        tmpdir = tempfile.mkdtemp(prefix="tier4_poly_")
        go_subdir = os.path.join(tmpdir, "go_project")
        os.makedirs(go_subdir)
        with open(os.path.join(go_subdir, "go.mod"), "w") as f:
            f.write("module testpkg\ngo 1.22\n")

        try:
            # Ensure prmt_versions.zsh is seeded so cold-cache CI environments never fail
            zcache_dir = os.path.expanduser("~/.zcache")
            os.makedirs(zcache_dir, exist_ok=True)
            ver_cache = os.path.join(zcache_dir, "prmt_versions.zsh")
            if not os.path.exists(ver_cache):
                with open(ver_cache, "w") as vf:
                    vf.write("_prmt_cached_go_ver='1.22'\n_prmt_cached_rust_ver=''\n_prmt_cached_node_ver=''\n")

            # Launch interactive zsh in a real PTY
            master, slave = pty.openpty()
            winsize = struct.pack("HHHH", 24, 120, 0, 0)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env["TMUX"] = "mock_tier4"
            env["DOTFILES_DIR"] = PROJECT_ROOT

            pid = os.fork()
            if pid == 0:
                os.close(master)
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
                os.dup2(slave, 0)
                os.dup2(slave, 1)
                os.dup2(slave, 2)
                os.close(slave)
                os.chdir(tmpdir)
                os.execvpe("zsh", ["zsh", "-i"], env)
                os._exit(1)

            os.close(slave)
            try:
                time.sleep(0.5)

                # Navigate into Go project directory
                os.write(master, f"cd {go_subdir}\n".encode("utf-8"))
                time.sleep(0.4)

                out = b""
                while True:
                    r, _, _ = select.select([master], [], [], 0.3)
                    if not r:
                        break
                    out += os.read(master, 2048)

                clean = strip_ansi(out.decode("utf-8", errors="replace"))
                self.assertIn("🐹", clean, "Prompt must show Go badge (🐹) in go.mod dir")
            finally:
                try:
                    os.kill(pid, 9)
                except OSError:
                    pass
                try:
                    os.waitpid(pid, 0)
                except OSError:
                    pass
                os.close(master)
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_scenario_4_4_tmux_status_line_integration(self):
        """Scenario 4.4: Multiplexer and compiled binary status-line integration."""
        bin_pane_info = os.path.join(PROJECT_ROOT, "tmux.conf.d", "tmux-pane-info", "tmux-pane-info")
        if not os.path.isfile(bin_pane_info):
            bin_pane_info = os.path.expanduser("~/.zcache/tmux-pane-info")

        self.assertTrue(os.path.isfile(bin_pane_info), f"Binary not found: {bin_pane_info}")

        # Test pane segment formatting
        proc_pane = subprocess.run(
            [bin_pane_info, "pane", PROJECT_ROOT],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(proc_pane.returncode, 0)
        self.assertIn("dotfiles", proc_pane.stdout)

        # Test right segment formatting
        proc_right = subprocess.run(
            [bin_pane_info, "right"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(proc_right.returncode, 0)
        self.assertIn("CPU:", proc_right.stdout)
        self.assertIn("RAM:", proc_right.stdout)


def run_tier_1():
    print(f"\n{BOLD}{BLUE}================================================================={NC}")
    print(f"{BOLD}{BLUE} RUNNING TIER 1: FUNCTIONAL & UX INVARIANT COVERAGE{NC}")
    print(f"{BOLD}{BLUE}================================================================={NC}\n")
    script = os.path.join(SCRIPT_DIR, "test_ux_invariants.py")
    res = subprocess.run([sys.executable, script], cwd=PROJECT_ROOT)
    return res.returncode == 0


def run_tier_2():
    print(f"\n{BOLD}{BLUE}================================================================={NC}")
    print(f"{BOLD}{BLUE} RUNNING TIER 2: BENCHMARKS & PERFORMANCE THRESHOLDS{NC}")
    print(f"{BOLD}{BLUE}================================================================={NC}\n")
    script = os.path.join(SCRIPT_DIR, "test_benchmarks.sh")
    res = subprocess.run(["bash", script], cwd=PROJECT_ROOT)
    return res.returncode == 0


def run_tier_3():
    print(f"\n{BOLD}{BLUE}================================================================={NC}")
    print(f"{BOLD}{BLUE} RUNNING TIER 3: GUARDRAILS, SYNTAX & BOUNDARY INTEGRITY{NC}")
    print(f"{BOLD}{BLUE}================================================================={NC}\n")
    script = os.path.join(SCRIPT_DIR, "test_guardrails.sh")
    res = subprocess.run(["bash", script], cwd=PROJECT_ROOT)
    return res.returncode == 0


def run_tier_4():
    print(f"\n{BOLD}{BLUE}================================================================={NC}")
    print(f"{BOLD}{BLUE} RUNNING TIER 4: REAL-WORLD SCENARIOS & FULL INTEGRATION{NC}")
    print(f"{BOLD}{BLUE}================================================================={NC}\n")
    suite = unittest.TestLoader().loadTestsFromTestCase(Tier4RealWorldScenarios)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return result.wasSuccessful()


def main():
    parser = argparse.ArgumentParser(description="E2E Test Runner")
    parser.add_argument(
        "--tier",
        choices=["1", "2", "3", "4", "all"],
        default="all",
        help="Test tier to execute (1, 2, 3, 4, or all)",
    )
    args = parser.parse_args()

    results = {}

    if args.tier in ("1", "all"):
        results["Tier 1 (UX Invariants)"] = run_tier_1()

    if args.tier in ("2", "all"):
        results["Tier 2 (Benchmarks)"] = run_tier_2()

    if args.tier in ("3", "all"):
        results["Tier 3 (Guardrails)"] = run_tier_3()

    if args.tier in ("4", "all"):
        results["Tier 4 (Real-World Scenarios)"] = run_tier_4()

    print(f"\n{BOLD}================================================================={NC}")
    print(f"{BOLD} E2E TEST SUITE EXECUTION SUMMARY{NC}")
    print(f"{BOLD}================================================================={NC}")

    all_passed = True
    for name, ok in results.items():
        status = f"{GREEN}PASSED{NC}" if ok else f"{RED}FAILED{NC}"
        print(f"  {name:<36}: {status}")
        if not ok:
            all_passed = False

    print(f"{BOLD}================================================================={NC}")

    if all_passed:
        print(f"{GREEN}{BOLD}ALL REQUESTED TIERS COMPLETED SUCCESSFULLY (100% PASS){NC}\n")
        sys.exit(0)
    else:
        print(f"{RED}{BOLD}ONE OR MORE TIERS FAILED{NC}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
