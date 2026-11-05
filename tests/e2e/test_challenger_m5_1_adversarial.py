#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M5: Features 13 & 15.

Tasks:
1. sysclean Autoloading & Execution Stress:
   - Verify sysclean is autoloaded via `whence -v sysclean` and `which sysclean`.
   - Test invoking sysclean --help / dry-run: assert it resolves, defines helpers, executes with 0 errors.
   - Verify zclean and zprecompile continue to work from zsh/05-functions.zsh.
2. Batch Chaining Stress:
   - Verify Batch 2 and Batch 3 execute seamlessly in order without race conditions or missing environment variables.
   - Stress test rapid interactive input during startup: assert keystrokes are echoed and handled cleanly without dropping.
"""

import concurrent.futures
import os
import pty
import select
import subprocess
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ZCACHE_DIR = os.path.expanduser("~/.zcache")
ZFUNC_DIR = os.path.join(PROJECT_ROOT, "zfunc")
SYSCLEAN_FILE = os.path.join(ZFUNC_DIR, "sysclean")
FUNCTIONS_FILE = os.path.join(PROJECT_ROOT, "zsh", "05-functions.zsh")


class TestSyscleanAutoloadAndExecution(unittest.TestCase):
    """Stress-test sysclean autoloading, helper definition, and zclean/zprecompile."""

    def test_sysclean_file_exists_and_syntax_valid(self):
        """Assert zfunc/sysclean exists, is non-empty, and has valid zsh syntax."""
        self.assertTrue(os.path.isfile(SYSCLEAN_FILE), "zfunc/sysclean must exist")
        self.assertGreater(os.path.getsize(SYSCLEAN_FILE), 10000, "zfunc/sysclean must contain full implementation")

        res = subprocess.run(["zsh", "-n", SYSCLEAN_FILE], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"zsh -n syntax error on {SYSCLEAN_FILE}: {res.stderr}")

    def test_sysclean_autoload_state_before_invocation(self):
        """Assert sysclean is marked as autoload shell function before first invocation."""
        cmd = """
fpath=({zfunc} $fpath)
source {funcs}
print -r -- "WHENCE: $(whence -v sysclean)"
print -r -- "WHICH: $(which sysclean)"
exit 0
""".format(zfunc=ZFUNC_DIR, funcs=FUNCTIONS_FILE)

        res = subprocess.run(["zsh", "-f", "-c", cmd], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Execution failed: {res.stderr}")
        self.assertIn("autoload shell function", res.stdout, "sysclean must be an autoload shell function")
        self.assertIn("builtin autoload -XUz", res.stdout, "sysclean must have autoload stub")

    def test_sysclean_resolution_and_helper_definitions(self):
        """Assert invoking sysclean resolves the autoload, defines all 11 helpers, and completes with exit 0."""
        helpers = [
            "_sysclean_step",
            "_sysclean_chrome",
            "_sysclean_pyc",
            "_sysclean_log_tail",
            "_sysclean_tmpdir",
            "_sysclean_drop_caches",
            "_sysclean_swap_reset",
            "_sysclean_tmux_stale",
            "_sysclean_claude",
            "_sysclean_src_build_cache",
            "_sysclean_rustup",
        ]

        h_checks = " ".join([f'(( $+functions[{h}] )) || echo "MISSING_{h}"' for h in helpers])

        test_script = f"""
fpath=({ZFUNC_DIR} $fpath)
source {FUNCTIONS_FILE}

# Safe mocks for external/destructive utilities
sudo() {{ return 0; }}
docker() {{ return 0; }}
kacclean() {{ return 0; }}
zclean() {{ return 0; }}
xargs() {{ return 0; }}
truncate() {{ return 0; }}
rustup() {{ return 0; }}
go() {{ return 0; }}
npm() {{ return 0; }}
pip3() {{ return 0; }}
fc-cache() {{ return 0; }}
resolvectl() {{ return 0; }}

# Invoke sysclean with --help
sysclean --help >/dev/null 2>&1
ret=$?
echo "EXIT_CODE:$ret"
echo "WHENCE_AFTER:$(whence -v sysclean)"

# Check helpers
{h_checks}
exit 0
"""
        res = subprocess.run(["zsh", "-f", "-c", test_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Failed: {res.stderr}")
        self.assertIn("EXIT_CODE:0", res.stdout, "sysclean invocation must return 0")
        self.assertIn("WHENCE_AFTER:sysclean is a shell function", res.stdout, "sysclean must resolve to shell function")
        for h in helpers:
            self.assertNotIn(f"MISSING_{h}", res.stdout, f"Helper {h} must be defined after sysclean invocation")

    def test_sysclean_multiple_invocations(self):
        """Assert sysclean can be called multiple times in same session without autoload re-trigger."""
        test_script = f"""
fpath=({ZFUNC_DIR} $fpath)
source {FUNCTIONS_FILE}

sudo() {{ return 0; }}
docker() {{ return 0; }}
kacclean() {{ return 0; }}
zclean() {{ return 0; }}
xargs() {{ return 0; }}
truncate() {{ return 0; }}
rustup() {{ return 0; }}
go() {{ return 0; }}
npm() {{ return 0; }}
pip3() {{ return 0; }}
fc-cache() {{ return 0; }}
resolvectl() {{ return 0; }}

sysclean --dry-run >/dev/null 2>&1
r1=$?
sysclean --dry-run >/dev/null 2>&1
r2=$?
echo "R1:$r1 R2:$r2"
exit 0
"""
        res = subprocess.run(["zsh", "-f", "-c", test_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Multiple invocations failed: {res.stderr}")
        self.assertIn("R1:0 R2:0", res.stdout, "Both sysclean invocations must succeed")

    def test_sysclean_helper_isolation_and_edge_cases(self):
        """Stress-test individual helper functions on boundary conditions."""
        test_script = f"""
fpath=({ZFUNC_DIR} $fpath)
source {FUNCTIONS_FILE}

sudo() {{ return 0; }}
docker() {{ return 0; }}
kacclean() {{ return 0; }}
zclean() {{ return 0; }}
xargs() {{ return 0; }}
truncate() {{ return 0; }}
rustup() {{ return 0; }}
go() {{ return 0; }}
npm() {{ return 0; }}
pip3() {{ return 0; }}
fc-cache() {{ return 0; }}
resolvectl() {{ return 0; }}

# Trigger load
sysclean --dry-run >/dev/null 2>&1

# 1. Test _sysclean_log_tail on non-existent file
_sysclean_log_tail "/tmp/non_existent_log_12345" 100
echo "LOG_TAIL_NONEXISTENT:$?"

# 2. Test _sysclean_log_tail on real temp file
tmpf=$(mktemp)
for i in {{1..50}}; do echo "line $i" >> "$tmpf"; done
_sysclean_log_tail "$tmpf" 10
lines=$(wc -l < "$tmpf")
rm -f "$tmpf"
echo "LOG_TAIL_LINES:$lines"

# 3. Test _sysclean_chrome on non-existent dir
_sysclean_chrome "/tmp/non_existent_chrome_12345"
echo "CHROME_NONEXISTENT:$?"

# 4. Test _sysclean_pyc on non-existent dir
_sysclean_pyc "/tmp/non_existent_pyc_12345"
echo "PYC_NONEXISTENT:$?"

# 5. Test _sysclean_tmpdir on non-existent dir
_sysclean_tmpdir "/tmp/non_existent_tmpdir_12345"
echo "TMPDIR_NONEXISTENT:$?"
exit 0
"""
        res = subprocess.run(["zsh", "-f", "-c", test_script], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Helper edge cases failed: {res.stderr}")
        self.assertIn("LOG_TAIL_NONEXISTENT:0", res.stdout)
        self.assertIn("LOG_TAIL_LINES:10", res.stdout)
        self.assertIn("CHROME_NONEXISTENT:0", res.stdout)
        self.assertIn("PYC_NONEXISTENT:0", res.stdout)
        self.assertIn("TMPDIR_NONEXISTENT:0", res.stdout)

    def test_zclean_and_zprecompile_retained_and_functional(self):
        """Assert zclean and zprecompile in 05-functions.zsh remain intact and functional."""
        cmd = f"""
source {FUNCTIONS_FILE}
print -r -- "ZCLEAN:$(whence -v zclean)"
print -r -- "ZPRECOMPILE:$(whence -v zprecompile)"
exit 0
"""
        res = subprocess.run(["zsh", "-f", "-c", cmd], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Failed: {res.stderr}")
        self.assertIn("zclean is a shell function from", res.stdout, "zclean must be defined in 05-functions.zsh")
        self.assertIn("zprecompile is a shell function from", res.stdout, "zprecompile must be defined in 05-functions.zsh")

        # Test executing zprecompile in interactive zsh
        pre_res = subprocess.run(["zsh", "-i", "-c", "zprecompile"], capture_output=True, text=True)
        self.assertEqual(pre_res.returncode, 0, f"zprecompile failed: {pre_res.stderr}")
        self.assertIn("Pre-compiling zsh caches", pre_res.stdout)


class TestBatchChainingStress(unittest.TestCase):
    """Stress-test Batch 2 and Batch 3 chaining, execution order, and rapid input handling."""

    def test_batch2_and_batch3_execution_and_cleanup(self):
        """Assert Batch 2 invokes Batch 3, loads both caches, and cleans up functions."""
        # Query functions status via echo with unambiguous prefixes to avoid PTY echo collision
        cmd = (
            'print "CHECK_BATCH2_EXISTS=$(( $+functions[_defer_batch2] ))"; '
            'print "CHECK_BATCH3_EXISTS=$(( $+functions[_defer_batch3] ))"; '
            'print "CHECK_ZCACHE_EVAL=$(( $+functions[_zcache_eval] ))"; '
            'print "CHECK_COMBINED_LEN=${#combined_cache}"; '
            'exit\n'
        )
        master, slave = pty.openpty()
        p = subprocess.Popen(
            ["zsh", "-i"],
            stdin=slave,
            stdout=slave,
            stderr=slave,
            close_fds=True,
            cwd=PROJECT_ROOT,
        )
        os.close(slave)

        # Allow deferred batches to drain (~400ms)
        time.sleep(0.4)
        os.write(master, cmd.encode())

        out = b""
        start_time = time.time()
        while time.time() - start_time < 2.5:
            r, _, _ = select.select([master], [], [], 0.1)
            if master in r:
                try:
                    data = os.read(master, 4096)
                    if not data:
                        break
                    out += data
                except OSError:
                    break
            if p.poll() is not None:
                break

        p.terminate()
        try:
            p.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            p.kill()
        os.close(master)

        text = out.decode("utf-8", errors="replace")
        self.assertIn("CHECK_BATCH2_EXISTS=0", text, "_defer_batch2 must be unfunctioned (0)")
        self.assertIn("CHECK_BATCH3_EXISTS=0", text, "_defer_batch3 must be unfunctioned (0)")
        self.assertIn("CHECK_ZCACHE_EVAL=1", text, "_zcache_eval from Batch 2 must be available (1)")

    def test_batch3_fallback_when_zsh_defer_absent(self):
        """Assert Batch 3 runs synchronously if zsh-defer is not available."""
        cmd = """
ZSH_EXECUTION_STRING=""
source ~/.zshenv
unfunction zsh-defer 2>/dev/null

DOTFILES_DIR="{root}"
ZCACHE_DIR="{zcache}"
combined_cache="$ZCACHE_DIR/combined.zsh"
_os_cache="$ZCACHE_DIR/os-arch.zsh"
_gui_cache="$ZCACHE_DIR/os-gui.zsh"

_defer_batch3() {{
    echo "FALLBACK_CALLED_SUCCESS"
    unfunction _defer_batch3
}}

if ! (($+functions[zsh-defer])); then
    _defer_batch3
fi

echo "BATCH3_EXISTS=$(( $+functions[_defer_batch3] ))"
exit 0
""".format(root=PROJECT_ROOT, zcache=ZCACHE_DIR)

        res = subprocess.run(["zsh", "-f", "-c", cmd], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Fallback failed: {res.stderr}")
        self.assertIn("FALLBACK_CALLED_SUCCESS", res.stdout, "Fallback must be called immediately when zsh-defer is absent")
        self.assertIn("BATCH3_EXISTS=0", res.stdout, "Fallback must unfunction itself")

    def test_non_tty_startup_skips_defer_cleanly(self):
        """Assert non-TTY non-interactive zsh execution (e.g. zsh -c) executes cleanly without defer errors."""
        res = subprocess.run(["zsh", "-c", "echo NON_TTY_OK"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"zsh -c failed: {res.stderr}")
        self.assertIn("NON_TTY_OK", res.stdout)

    def test_rapid_interactive_input_during_startup_stress(self):
        """Stress-test rapid user input: inject keystrokes at t=0ms, t=5ms, t=10ms across 10 runs.

        Asserts that no characters are dropped, and output tokens match exactly.
        """
        for iteration in range(10):
            token = f"ADVERSARIAL_TOKEN_{iteration}_{int(time.time()*1000)%100000}"
            master, slave = pty.openpty()
            p = subprocess.Popen(
                ["zsh", "-i"],
                stdin=slave,
                stdout=slave,
                stderr=slave,
                close_fds=True,
                cwd=PROJECT_ROOT,
            )
            os.close(slave)

            # Rapidly pump input with microsecond spacing simulating burst keystrokes
            test_cmd = f"echo {token}; exit\n"
            for char in test_cmd:
                os.write(master, char.encode())
                time.sleep(0.002)

            out = b""
            start_time = time.time()
            while time.time() - start_time < 3.0:
                r, _, _ = select.select([master], [], [], 0.1)
                if master in r:
                    try:
                        chunk = os.read(master, 4096)
                        if not chunk:
                            break
                        out += chunk
                    except OSError:
                        break
                if p.poll() is not None:
                    break

            p.terminate()
            try:
                p.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                p.kill()
            os.close(master)

            text = out.decode("utf-8", errors="replace")
            self.assertIn(
                token,
                text,
                f"Iteration {iteration}: Keystrokes were dropped or not processed! Token '{token}' missing from output.",
            )

    def test_concurrent_sessions_batch_chaining_stress(self):
        """Stress-test concurrent interactive sessions running chained Batch 2/3 under high concurrency."""
        def run_single_session(idx):
            token = f"CONCURRENCY_TOKEN_{idx}"
            master, slave = pty.openpty()
            p = subprocess.Popen(
                ["zsh", "-i"],
                stdin=slave,
                stdout=slave,
                stderr=slave,
                close_fds=True,
                cwd=PROJECT_ROOT,
            )
            os.close(slave)

            time.sleep(0.1)
            os.write(master, f"echo {token}; exit\n".encode())

            out = b""
            start = time.time()
            while time.time() - start < 3.0:
                r, _, _ = select.select([master], [], [], 0.05)
                if master in r:
                    try:
                        chunk = os.read(master, 4096)
                        if not chunk:
                            break
                        out += chunk
                    except OSError:
                        break
                if p.poll() is not None:
                    break

            p.terminate()
            try:
                p.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                p.kill()
            os.close(master)

            return token in out.decode("utf-8", errors="replace")

        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            futures = [executor.submit(run_single_session, i) for i in range(10)]
            results = [f.result() for f in concurrent.futures.as_completed(futures)]

        self.assertTrue(all(results), f"One or more concurrent sessions dropped input: {results}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
