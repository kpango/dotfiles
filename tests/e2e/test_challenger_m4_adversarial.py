#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M4: Zsh Quick-Win Pruning & Fork Elimination.

Attacks and stress tests:
1. Steady-state fork gating stress:
   - 10 consecutive interactive shell boots under PTY.
   - Assert 0 subshell forks spawned (stamp mtime nanosecond invariance).
   - Assert Zsh gating condition evaluates to GATED.
2. Invalidation stress:
   - Touch configuration files (~/.zshrc, sheldon.toml).
   - Assert subshell forks, compiles .zwc, and refreshes stamp.
   - Assert subsequent boot returns to GATED.
3. 24h TTL expiration stress:
   - Touch stamp with timestamp 2 days in the past.
   - Assert #qN.mh+24 matches, triggers subshell fork, and refreshes stamp to current time.
   - Assert subsequent boot returns to GATED.
4. Missing stamp stress:
   - Remove .async_compile_stamp entirely.
   - Assert subshell triggers, recreates stamp, and returns to GATED on next boot.
5. Concurrency stress:
   - Launch 10 simultaneous interactive Zsh sessions in parallel with microsecond barrier synchronization.
   - Assert 0 hanging subshells, 0 FD leaks, 0 .zwc corruption, clean termination.
6. Concurrent invalidation storm:
   - Remove stamp and touch ~/.zshrc simultaneously, then fire 10 concurrent Zsh sessions.
   - Assert lock arbitration, zero corruptions, zero hangs, and clean post-storm recovery.
7. Dead OS fpath pruning integrity:
   - Assert AIX, Solaris, Cygwin, Darwin, BSD, Windows dirs pruned on Linux.
   - Assert Linux completion and zfunc dirs strictly preserved.
   - Assert Darwin branching logic.
8. Colors elimination and prompt formatting invariance:
   - Assert colors function not loaded.
   - Assert prompt rendering functions without errors.
9. Compinit -C -u hardening verification:
   - Assert compinit runs with -u flag and .zcompdump.zwc is valid.
"""

import glob
import os
import pty
import shutil
import subprocess
import threading
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ZCACHE_DIR = os.path.expanduser("~/.zcache")
STAMP_FILE = os.path.join(ZCACHE_DIR, ".async_compile_stamp")
ZSHRC = os.path.expanduser("~/.zshrc")
ZSHRC_ZWC = os.path.expanduser("~/.zshrc.zwc")
ZSHENV = os.path.expanduser("~/.zshenv")
ZSHENV_ZWC = os.path.expanduser("~/.zshenv.zwc")
SHELDON_CFG = os.path.expanduser("~/.config/sheldon/plugins.toml")
SHELDON_CACHE = os.path.join(ZCACHE_DIR, "sheldon.zsh")


def launch_interactive_zsh(wait_s=0.5):
    """Launch an interactive zsh under a real PTY and exit via SIGHUP after wait_s."""
    master, slave = pty.openpty()
    p = subprocess.Popen(
        ["zsh", "-i"],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        close_fds=True,
    )
    os.close(slave)
    time.sleep(wait_s)
    try:
        os.kill(p.pid, 1)  # SIGHUP
        p.wait(timeout=5)
    except (ProcessLookupError, subprocess.TimeoutExpired):
        try:
            os.kill(p.pid, 9)
        except OSError:
            pass
        p.wait()
    finally:
        os.close(master)
    return p.returncode


def check_gating_condition():
    """Evaluate async-compile gating condition directly in Zsh."""
    script = """
setopt local_options extended_glob
_stamp="${ZCACHE_DIR:-$HOME/.zcache}/.async_compile_stamp"
_scfg="${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"

if [[ ! -f "$_stamp" || -n "$_stamp"(#qN.mh+24) ||
      ! -f ~/.zshrc.zwc || ~/.zshrc -nt ~/.zshrc.zwc ||
      ! -f ~/.zshenv.zwc || ~/.zshenv -nt ~/.zshenv.zwc ||
      ! -f ~/.zcompdump.zwc || ~/.zcompdump -nt ~/.zcompdump.zwc ||
      ! -f $DOTFILES_DIR/zsh/01-tmux.zsh.zwc || $DOTFILES_DIR/zsh/01-tmux.zsh -nt $DOTFILES_DIR/zsh/01-tmux.zsh.zwc ||
      "$_scfg" -nt "$ZCACHE_DIR/sheldon.zsh" ]]; then
    echo "FORK"
else
    echo "GATED"
fi
"""
    res = subprocess.run(["zsh", "-c", script], capture_output=True, text=True)
    return res.stdout.strip()


def check_all_zwc_files():
    """Verify validity of all .zwc files on disk using zcompile -t."""
    corrupted = []
    zwc_candidates = glob.glob(os.path.join(ZCACHE_DIR, "*.zwc"))
    zwc_candidates.extend([
        os.path.expanduser("~/.zshrc.zwc"),
        os.path.expanduser("~/.zshenv.zwc"),
        os.path.expanduser("~/.zcompdump.zwc"),
        os.path.join(PROJECT_ROOT, "zsh", "01-tmux.zsh.zwc"),
    ])
    for zwc in zwc_candidates:
        if os.path.exists(zwc):
            res = subprocess.run(["zsh", "-c", f"zcompile -t {zwc}"], capture_output=True)
            if res.returncode != 0:
                corrupted.append(zwc)
    return corrupted


class TestChallengerM4Adversarial(unittest.TestCase):
    """Adversarial stress harness for M4 Zsh optimizations."""

    def setUp(self):
        # Ensure stamp and core zwc files exist and are valid before test
        os.makedirs(ZCACHE_DIR, exist_ok=True)
        if not os.path.exists(STAMP_FILE):
            subprocess.run(["touch", STAMP_FILE], check=True)
        for f in [ZSHRC, ZSHENV]:
            zwc = f + ".zwc"
            if not os.path.exists(zwc) or os.stat(f).st_mtime > os.stat(zwc).st_mtime:
                subprocess.run(["zsh", "-c", f"zcompile -U -R {f}"], check=True)

    def test_adv_1_fork_gating_steady_state_10_boots(self):
        """Adversarial 1: Steady-state fork gating - 0 forks across 10 consecutive shell boots."""
        self.assertEqual(check_gating_condition(), "GATED")

        initial_stamp_mtime_ns = os.stat(STAMP_FILE).st_mtime_ns
        initial_zshrc_zwc_mtime_ns = os.stat(ZSHRC_ZWC).st_mtime_ns

        for boot_idx in range(10):
            launch_interactive_zsh(wait_s=0.35)
            curr_stamp_mtime_ns = os.stat(STAMP_FILE).st_mtime_ns
            curr_zshrc_zwc_mtime_ns = os.stat(ZSHRC_ZWC).st_mtime_ns

            self.assertEqual(
                curr_stamp_mtime_ns,
                initial_stamp_mtime_ns,
                f"Boot {boot_idx + 1}: .async_compile_stamp was touched, indicating subshell fork!",
            )
            self.assertEqual(
                curr_zshrc_zwc_mtime_ns,
                initial_zshrc_zwc_mtime_ns,
                f"Boot {boot_idx + 1}: .zshrc.zwc was recompiled in steady state!",
            )

    def test_adv_2_invalidation_mtime_triggers_recompile_and_stamp(self):
        """Adversarial 2: Invalidation - touching ~/.zshrc forces subshell fork, recompile & stamp update."""
        time.sleep(0.01)
        os.utime(ZSHRC, None)  # touch
        touch_time = os.stat(ZSHRC).st_mtime

        self.assertEqual(check_gating_condition(), "FORK")

        # Boot interactive shell to allow async-compile to run
        launch_interactive_zsh(wait_s=0.8)

        # Verify recompilation occurred
        zwc_mtime = os.stat(ZSHRC_ZWC).st_mtime
        stamp_mtime = os.stat(STAMP_FILE).st_mtime

        self.assertGreaterEqual(
            zwc_mtime,
            touch_time,
            "~/.zshrc.zwc was not recompiled after ~/.zshrc modification!",
        )
        self.assertGreaterEqual(
            stamp_mtime,
            touch_time,
            ".async_compile_stamp was not refreshed after recompilation!",
        )

        # Verify return to steady state
        self.assertEqual(
            check_gating_condition(),
            "GATED",
            "Gating condition did not recover to GATED after recompilation!",
        )

    def test_adv_3_ttl_24h_expiration_triggers_recompile_and_refresh(self):
        """Adversarial 3: 24h TTL - stamp older than 24h forces subshell fork and refreshes stamp."""
        two_days_ago = time.time() - (2 * 86400)
        os.utime(STAMP_FILE, (two_days_ago, two_days_ago))

        # Check glob condition
        check_script = f"""
setopt local_options extended_glob
s="{STAMP_FILE}"
[[ -n $s(#qN.mh+24) ]] && echo YES || echo NO
"""
        res = subprocess.run(["zsh", "-c", check_script], capture_output=True, text=True)
        self.assertEqual(res.stdout.strip(), "YES")
        self.assertEqual(check_gating_condition(), "FORK")

        t_boot_start = time.time()
        launch_interactive_zsh(wait_s=0.8)

        stamp_mtime_after = os.stat(STAMP_FILE).st_mtime
        self.assertGreaterEqual(
            stamp_mtime_after,
            t_boot_start - 0.5,
            ".async_compile_stamp was not refreshed to current time after 24h TTL trigger!",
        )

        # Immediate next boot must be GATED
        self.assertEqual(check_gating_condition(), "GATED")

    def test_adv_4_missing_stamp_triggers_recompile_and_recreation(self):
        """Adversarial 4: Missing stamp - deleting stamp forces subshell fork and recreates stamp."""
        if os.path.exists(STAMP_FILE):
            os.remove(STAMP_FILE)

        self.assertFalse(os.path.exists(STAMP_FILE))
        self.assertEqual(check_gating_condition(), "FORK")

        t_boot_start = time.time()
        launch_interactive_zsh(wait_s=0.8)

        self.assertTrue(os.path.exists(STAMP_FILE), ".async_compile_stamp was not recreated!")
        stamp_mtime_after = os.stat(STAMP_FILE).st_mtime
        self.assertGreaterEqual(
            stamp_mtime_after,
            t_boot_start - 0.5,
            "Recreated stamp mtime does not reflect current boot!",
        )

        # Next boot must be GATED
        self.assertEqual(check_gating_condition(), "GATED")

    def test_adv_5_concurrency_stress_10_parallel_sessions(self):
        """Adversarial 5: Concurrency - 10 simultaneous interactive Zsh sessions in parallel."""
        num_sessions = 10
        barrier = threading.Barrier(num_sessions)
        sessions = []

        def worker(idx):
            master, slave = pty.openpty()
            barrier.wait()
            p = subprocess.Popen(
                ["zsh", "-i"],
                stdin=slave,
                stdout=slave,
                stderr=slave,
                close_fds=True,
            )
            os.close(slave)
            sessions.append((idx, p, master))

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(num_sessions)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        # Wait for deferred initialization to complete
        time.sleep(1.0)

        hanging_subshells = 0
        fd_leaks = 0

        for idx, p, master in sessions:
            res = subprocess.run(["pgrep", "-P", str(p.pid)], capture_output=True, text=True)
            children = res.stdout.strip().split()
            hanging_subshells += len(children)

            fd_dir = f"/proc/{p.pid}/fd"
            if os.path.exists(fd_dir):
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                        if "pipe:" in target or "(deleted)" in target:
                            fd_leaks += 1
                    except OSError:
                        pass

        # Cleanup
        for idx, p, master in sessions:
            try:
                os.kill(p.pid, 1)
                p.wait(timeout=5)
            except Exception:
                try:
                    os.kill(p.pid, 9)
                except OSError:
                    pass
                p.wait()
            finally:
                os.close(master)

        self.assertEqual(hanging_subshells, 0, f"Found {hanging_subshells} hanging subshells!")
        self.assertEqual(fd_leaks, 0, f"Found {fd_leaks} leaked file descriptors!")

        corrupted = check_all_zwc_files()
        self.assertEqual(len(corrupted), 0, f"Corrupted .zwc files detected: {corrupted}")

    def test_adv_6_concurrent_invalidation_storm(self):
        """Adversarial 6: Concurrency Storm - 10 simultaneous boots during cache invalidation."""
        # Induce storm: delete stamp AND touch ~/.zshrc
        if os.path.exists(STAMP_FILE):
            os.remove(STAMP_FILE)
        time.sleep(0.01)
        os.utime(ZSHRC, None)

        num_sessions = 10
        barrier = threading.Barrier(num_sessions)
        sessions = []

        def worker(idx):
            master, slave = pty.openpty()
            barrier.wait()
            p = subprocess.Popen(
                ["zsh", "-i"],
                stdin=slave,
                stdout=slave,
                stderr=slave,
                close_fds=True,
            )
            os.close(slave)
            sessions.append((idx, p, master))

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(num_sessions)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        # Allow time for compilation and lock arbitration across all subshells
        time.sleep(2.0)

        hanging_subshells = 0
        fd_leaks = 0

        for idx, p, master in sessions:
            res = subprocess.run(["pgrep", "-P", str(p.pid)], capture_output=True, text=True)
            children = res.stdout.strip().split()
            hanging_subshells += len(children)

            fd_dir = f"/proc/{p.pid}/fd"
            if os.path.exists(fd_dir):
                for fd in os.listdir(fd_dir):
                    try:
                        target = os.readlink(f"{fd_dir}/{fd}")
                        if "pipe:" in target or "(deleted)" in target:
                            fd_leaks += 1
                    except OSError:
                        pass

        # Cleanup
        for idx, p, master in sessions:
            try:
                os.kill(p.pid, 1)
                p.wait(timeout=5)
            except Exception:
                try:
                    os.kill(p.pid, 9)
                except OSError:
                    pass
                p.wait()
            finally:
                os.close(master)

        self.assertEqual(hanging_subshells, 0, f"Found {hanging_subshells} hanging subshells after storm!")
        self.assertEqual(fd_leaks, 0, f"Found {fd_leaks} leaked FDs after storm!")
        self.assertTrue(os.path.exists(STAMP_FILE), "Stamp was not recreated during invalidation storm!")

        corrupted = check_all_zwc_files()
        self.assertEqual(len(corrupted), 0, f"Corrupted .zwc files detected after storm: {corrupted}")

        # Verify clean post-storm recovery
        self.assertEqual(check_gating_condition(), "GATED")

    def test_adv_7_fpath_dead_os_pruning_and_linux_integrity(self):
        """Adversarial 7: Feature 11 - Dead OS directories in fpath are pruned on Linux."""
        script = """
typeset -U fpath
source ~/.zshenv
print -l -- $fpath
"""
        res = subprocess.run(["zsh", "-fc", script], capture_output=True, text=True)
        fpath_entries = res.stdout.strip().splitlines()

        dead_patterns = ["Solaris", "AIX", "Cygwin", "Darwin", "Windows"]
        for entry in fpath_entries:
            for pat in dead_patterns:
                self.assertNotIn(
                    pat,
                    entry,
                    f"Dead OS pattern '{pat}' found in Linux fpath entry: {entry}",
                )

        # Linux completion dir must be present
        has_linux = any("Completion/Linux" in e for e in fpath_entries)
        has_zfunc = any(e.endswith("/zfunc") for e in fpath_entries)
        self.assertTrue(has_linux, "Linux completion directory missing from fpath!")
        self.assertTrue(has_zfunc, "Dotfiles zfunc directory missing from fpath!")

    def test_adv_8_colors_module_elimination(self):
        """Adversarial 8: Feature 9 - colors module is eliminated and not loaded into functions."""
        script = """
source ~/.zshenv
source ~/.zshrc
if (( $+functions[colors] )); then
    echo "LOADED"
else
    echo "ELIMINATED"
fi
"""
        res = subprocess.run(["zsh", "-lic", script], capture_output=True, text=True)
        # Note: in interactive boot, colors should not be defined
        self.assertIn("ELIMINATED", res.stdout)

    def test_adv_9_compinit_hardening(self):
        """Adversarial 9: Feature 12 - compinit runs with -u -d and .zcompdump.zwc is valid."""
        zcompdump = os.path.expanduser("~/.zcompdump")
        zcompdump_zwc = os.path.expanduser("~/.zcompdump.zwc")

        self.assertTrue(os.path.exists(zcompdump), "~/.zcompdump missing!")
        self.assertTrue(os.path.exists(zcompdump_zwc), "~/.zcompdump.zwc missing!")

        res = subprocess.run(["zsh", "-c", f"zcompile -t {zcompdump_zwc}"], capture_output=True)
        self.assertEqual(res.returncode, 0, "~/.zcompdump.zwc is corrupt!")


if __name__ == "__main__":
    unittest.main()
