#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M3: tmux-pane-info Zero-Allocation & Syscall Tuning.

Attacks tested:
1. Boundary & Extreme Paths: Pass paths with >256B, 500B, 1000B, 4096B, emojis, surrogate pairs,
   slashes-only, trailing slashes, relative paths, null-byte injection to CLI and Go test harness.
2. Go Race Detector & Concurrency: Run 100 concurrent goroutines executing paneOut and paneSegment
   under Go's race detector (-race).
3. CLI Long-Path Resilience: Invoke ~/.zcache/tmux-pane-info with 1000-byte paths and verify zero crashes.
4. Memory Safety & Stability: Assert zero leaks over 10,000 rapid iterations.
"""

import os
import subprocess
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BINARY_PATH = os.path.expanduser("~/.zcache/tmux-pane-info")
PANE_INFO_DIR = os.path.join(PROJECT_ROOT, "tmux.conf.d", "tmux-pane-info")


class TestChallengerM3Adversarial(unittest.TestCase):
    """Adversarial challenge suite for Milestone M3."""

    def test_adv_1_go_race_and_adversarial_suite(self):
        """Adversarial 1: Execute Go adversarial harness under race detector (-race)."""
        cmd = ["go", "test", "-v", "-race", "-count=1", "-run", "TestAdversarial", "."]
        proc = subprocess.run(cmd, cwd=PANE_INFO_DIR, capture_output=True, text=True)
        self.assertEqual(
            proc.returncode,
            0,
            f"Go adversarial test failed:\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}",
        )
        self.assertIn("PASS: TestAdversarialAbbreviatePath_ExtremeLengths", proc.stdout)
        self.assertIn("PASS: TestAdversarialAbbreviatePath_UnusualUnicodeAndSurrogates", proc.stdout)
        self.assertIn("PASS: TestAdversarialAbbreviatePath_StructuralEdges", proc.stdout)
        self.assertIn("PASS: TestAdversarialConcurrencyStress_100Goroutines", proc.stdout)
        self.assertIn("PASS: TestAdversarialMemoryStability", proc.stdout)

    def test_adv_2_cli_extreme_path_arguments(self):
        """Adversarial 2: Pass extreme path arguments (>1000B, unicode, emojis) to compiled CLI."""
        if not os.path.isfile(BINARY_PATH):
            self.skipTest(f"Binary {BINARY_PATH} not found")

        extreme_paths = [
            "/a" * 500,  # 1000 bytes
            "/very/long/nested/path/" + "sub/" * 100 + "leaf",
            "/🚀rocket/🔥fire/🎉party/target",
            "///",
            "/////",
            "/a/b/c/",
            "../../internal/cache",
            "/safe/path/with spaces and tabs\t/target",
        ]

        for p in extreme_paths:
            # Test 'pane' subcommand
            proc = subprocess.run(
                [BINARY_PATH, "pane", p],
                capture_output=True,
                text=True,
                timeout=2.0,
            )
            self.assertEqual(
                proc.returncode,
                0,
                f"Binary crashed on 'pane {p[:30]}...': {proc.stderr}",
            )
            self.assertTrue(len(proc.stdout) > 0, f"Expected non-empty output for path {p[:30]}")

            # Test default ('path') subcommand
            proc_path = subprocess.run(
                [BINARY_PATH, "path", p],
                capture_output=True,
                text=True,
                timeout=2.0,
            )
            self.assertEqual(
                proc_path.returncode,
                0,
                f"Binary crashed on 'path {p[:30]}...': {proc_path.stderr}",
            )

    def test_adv_3_zero_allocation_microbenchmarks(self):
        """Adversarial 3: Verify microbenchmarks achieve exactly 0 allocs/op and 0 B/op."""
        cmd = [
            "go",
            "test",
            "-bench=^(BenchmarkReadCacheHit|BenchmarkPaneSegmentCacheHit|BenchmarkAbbreviatePath|BenchmarkWriteSegment)$",
            "-benchmem",
            "-count=1",
            ".",
        ]
        proc = subprocess.run(cmd, cwd=PANE_INFO_DIR, capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, f"Benchmark execution failed: {proc.stderr}")

        for line in proc.stdout.splitlines():
            if "Benchmark" in line and "ns/op" in line:
                self.assertIn(
                    "0 B/op",
                    line,
                    f"Non-zero allocation detected in benchmark: {line}",
                )
                self.assertIn(
                    "0 allocs/op",
                    line,
                    f"Non-zero allocations detected in benchmark: {line}",
                )


if __name__ == "__main__":
    unittest.main()
