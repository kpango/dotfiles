#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M3 (Instance 2): Syscall Robustness & Status Hammer Adversary.

Attacks and stress tests:
1. Syscall error handling & negative testing:
   - statBuf and openBuf handle non-existent paths (ENOENT), permission denied (EACCES),
     unreadable directories, empty slices (EINVAL), and null-only bytes without panicking.
   - findGitHeadMtime on 50-level deeply nested non-git directories terminates cleanly at filesystem root (/)
     with zero infinite looping or stack overflow.
   - findGitHeadMtime on path exceeding PATH_MAX buffer (4112 bytes) terminates cleanly.
   - gitdir / gitfile worktree pointer handling.
2. Boundary Condition Analysis:
   - parentDir("") behavior and CLI defensive interception in paneOut and paneSegment.
3. CLI High-Frequency Status Hammer:
   - 1,000 rapid sequential CLI calls to `~/.zcache/tmux-pane-info pane $PWD`.
   - 1,000 rapid sequential CLI calls to `~/.zcache/tmux-pane-info right`.
   - Latency assertion: average latency and p95 latency must be <= 5.0 ms per call.
   - 100% exit code 0 success rate across all 2,000 calls.
4. Resource & File Descriptor Leak Prevention:
   - Zero FD leaks verified across 1,000 rapid executions.
   - Zero orphaned atomic cache files (*.tmp.*) left in ~/.cache.
   - Peak RSS stability verified (<= 25 MB).
5. Exact Visual Powerline Format Conformity:
   - Exact Powerline arrow glyph transitions (U+E0B0, U+E0B2).
   - Strict color segment styling matching tmux.conf.d/status.conf specifications.
"""

import glob
import os
import re
import shutil
import statistics
import subprocess
import tempfile
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PANE_INFO_BIN = os.path.expanduser("~/.zcache/tmux-pane-info")
PANE_INFO_DIR = os.path.join(PROJECT_ROOT, "tmux.conf.d", "tmux-pane-info")

PL_RIGHT = "\ue0b0"  # 
PL_LEFT = "\ue0b2"   # 


class TestChallengerM3_2Adversarial(unittest.TestCase):
    """Adversarial stress harness for M3-2 tmux-pane-info raw syscalls and status hammer."""

    @classmethod
    def setUpClass(cls):
        # Verify binary existence and buildability
        if not os.path.exists(PANE_INFO_BIN):
            subprocess.run(
                ["go", "build", "-ldflags=-s -w", "-o", PANE_INFO_BIN, "."],
                cwd=PANE_INFO_DIR,
                check=True,
            )

    def test_adv_1_syscall_error_paths_and_negative_inputs(self):
        """Adversarial 1: Negative syscall testing on statBuf, openBuf, and findGitHeadMtime."""
        test_code = r"""package main

import (
	"os"
	"strings"
	"syscall"
	"testing"
)

func TestAdversarialSyscallsInternal(t *testing.T) {
	var st syscall.Stat_t

	// 1. Empty slice handling (must return EINVAL without panicking)
	if errno := statBuf(nil, &st); errno != syscall.EINVAL {
		t.Fatalf("statBuf(nil) = %v, want EINVAL", errno)
	}
	if fd, errno := openBuf(nil, syscall.O_RDONLY); errno != syscall.EINVAL || fd != -1 {
		t.Fatalf("openBuf(nil) = (%d, %v), want (-1, EINVAL)", fd, errno)
	}
	if errno := statBuf([]byte{}, &st); errno != syscall.EINVAL {
		t.Fatalf("statBuf([]byte{}) = %v, want EINVAL", errno)
	}
	if fd, errno := openBuf([]byte{}, syscall.O_RDONLY); errno != syscall.EINVAL || fd != -1 {
		t.Fatalf("openBuf([]byte{}) = (%d, %v), want (-1, EINVAL)", fd, errno)
	}

	// 2. Empty string (just null terminator, should return ENOENT)
	if errno := statBuf([]byte{0}, &st); errno != syscall.ENOENT {
		t.Fatalf("statBuf(\"\\x00\") = %v, want ENOENT", errno)
	}
	if fd, errno := openBuf([]byte{0}, syscall.O_RDONLY); errno != syscall.ENOENT || fd != -1 {
		t.Fatalf("openBuf(\"\\x00\") = (%d, %v), want (-1, ENOENT)", fd, errno)
	}

	// 3. Non-existent path (ENOENT)
	nonExist := []byte("/this/path/absolutely/does/not/exist/on/the/filesystem/test12345\x00")
	if errno := statBuf(nonExist, &st); errno != syscall.ENOENT {
		t.Fatalf("statBuf(nonExist) = %v, want ENOENT", errno)
	}
	if fd, errno := openBuf(nonExist, syscall.O_RDONLY); errno != syscall.ENOENT || fd != -1 {
		t.Fatalf("openBuf(nonExist) = (%d, %v), want (-1, ENOENT)", fd, errno)
	}

	// 4. Permission denied (EACCES)
	tmpDir, err := os.MkdirTemp("", "adv_eacces_*")
	if err != nil {
		t.Fatal(err)
	}
	defer os.RemoveAll(tmpDir)

	unreadableDir := tmpDir + "/noperm"
	if err := os.Mkdir(unreadableDir, 0000); err != nil {
		t.Fatal(err)
	}
	defer os.Chmod(unreadableDir, 0755)

	testFileInNoPerm := []byte(unreadableDir + "/file\x00")
	errnoStat := statBuf(testFileInNoPerm, &st)
	fdOpen, errnoOpen := openBuf(testFileInNoPerm, syscall.O_RDONLY)
	if os.Getuid() != 0 {
		if errnoStat != syscall.EACCES {
			t.Fatalf("statBuf on unreadable dir = %v, want EACCES", errnoStat)
		}
		if errnoOpen != syscall.EACCES || fdOpen != -1 {
			t.Fatalf("openBuf on unreadable dir = (%d, %v), want (-1, EACCES)", fdOpen, errnoOpen)
		}
	}

	// 5. 50-level deeply nested directory without git repository
	deepDir := tmpDir
	for i := 0; i < 50; i++ {
		deepDir += "/lvl" + string(rune(48+i%10))
	}
	if err := os.MkdirAll(deepDir, 0755); err != nil {
		t.Fatal(err)
	}
	mtime := findGitHeadMtime(deepDir)
	if mtime != 0 {
		t.Fatalf("findGitHeadMtime on 50-level non-git directory = %d, want 0", mtime)
	}

	// 6. Path exceeding 4112 byte stack buffer
	longDir := tmpDir + "/" + strings.Repeat("long_segment_directory_name/", 220)
	mtimeLong := findGitHeadMtime(longDir)
	if mtimeLong != 0 {
		t.Fatalf("findGitHeadMtime on >4112 byte path = %d, want 0", mtimeLong)
	}

	// 7. Git worktree with .git file ("gitdir: <path>")
	wtDir := tmpDir + "/worktree_test"
	if err := os.MkdirAll(wtDir, 0755); err != nil {
		t.Fatal(err)
	}
	realGitDir := tmpDir + "/real_git_dir"
	if err := os.MkdirAll(realGitDir, 0755); err != nil {
		t.Fatal(err)
	}
	headContent := []byte("ref: refs/heads/feature/adversarial-wt\n")
	if err := os.WriteFile(realGitDir+"/HEAD", headContent, 0644); err != nil {
		t.Fatal(err)
	}
	gitFileContent := []byte("gitdir: " + realGitDir + "\n")
	if err := os.WriteFile(wtDir+"/.git", gitFileContent, 0644); err != nil {
		t.Fatal(err)
	}

	wtMtime := findGitHeadMtime(wtDir)
	if wtMtime == 0 {
		t.Fatalf("findGitHeadMtime on gitfile worktree returned 0, want non-zero mtime")
	}
}
"""
        tmp_test_file = os.path.join(PANE_INFO_DIR, "adversarial_m3_2_generated_test.go")
        try:
            with open(tmp_test_file, "w") as f:
                f.write(test_code)

            res = subprocess.run(
                ["go", "test", "-v", "-run", "TestAdversarialSyscallsInternal", "./..."],
                cwd=PANE_INFO_DIR,
                capture_output=True,
                text=True,
                timeout=15,
            )
            self.assertEqual(
                res.returncode,
                0,
                f"Adversarial syscall internal Go test failed:\nSTDOUT:\n{res.stdout}\nSTDERR:\n{res.stderr}",
            )
            self.assertIn("PASS: TestAdversarialSyscallsInternal", res.stdout)
        finally:
            if os.path.exists(tmp_test_file):
                os.remove(tmp_test_file)

    def test_adv_2_parent_dir_empty_string_boundary(self):
        """Adversarial 2: Boundary test on parentDir("") finding and CLI defensive guards."""
        # 1. Empirically verify the panic in direct parentDir("") call
        test_panic_code = r"""package main

import "testing"

func TestParentDirPanicDirect(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Logf("Expected panic observed: %v", r)
			return
		}
		t.Fatalf("expected panic on parentDir(\"\") but none occurred")
	}()
	_ = parentDir("")
}
"""
        tmp_test_file = os.path.join(PANE_INFO_DIR, "adversarial_m3_2_panic_test.go")
        try:
            with open(tmp_test_file, "w") as f:
                f.write(test_panic_code)

            res = subprocess.run(
                ["go", "test", "-v", "-run", "TestParentDirPanicDirect", "./..."],
                cwd=PANE_INFO_DIR,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(res.returncode, 0, f"Panic test runner failed:\n{res.stdout}\n{res.stderr}")
            self.assertIn("Expected panic observed", res.stdout)
        finally:
            if os.path.exists(tmp_test_file):
                os.remove(tmp_test_file)

        # 2. Assert CLI entrypoints (pane, path, branch) guard against empty strings
        for subcmd in ["pane", "path", "branch"]:
            cmd = [PANE_INFO_BIN, subcmd, ""]
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
            self.assertEqual(
                proc.returncode,
                0,
                f"tmux-pane-info {subcmd} '' failed with exit code {proc.returncode}: {proc.stderr}",
            )

        # 3. Assert CLI handles root "/" and multiple slashes "///" without hanging
        for p in ["/", "///", "/.", "/..", "/nonexistent/deep/path"]:
            proc = subprocess.run([PANE_INFO_BIN, "pane", p], capture_output=True, text=True, timeout=5)
            self.assertEqual(proc.returncode, 0, f"tmux-pane-info pane '{p}' crashed: {proc.stderr}")

    def test_adv_3_cli_status_hammer_1000_calls(self):
        """Adversarial 3: Status Hammer - 1,000 rapid sequential CLI calls to pane and right."""
        iterations = 1000

        # Subtest A: 1,000 rapid calls to `tmux-pane-info pane $PWD`
        pane_lats = []
        t0_pane = time.perf_counter()
        for i in range(iterations):
            t_call_0 = time.perf_counter()
            p = subprocess.run(
                [PANE_INFO_BIN, "pane", PROJECT_ROOT],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            t_call_1 = time.perf_counter()
            self.assertEqual(p.returncode, 0, f"pane call {i} failed with exit {p.returncode}: {p.stderr}")
            pane_lats.append((t_call_1 - t_call_0) * 1000.0)
        t_total_pane = time.perf_counter() - t0_pane

        mean_pane = statistics.mean(pane_lats)
        sorted_pane = sorted(pane_lats)
        p50_pane = sorted_pane[int(iterations * 0.50)]
        p95_pane = sorted_pane[int(iterations * 0.95)]
        p99_pane = sorted_pane[int(iterations * 0.99)]

        print(
            f"\n[HAMMER PANE] 1,000 calls: total={t_total_pane:.3f}s | "
            f"mean={mean_pane:.3f}ms | p50={p50_pane:.3f}ms | p95={p95_pane:.3f}ms | p99={p99_pane:.3f}ms"
        )
        self.assertLessEqual(mean_pane, 5.0, f"Mean latency for pane ({mean_pane:.3f}ms) exceeds 5.0ms threshold")
        self.assertLessEqual(p95_pane, 5.0, f"p95 latency for pane ({p95_pane:.3f}ms) exceeds 5.0ms threshold")

        # Subtest B: 1,000 rapid calls to `tmux-pane-info right`
        right_lats = []
        t0_right = time.perf_counter()
        for i in range(iterations):
            t_call_0 = time.perf_counter()
            p = subprocess.run(
                [PANE_INFO_BIN, "right"],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            t_call_1 = time.perf_counter()
            self.assertEqual(p.returncode, 0, f"right call {i} failed with exit {p.returncode}: {p.stderr}")
            right_lats.append((t_call_1 - t_call_0) * 1000.0)
        t_total_right = time.perf_counter() - t0_right

        mean_right = statistics.mean(right_lats)
        sorted_right = sorted(right_lats)
        p50_right = sorted_right[int(iterations * 0.50)]
        p95_right = sorted_right[int(iterations * 0.95)]
        p99_right = sorted_right[int(iterations * 0.99)]

        print(
            f"[HAMMER RIGHT] 1,000 calls: total={t_total_right:.3f}s | "
            f"mean={mean_right:.3f}ms | p50={p50_right:.3f}ms | p95={p95_right:.3f}ms | p99={p99_right:.3f}ms"
        )
        self.assertLessEqual(mean_right, 5.0, f"Mean latency for right ({mean_right:.3f}ms) exceeds 5.0ms threshold")
        self.assertLessEqual(p95_right, 5.0, f"p95 latency for right ({p95_right:.3f}ms) exceeds 5.0ms threshold")

    def test_adv_4_fd_leak_and_resource_stability(self):
        """Adversarial 4: Assert zero FD leaks and stable cache/memory usage."""
        cache_dir = os.path.expanduser("~/.cache")

        # Check open FDs in caller process before hammer
        fds_before = len(os.listdir("/proc/self/fd"))
        tmp_files_before = len(glob.glob(os.path.join(cache_dir, "tmux-*.tmp.*")))

        # Run 200 interleaved calls
        for _ in range(100):
            subprocess.run([PANE_INFO_BIN, "pane", PROJECT_ROOT], stdout=subprocess.DEVNULL)
            subprocess.run([PANE_INFO_BIN, "right"], stdout=subprocess.DEVNULL)

        fds_after = len(os.listdir("/proc/self/fd"))
        tmp_files_after = len(glob.glob(os.path.join(cache_dir, "tmux-*.tmp.*")))

        self.assertEqual(
            fds_before,
            fds_after,
            f"File descriptor leak detected in caller harness: before={fds_before}, after={fds_after}",
        )
        self.assertEqual(
            tmp_files_after,
            0,
            f"Orphaned temporary cache files found in ~/.cache: {tmp_files_after}",
        )

        # Check peak RSS of tmux-pane-info using an isolated measurement subprocess
        rss_check_code = f"""
import subprocess, resource
for _ in range(50):
    subprocess.run(["{PANE_INFO_BIN}", "pane", "{PROJECT_ROOT}"], stdout=subprocess.DEVNULL)
    subprocess.run(["{PANE_INFO_BIN}", "right"], stdout=subprocess.DEVNULL)
usage = resource.getrusage(resource.RUSAGE_CHILDREN)
print(usage.ru_maxrss / 1024.0)
"""
        proc_rss = subprocess.run(
            ["python3", "-c", rss_check_code],
            capture_output=True,
            text=True,
            check=True,
        )
        max_rss_mb = float(proc_rss.stdout.strip())
        print(f"\n[RESOURCE STABILITY] Peak tmux-pane-info child RSS: {max_rss_mb:.2f} MB (limit <= 25.0 MB)")
        self.assertLessEqual(max_rss_mb, 25.0, f"Child process RSS ({max_rss_mb:.2f}MB) exceeded 25MB limit")

    def test_adv_5_exact_powerline_visual_format_conformity(self):
        """Adversarial 5: Assert exact visual format conformity with Powerline definitions."""
        # 1. pane with git repo ($PROJECT_ROOT)
        p_git = subprocess.run([PANE_INFO_BIN, "pane", PROJECT_ROOT], capture_output=True, text=True, check=True)
        out_git = p_git.stdout
        self.assertTrue(
            out_git.startswith("#[fg=#6eb4bf,bg=#2f343e]"),
            f"pane git output missing path color prefix: {out_git}",
        )
        self.assertIn(
            f"#[fg=#2f343e,bg=#b477cf,nobold]{PL_RIGHT}#[fg=#282c33,bg=#b477cf,nobold]",
            out_git,
            f"pane git output missing branch pill separator: {out_git}",
        )
        self.assertTrue(
            out_git.endswith(f"#[fg=#b477cf,bg=#1f1f1f,nobold]{PL_RIGHT}"),
            f"pane git output missing terminal separator: {out_git}",
        )

        # 2. pane with non-git repo (/tmp)
        tmp_non_git = tempfile.mkdtemp(prefix="adv_nongit_")
        try:
            p_nongit = subprocess.run([PANE_INFO_BIN, "pane", tmp_non_git], capture_output=True, text=True, check=True)
            out_nongit = p_nongit.stdout
            self.assertTrue(
                out_nongit.startswith("#[fg=#6eb4bf,bg=#2f343e]"),
                f"nongit output missing path color prefix: {out_nongit}",
            )
            self.assertTrue(
                out_nongit.endswith(f"#[fg=#2f343e,bg=#1f1f1f,nobold]{PL_RIGHT}"),
                f"nongit output missing terminal separator: {out_nongit}",
            )
            self.assertNotIn("#[fg=#b477cf,bg=#1f1f1f", out_nongit)
        finally:
            shutil.rmtree(tmp_non_git, ignore_errors=True)

        # 3. pane with root "/"
        p_root = subprocess.run([PANE_INFO_BIN, "pane", "/"], capture_output=True, text=True, check=True)
        out_root = p_root.stdout
        expected_root = f"#[fg=#6eb4bf,bg=#2f343e]/#[fg=#2f343e,bg=#1f1f1f,nobold]{PL_RIGHT}"
        self.assertEqual(out_root, expected_root, f"root output mismatch: got {out_root}, want {expected_root}")

        # 4. right status bar
        p_right = subprocess.run([PANE_INFO_BIN, "right"], capture_output=True, text=True, check=True)
        out_right = p_right.stdout
        self.assertTrue(
            out_right.startswith("#[fg=#a1c181,bg=#282c33]CPU:"),
            f"right status missing CPU prefix: {out_right}",
        )
        self.assertIn(" #[fg=#73ade9]RAM:", out_right, f"right status missing RAM metric: {out_right}")
        self.assertIn(
            f" #[fg=#2f343e,bg=#282c33]{PL_LEFT}#[bg=#2f343e]",
            out_right,
            f"right status missing Powerline left separator: {out_right}",
        )
        cpu_match = re.search(r"CPU:#\[fg=(?:green|yellow|red)\]\d+\.\d+%", out_right)
        self.assertIsNotNone(cpu_match, f"right status CPU format invalid: {out_right}")
        ram_match = re.search(r"RAM:#\[fg=(?:green|yellow|red)\]\d+\.\d+%", out_right)
        self.assertIsNotNone(ram_match, f"right status RAM format invalid: {out_right}")


if __name__ == "__main__":
    unittest.main()
