#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M2: Tmux Startup & Options Acceleration.

Attacks tested on isolated sockets (tmux -L bench_stress_...):
1. Concurrency Stress: 20 rapid sequential start-server / kill-server cycles on isolated sockets.
   Verifies zero hangs, crashes, or zombie processes.
2. Race Condition Attack: Immediately inject prefix + I and prefix + U within 5 ms of server launch.
   Verifies graceful execution / registration without socket panic.
3. High-Frequency Reload: Run 50 rapid tmux source-file commands in under 1 second.
   Verifies that server remains responsive, does not deadlock, and does not leak file descriptors.
4. Synchronized Updates Runtime Activation: Attach PTY with xterm-256color and ghostty,
   verifies that 'sync' feature is parsed and registered in #{client_termfeatures},
   and that paired \x1b[?2026h / \x1b[?2026l sequences are emitted during redraws.
"""

import glob
import os
import pty
import select
import shutil
import subprocess
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TMUX_CONF = os.path.expanduser("~/.tmux.conf")


class TestChallengerM2Adversarial(unittest.TestCase):
    """Adversarial stress harness for M2 Tmux optimizations."""

    def setUp(self):
        # Clean any stale bench_stress sockets
        self._cleanup_sockets()

    def tearDown(self):
        self._cleanup_sockets()

    def _cleanup_sockets(self):
        uid = os.getuid()
        for sock_path in glob.glob(f"/tmp/tmux-{uid}/bench_stress_*"):
            try:
                os.remove(sock_path)
            except OSError:
                pass

    def test_adv_1_concurrency_stress_20_cycles(self):
        """Adversarial 1: Concurrency stress - 20 rapid sequential start-server & kill-server cycles."""
        cycles = 20
        cycle_times = []

        # Part A: 20 sequential start-server (exit-empty off) -> kill-server cycles
        for i in range(cycles):
            lbl = f"bench_stress_concur_start_{i}"
            t0 = time.perf_counter()

            # Start server
            start_res = subprocess.run(
                ["tmux", "-L", lbl, "-f", TMUX_CONF, "set", "-s", "exit-empty", "off", ";", "start-server"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(
                start_res.returncode,
                0,
                f"Cycle {i} start-server failed: {start_res.stderr}",
            )

            # Query server to verify responsiveness
            resp = subprocess.run(
                ["tmux", "-L", lbl, "display-message", "-p", "ALIVE_#{version}"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(resp.returncode, 0)
            self.assertTrue(resp.stdout.strip().startswith("ALIVE_"))

            # Kill server
            kill_res = subprocess.run(
                ["tmux", "-L", lbl, "kill-server"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(kill_res.returncode, 0)

            dt = (time.perf_counter() - t0) * 1000
            cycle_times.append(dt)

        # Part B: 20 sequential new-session -d -> kill-server cycles
        session_times = []
        for i in range(cycles):
            lbl = f"bench_stress_concur_sess_{i}"
            t0 = time.perf_counter()

            sess_res = subprocess.run(
                ["tmux", "-L", lbl, "-f", TMUX_CONF, "new-session", "-d", "-s", f"sess_{i}"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(sess_res.returncode, 0)

            # Kill server
            kill_res = subprocess.run(
                ["tmux", "-L", lbl, "kill-server"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(kill_res.returncode, 0)

            dt = (time.perf_counter() - t0) * 1000
            session_times.append(dt)

        # Allow kernel a brief window to reap exited processes
        time.sleep(0.1)

        # Check for lingering tmux server processes on test labels
        ps_out = subprocess.run(
            ["ps", "-eo", "pid,stat,cmd"],
            capture_output=True,
            text=True,
            check=True,
        ).stdout

        lingering = [
            line
            for line in ps_out.splitlines()
            if "bench_stress_concur" in line and "grep" not in line and "python" not in line
        ]
        self.assertEqual(
            len(lingering),
            0,
            f"Detected lingering tmux server processes after kill-server: {lingering}",
        )

        # Check for defunct/zombie processes spawned during tests
        zombies = [
            line
            for line in ps_out.splitlines()
            if "bench_stress" in line and (" Z " in line or line.split()[1].startswith("Z"))
        ]
        self.assertEqual(
            len(zombies),
            0,
            f"Detected zombie processes after rapid cycles: {zombies}",
        )

        avg_start = sum(cycle_times) / len(cycle_times)
        avg_sess = sum(session_times) / len(session_times)
        print(f"\n  [ADV 1] 20 start-server cycles avg: {avg_start:.2f} ms")
        print(f"  [ADV 1] 20 new-session cycles avg:  {avg_sess:.2f} ms")

    def test_adv_2_race_condition_attack_under_5ms(self):
        """Adversarial 2: Race condition attack - inject prefix + I and prefix + U within 5 ms of server launch."""
        iterations = 5

        for i in range(iterations):
            lbl = f"bench_stress_race_{i}"
            master, slave = pty.openpty()
            env = os.environ.copy()
            env["TERM"] = "xterm-256color"

            try:
                t0 = time.perf_counter()
                proc = subprocess.Popen(
                    ["tmux", "-L", lbl, "-f", TMUX_CONF, "new-session", "-s", f"race_{i}"],
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    close_fds=True,
                    env=env,
                )

                # Wait between 1.5 and 3.0 ms (< 5 ms bound)
                time.sleep(0.002)
                t_attack = (time.perf_counter() - t0) * 1000

                # Send prefix + I (both Docker prefix C-w \x17 and standard C-b \x02)
                # followed by prefix + U
                os.write(master, b"\x17I\x02I")
                time.sleep(0.002)
                os.write(master, b"\x17U\x02U")

                # Allow async TPM bootstrap to settle (150ms)
                time.sleep(0.15)

                # Verify server responsiveness: ping must return in < 15 ms without panic
                t_ping0 = time.perf_counter()
                ping = subprocess.run(
                    ["tmux", "-L", lbl, "display-message", "-p", "PONG_#{version}"],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                ping_latency = (time.perf_counter() - t_ping0) * 1000

                self.assertEqual(
                    ping.returncode,
                    0,
                    f"Server crashed or failed to respond after race attack: {ping.stderr}",
                )
                self.assertTrue(ping.stdout.strip().startswith("PONG_"))
                self.assertLess(
                    ping_latency,
                    20.0,
                    f"Ping latency {ping_latency:.2f} ms exceeded 20 ms threshold",
                )

                # Verify TPM key bindings registered cleanly despite race
                keys_out = subprocess.run(
                    ["tmux", "-L", lbl, "list-keys"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout
                self.assertIn("install_plugins", keys_out, "TPM prefix+I binding not registered")
                self.assertIn("update_plugins", keys_out, "TPM prefix+U binding not registered")

            finally:
                subprocess.run(
                    ["tmux", "-L", lbl, "kill-server"],
                    capture_output=True,
                    text=True,
                )
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=2)
                os.close(slave)
                os.close(master)

        print(f"\n  [ADV 2] {iterations} race attacks injected at ~2.5 ms: 100% passed without socket panic")

    def test_adv_3_high_frequency_reload_50_reloads_under_1s(self):
        """Adversarial 3: High-frequency reload - 50 rapid tmux source-file commands in < 1 second."""
        lbl = "bench_stress_m2_reload"

        # Spawn isolated server with session
        sess_res = subprocess.run(
            ["tmux", "-L", lbl, "-f", TMUX_CONF, "new-session", "-d", "-s", "bench_reload"],
            capture_output=True,
            text=True,
            check=True,
        )

        try:
            reloads = 50
            reload_times = []
            t_total_start = time.perf_counter()

            for i in range(reloads):
                t_single = time.perf_counter()
                res = subprocess.run(
                    ["tmux", "-L", lbl, "source-file", TMUX_CONF],
                    capture_output=True,
                    text=True,
                    timeout=5,
                )
                self.assertEqual(
                    res.returncode,
                    0,
                    f"Reload {i} failed: {res.stderr}",
                )
                reload_times.append((time.perf_counter() - t_single) * 1000)

            total_elapsed = time.perf_counter() - t_total_start
            avg_reload = sum(reload_times) / len(reload_times)

            # Strict Assertion: 50 reloads must complete in < 1.0 second
            self.assertLess(
                total_elapsed,
                1.0,
                f"50 reloads took {total_elapsed:.3f} s (exceeded 1.0 s threshold)",
            )

            # Allow background subshells to complete
            time.sleep(0.2)

            # Verify server responsiveness immediately after high-frequency burst
            t_ping0 = time.perf_counter()
            ping = subprocess.run(
                ["tmux", "-L", lbl, "display-message", "-p", "ALIVE_AFTER_50_RELOADS"],
                capture_output=True,
                text=True,
                timeout=5,
            )
            ping_dt = (time.perf_counter() - t_ping0) * 1000

            self.assertEqual(ping.returncode, 0)
            self.assertEqual(ping.stdout.strip(), "ALIVE_AFTER_50_RELOADS")
            self.assertLess(
                ping_dt,
                15.0,
                f"Post-reload ping latency {ping_dt:.2f} ms exceeded 15 ms threshold",
            )

            # Inspect server PID and check resource leakage (file descriptors, child processes)
            pid_str = subprocess.run(
                ["tmux", "-L", lbl, "display-message", "-p", "#{pid}"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            server_pid = int(pid_str)

            # Check open file descriptors in /proc/<pid>/fd
            fd_dir = f"/proc/{server_pid}/fd"
            if os.path.exists(fd_dir):
                fds = os.listdir(fd_dir)
                self.assertLessEqual(
                    len(fds),
                    15,
                    f"Potential file descriptor leak: server has {len(fds)} open FDs",
                )

            # Check active child processes in /proc/<pid>/task/<pid>/children
            children_file = f"/proc/{server_pid}/task/{server_pid}/children"
            if os.path.exists(children_file):
                with open(children_file, "r") as f:
                    children = f.read().split()
                self.assertLessEqual(
                    len(children),
                    2,
                    f"Potential zombie child accumulation: {len(children)} active children",
                )

            # Verify options and invariant preservation
            status_inv = subprocess.run(
                ["tmux", "-L", lbl, "show-options", "-g", "status-interval"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            self.assertEqual(status_inv, "status-interval 5")

            term_feat = subprocess.run(
                ["tmux", "-L", lbl, "show-options", "-g", "terminal-features[0]"],
                capture_output=True,
                text=True,
                check=True,
            ).stdout.strip()
            self.assertIn(":sync", term_feat)

            print(
                f"\n  [ADV 3] 50 reloads completed in {total_elapsed*1000:.2f} ms "
                f"({total_elapsed:.3f} s, avg: {avg_reload:.2f} ms/reload)"
            )
            print(f"  [ADV 3] Post-burst ping latency: {ping_dt:.2f} ms | Open FDs: {len(fds)}")

        finally:
            subprocess.run(
                ["tmux", "-L", lbl, "kill-server"],
                capture_output=True,
                text=True,
            )

    def test_adv_4_synchronized_updates_runtime_feature_activation(self):
        """Adversarial 4: Synchronized updates (DEC mode 2026) runtime activation.

        Guards against parser abortion from unknown feature tokens (e.g. legacy U8).
        Verifies:
        1. When client attaches with TERM=xterm-256color or TERM=ghostty,
           'sync' is actively present in #{client_termfeatures}.
        2. Screen redraws under PTY emit paired \\x1b[?2026h and \\x1b[?2026l escape sequences.
        3. Non-sync terminals (TERM=screen-256color) cleanly omit 'sync' with zero sequence emission.
        """
        for term_type, expect_sync in [("xterm-256color", True), ("ghostty", True), ("screen-256color", False)]:
            lbl = f"bench_stress_sync_{term_type.replace('-', '_')}"
            master, slave = pty.openpty()
            env = os.environ.copy()
            env["TERM"] = term_type

            try:
                proc = subprocess.Popen(
                    ["tmux", "-L", lbl, "-f", TMUX_CONF, "new-session", "-s", f"sess_{term_type.replace('-', '_')}"],
                    stdin=slave,
                    stdout=slave,
                    stderr=slave,
                    close_fds=True,
                    env=env,
                )
                time.sleep(0.5)

                feats_out = subprocess.run(
                    ["tmux", "-L", lbl, "display-message", "-p", "#{client_termfeatures}"],
                    capture_output=True,
                    text=True,
                    check=True,
                ).stdout.strip()
                feats = feats_out.split(",")

                if expect_sync:
                    self.assertIn(
                        "sync",
                        feats,
                        f"TERM={term_type}: 'sync' missing from #{{client_termfeatures}} (parser aborted): {feats_out}",
                    )
                else:
                    self.assertNotIn("sync", feats)

                # Send command to trigger screen refresh and capture PTY master stream
                subprocess.run(
                    ["tmux", "-L", lbl, "send-keys", "-t", f"sess_{term_type.replace('-', '_')}", "echo sync_test", "Enter"],
                    check=True,
                )
                time.sleep(0.3)

                captured = b""
                while select.select([master], [], [], 0.2)[0]:
                    try:
                        chunk = os.read(master, 4096)
                        if not chunk:
                            break
                        captured += chunk
                    except OSError:
                        break

                h_count = captured.count(b"\x1b[?2026h")
                l_count = captured.count(b"\x1b[?2026l")

                if expect_sync:
                    self.assertGreater(
                        h_count,
                        0,
                        f"TERM={term_type}: No \\x1b[?2026h (synchronized update start) sequence emitted",
                    )
                    self.assertEqual(
                        h_count,
                        l_count,
                        f"TERM={term_type}: Unbalanced sync sequences: {h_count} start vs {l_count} end",
                    )
                else:
                    self.assertEqual(
                        h_count,
                        0,
                        f"TERM={term_type}: Unexpected \\x1b[?2026h sequence emitted on non-sync terminal",
                    )
                    self.assertEqual(l_count, 0)
            finally:
                subprocess.run(["tmux", "-L", lbl, "kill-server"], capture_output=True, text=True)
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=2)
                os.close(slave)
                os.close(master)


if __name__ == "__main__":
    unittest.main()
