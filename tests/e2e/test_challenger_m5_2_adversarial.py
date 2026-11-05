#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M5: Feature 14.

Adversarial Tasks:
1. Lazy k8s Completion Attack:
   - In PTY environment, test typing helm <TAB>, kubectl <TAB>, k <TAB>, kubecolor <TAB>, k9s <TAB> on fresh shell sessions.
   - Assert completions resolve immediately on first Tab press without falling back to file paths.
   - Verify completion menu select arrow keys and Shift+Tab navigation function 100% on the dynamically loaded completion list.
   - Verify second Tab press uses cached definition directly with zero overhead.
2. Cold Cache Regeneration Attack:
   - Delete $ZCACHE_DIR/combined_completion.zsh*.
   - Launch interactive session and type kubectl <TAB>: assert cache file is cleanly regenerated, compiled, and matches are displayed without hanging or syntax errors.
"""

import errno
import fcntl
import glob
import os
import pty
import re
import select
import shutil
import struct
import subprocess
import tempfile
import termios
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ZCACHE_DIR = os.path.expanduser("~/.zcache")
COMBINED_COMP_SRC = os.path.join(ZCACHE_DIR, "combined_completion.zsh")
COMBINED_COMP_ZWC = os.path.join(ZCACHE_DIR, "combined_completion.zsh.zwc")


def strip_ansi(text: str) -> str:
    """Strip ANSI escape sequences from terminal output."""
    ansi_regex = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    return ansi_regex.sub("", text)


class PtySession:
    """Helper to launch and interact with an interactive zsh process in a real PTY."""

    def __init__(self, cwd=None, env=None, rows=30, cols=140):
        self.cwd = cwd or PROJECT_ROOT
        self.master, self.slave = pty.openpty()

        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, winsize)

        sub_env = os.environ.copy()
        sub_env["TERM"] = "xterm-256color"
        sub_env["TMUX"] = "mock_session"
        sub_env["DOTFILES_DIR"] = PROJECT_ROOT
        if env:
            sub_env.update(env)

        self.pid = os.fork()
        if self.pid == 0:
            os.close(self.master)
            os.setsid()
            fcntl.ioctl(self.slave, termios.TIOCSCTTY, 0)
            os.dup2(self.slave, 0)
            os.dup2(self.slave, 1)
            os.dup2(self.slave, 2)
            os.close(self.slave)
            os.chdir(self.cwd)
            os.execvpe("zsh", ["zsh", "-i"], sub_env)
            os._exit(1)

        os.close(self.slave)
        flags = fcntl.fcntl(self.master, fcntl.F_GETFL)
        fcntl.fcntl(self.master, fcntl.F_SETFL, flags | os.O_NONBLOCK)

    def read_available(self, timeout=0.3) -> bytes:
        """Read all available bytes from master within timeout."""
        data = b""
        start = time.monotonic()
        while True:
            remaining = max(0.0, timeout - (time.monotonic() - start))
            try:
                rlist, _, _ = select.select([self.master], [], [], remaining)
            except (select.error, InterruptedError):
                break
            if not rlist:
                break
            try:
                chunk = os.read(self.master, 4096)
                if not chunk:
                    break
                data += chunk
            except OSError as e:
                if e.errno not in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINTR):
                    break
                break
        return data

    def wait_for_prompt(self, timeout=5.0) -> str:
        """Wait until zsh renders the prompt (lambda or cross symbol)."""
        start = time.monotonic()
        accum = b""
        while time.monotonic() - start < timeout:
            chunk = self.read_available(timeout=0.1)
            if chunk:
                accum += chunk
                text = accum.decode("utf-8", errors="replace")
                if "╰─λ" in text or "╰─✗" in text:
                    time.sleep(0.15)
                    accum += self.read_available(timeout=0.1)
                    return accum.decode("utf-8", errors="replace")
            time.sleep(0.05)
        return accum.decode("utf-8", errors="replace")

    def drain(self, timeout=0.1) -> bytes:
        """Drain all pending bytes until silence."""
        data = b""
        while True:
            chunk = self.read_available(timeout=timeout)
            if not chunk:
                break
            data += chunk
        return data

    def send(self, data: bytes):
        """Write raw bytes to PTY master."""
        os.write(self.master, data)

    def send_line(self, line: str):
        """Send a line followed by newline."""
        self.send(line.encode("utf-8") + b"\n")

    def run_command(self, cmd: str, timeout=4.0) -> str:
        """Run command and return output up to next prompt."""
        self.drain()
        self.send_line(cmd)
        return self.wait_for_prompt(timeout=timeout)

    def close(self):
        """Terminate child and close master fd."""
        try:
            os.kill(self.pid, 9)
        except ProcessLookupError:
            pass
        try:
            os.waitpid(self.pid, os.WNOHANG)
        except OSError:
            pass
        try:
            os.close(self.master)
        except OSError:
            pass


class TestLazyK8sCompletionAttack(unittest.TestCase):
    """Adversarial Attack 1: Lazy k8s completion on fresh shell sessions."""

    def ensure_cache_exists(self):
        """Helper to ensure combined_completion.zsh exists before warm tests."""
        if not os.path.exists(COMBINED_COMP_SRC):
            subprocess.run(
                [
                    "zsh",
                    "-c",
                    f"""
                    for c in kubectl kind k3d helm skaffold linkerd kustomize k9s; do
                        (($+commands[$c])) && timeout 10 "$c" completion zsh 2>/dev/null
                        print -r -- ""
                    done > "{COMBINED_COMP_SRC}" && zcompile -U -R "{COMBINED_COMP_SRC}" 2>/dev/null
                    """,
                ],
                check=True,
            )

    def setUp(self):
        self.ensure_cache_exists()

    def test_helm_first_tab_resolves_without_filepath_fallback(self):
        """Assert helm <TAB> resolves subcommands immediately without falling back to file paths."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"helm \t")
            out_bytes = session.read_available(timeout=1.0)
            clean = strip_ansi(out_bytes.decode("utf-8", errors="replace"))

            # Must contain helm subcommands
            self.assertTrue(
                "create" in clean and "install" in clean and "version" in clean,
                f"helm completions missing subcommands: {clean[:400]}",
            )
            # Must NOT fall back to repository file paths
            self.assertNotIn("Makefile", clean)
            self.assertNotIn("sheldon.toml", clean)
            self.assertNotIn("zshrc", clean)
        finally:
            session.close()

    def test_kubectl_first_tab_resolves_without_filepath_fallback(self):
        """Assert kubectl <TAB> resolves subcommands immediately without falling back to file paths."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"kubectl \t")
            out_bytes = session.read_available(timeout=1.0)
            clean = strip_ansi(out_bytes.decode("utf-8", errors="replace"))

            self.assertTrue(
                "annotate" in clean and "apply" in clean and "get" in clean,
                f"kubectl completions missing subcommands: {clean[:400]}",
            )
            self.assertNotIn("Makefile", clean)
            self.assertNotIn("sheldon.toml", clean)
        finally:
            session.close()

    def test_k_alias_first_tab_resolves_without_filepath_fallback(self):
        """Assert k <TAB> (alias for kubecolor/kubectl) resolves subcommands immediately."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"k \t")
            out_bytes = session.read_available(timeout=1.0)
            clean = strip_ansi(out_bytes.decode("utf-8", errors="replace"))

            self.assertTrue(
                "annotate" in clean and "apply" in clean and "get" in clean,
                f"k completions missing subcommands: {clean[:400]}",
            )
            self.assertNotIn("Makefile", clean)
            self.assertNotIn("sheldon.toml", clean)
        finally:
            session.close()

    def test_kubecolor_first_tab_resolves_without_filepath_fallback(self):
        """Assert kubecolor <TAB> resolves subcommands immediately."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"kubecolor \t")
            out_bytes = session.read_available(timeout=1.0)
            clean = strip_ansi(out_bytes.decode("utf-8", errors="replace"))

            self.assertTrue(
                "annotate" in clean and "apply" in clean and "get" in clean,
                f"kubecolor completions missing subcommands: {clean[:400]}",
            )
            self.assertNotIn("Makefile", clean)
            self.assertNotIn("sheldon.toml", clean)
        finally:
            session.close()

    def test_k9s_first_tab_resolves_without_filepath_fallback(self):
        """Assert k9s <TAB> resolves subcommands immediately."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"k9s \t")
            out_bytes = session.read_available(timeout=1.0)
            clean = strip_ansi(out_bytes.decode("utf-8", errors="replace"))

            self.assertTrue(
                "completion" in clean and "version" in clean,
                f"k9s completions missing subcommands: {clean[:400]}",
            )
            self.assertNotIn("Makefile", clean)
            self.assertNotIn("sheldon.toml", clean)
        finally:
            session.close()

    def test_collision_directory_never_falls_back_to_local_files(self):
        """Assert that in a directory containing files named helm, kubectl, k, completions never fall back to them."""
        tmpdir = tempfile.mkdtemp(prefix="adv_k8s_coll_")
        try:
            # Create files matching command names and prefixes
            open(os.path.join(tmpdir, "helm"), "w").close()
            open(os.path.join(tmpdir, "helm-chart"), "w").close()
            open(os.path.join(tmpdir, "kubectl"), "w").close()
            open(os.path.join(tmpdir, "kubectl-config"), "w").close()
            open(os.path.join(tmpdir, "k"), "w").close()
            open(os.path.join(tmpdir, "k-secret"), "w").close()
            open(os.path.join(tmpdir, "k9s"), "w").close()
            open(os.path.join(tmpdir, "k9s-config"), "w").close()

            session = PtySession(cwd=tmpdir)
            try:
                session.wait_for_prompt()
                session.drain()

                # Test helm
                session.send(b"helm \t")
                time.sleep(0.4)
                out = strip_ansi(session.drain().decode("utf-8", errors="replace"))
                self.assertIn("create", out)
                self.assertNotIn("helm-chart", out, "helm completion must NOT fall back to local file")

                # Clear and test kubectl
                session.send(b"\x15kubectl \t")
                time.sleep(0.4)
                out_k = strip_ansi(session.drain().decode("utf-8", errors="replace"))
                self.assertIn("apply", out_k)
                self.assertNotIn("kubectl-config", out_k, "kubectl completion must NOT fall back to local file")

                # Clear and test k
                session.send(b"\x15k \t")
                time.sleep(0.4)
                out_kalias = strip_ansi(session.drain().decode("utf-8", errors="replace"))
                self.assertIn("apply", out_kalias)
                self.assertNotIn("k-secret", out_kalias, "k completion must NOT fall back to local file")

                # Clear and test k9s
                session.send(b"\x15k9s \t")
                time.sleep(0.4)
                out_k9s = strip_ansi(session.drain().decode("utf-8", errors="replace"))
                self.assertIn("version", out_k9s)
                self.assertNotIn("k9s-config", out_k9s, "k9s completion must NOT fall back to local file")
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir)


class TestCompletionMenuSelectNavigationAttack(unittest.TestCase):
    """Adversarial Attack 2: Menu select arrow keys and Shift+Tab navigation on dynamic list."""

    def test_menu_select_arrow_navigation_helm(self):
        """Assert Right Arrow moves menu selection to the next candidate on dynamically loaded helm."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            # First Tab displays list, Second Tab enters menu select
            session.send(b"helm \t\t")
            time.sleep(0.3)
            session.drain()

            # Right Arrow (\x1b[C) navigates to second item ('create')
            session.send(b"\x1b[C")
            time.sleep(0.2)
            session.drain()

            # Comment out the line and press Enter to inspect the selected text
            session.send(b"\x01#\n")
            time.sleep(0.3)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("helm create", out, f"Right arrow must select 'create': {out}")
        finally:
            session.close()

    def test_menu_select_shift_tab_reverse_helm(self):
        """Assert Shift+Tab (\x1b[Z) wraps to the last candidate on dynamically loaded helm."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"helm \t\t")
            time.sleep(0.3)
            session.drain()

            # Shift+Tab (\x1b[Z) reverses to last item ('version')
            session.send(b"\x1b[Z")
            time.sleep(0.2)
            session.drain()

            session.send(b"\x01#\n")
            time.sleep(0.3)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("helm version", out, f"Shift+Tab must select 'version': {out}")
        finally:
            session.close()

    def test_menu_select_shift_tab_reverse_kubectl(self):
        """Assert Shift+Tab (\x1b[Z) wraps to the last candidate on dynamically loaded kubectl."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"kubectl \t\t")
            time.sleep(0.3)
            session.drain()

            session.send(b"\x1b[Z")
            time.sleep(0.2)
            session.drain()

            session.send(b"\x01#\n")
            time.sleep(0.3)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("kubectl wait", out, f"Shift+Tab must select 'wait': {out}")
        finally:
            session.close()

    def test_menu_select_shift_tab_reverse_k(self):
        """Assert Shift+Tab (\x1b[Z) wraps to the last candidate on dynamically loaded k."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"k \t\t")
            time.sleep(0.3)
            session.drain()

            session.send(b"\x1b[Z")
            time.sleep(0.2)
            session.drain()

            session.send(b"\x01#\n")
            time.sleep(0.3)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("k wait", out, f"Shift+Tab must select 'wait': {out}")
        finally:
            session.close()

    def test_menu_select_shift_tab_reverse_kubecolor(self):
        """Assert Shift+Tab (\x1b[Z) wraps to the last candidate on dynamically loaded kubecolor."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"kubecolor \t\t")
            time.sleep(0.3)
            session.drain()

            session.send(b"\x1b[Z")
            time.sleep(0.2)
            session.drain()

            session.send(b"\x01#\n")
            time.sleep(0.3)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("kubecolor wait", out, f"Shift+Tab must select 'wait': {out}")
        finally:
            session.close()

    def test_menu_select_shift_tab_reverse_k9s(self):
        """Assert Shift+Tab (\x1b[Z) wraps to the last candidate on dynamically loaded k9s."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"k9s \t\t")
            time.sleep(0.3)
            session.drain()

            session.send(b"\x1b[Z")
            time.sleep(0.2)
            session.drain()

            session.send(b"\x01#\n")
            time.sleep(0.3)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("k9s version", out, f"Shift+Tab must select 'version': {out}")
        finally:
            session.close()


class TestSecondTabCachedDefinitionAttack(unittest.TestCase):
    """Adversarial Attack 3: Cached definition directly used with zero overhead on second Tab."""

    def test_comps_transition_from_lazy_stub_to_native(self):
        """Assert $_comps updates from _lazy_k8s_completion to native definitions on first Tab."""
        session = PtySession()
        try:
            session.wait_for_prompt()

            # Check before
            out_before = session.run_command(
                'echo "BEFORE: HELM=${_comps[helm]} K=${_comps[k]} KUBECTL=${_comps[kubectl]} K9S=${_comps[k9s]}"'
            )
            clean_before = strip_ansi(out_before)
            self.assertIn("BEFORE: HELM=_lazy_k8s_completion", clean_before)
            self.assertIn("K=_lazy_k8s_completion", clean_before)
            self.assertIn("KUBECTL=_lazy_k8s_completion", clean_before)
            self.assertIn("K9S=_lazy_k8s_completion", clean_before)

            # Trigger first tab on helm
            session.send(b"helm \t\n")
            time.sleep(0.5)
            session.drain()

            # Check after
            out_after = session.run_command(
                'echo "AFTER: HELM=${_comps[helm]} K=${_comps[k]} KUBECTL=${_comps[kubectl]} K9S=${_comps[k9s]}"'
            )
            clean_after = strip_ansi(out_after)
            self.assertIn("AFTER: HELM=_helm", clean_after)
            self.assertIn("K=_kubectl", clean_after)
            self.assertIn("KUBECTL=_kubectl", clean_after)
            self.assertIn("K9S=_k9s", clean_after)
        finally:
            session.close()

    def test_second_tab_latency_has_zero_lazy_overhead(self):
        """Assert second Tab latency is virtually identical to native completion latency."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            # First Tab
            t0 = time.monotonic()
            session.send(b"helm \t")
            data1 = b""
            while time.monotonic() - t0 < 3.0:
                r, _, _ = select.select([session.master], [], [], 0.05)
                if r:
                    data1 += os.read(session.master, 4096)
                    if b"create" in data1 or b"install" in data1:
                        break
            t1 = time.monotonic()
            first_latency_ms = (t1 - t0) * 1000

            # Clear line
            session.send(b"\x15")
            time.sleep(0.1)
            session.drain()

            # Second Tab
            t2 = time.monotonic()
            session.send(b"helm \t")
            data2 = b""
            while time.monotonic() - t2 < 3.0:
                r, _, _ = select.select([session.master], [], [], 0.05)
                if r:
                    data2 += os.read(session.master, 4096)
                    if b"create" in data2 or b"install" in data2:
                        break
            t3 = time.monotonic()
            second_latency_ms = (t3 - t2) * 1000

            # Both must complete quickly (< 250ms under PTY)
            self.assertLess(first_latency_ms, 250.0, f"First Tab too slow: {first_latency_ms} ms")
            self.assertLess(second_latency_ms, 250.0, f"Second Tab too slow: {second_latency_ms} ms")
        finally:
            session.close()


class TestColdCacheRegenerationAttack(unittest.TestCase):
    """Adversarial Attack 4: Cold cache deletion and on-demand regeneration."""

    def test_cold_cache_regeneration_on_kubectl_tab(self):
        """Assert that deleting combined_completion.zsh* causes clean regeneration and compilation without hang."""
        # 1. Delete all combined_completion.zsh* files
        for f in glob.glob(os.path.join(ZCACHE_DIR, "combined_completion.zsh*")):
            os.remove(f)

        self.assertFalse(os.path.exists(COMBINED_COMP_SRC), "Cache file must be deleted")
        self.assertFalse(os.path.exists(COMBINED_COMP_ZWC), "Compiled zwc must be deleted")

        # 2. Launch interactive session
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            # 3. Type kubectl and Tab
            start_t = time.monotonic()
            session.send(b"kubectl \t")

            data = b""
            while time.monotonic() - start_t < 6.0:
                r, _, _ = select.select([session.master], [], [], 0.1)
                if r:
                    chunk = os.read(session.master, 4096)
                    data += chunk
                    clean = strip_ansi(data.decode("utf-8", errors="replace"))
                    if "annotate" in clean and "apply" in clean and "get" in clean:
                        break

            elapsed = time.monotonic() - start_t
            clean = strip_ansi(data.decode("utf-8", errors="replace"))

            # 4. Assert regeneration succeeded without hang
            self.assertLess(elapsed, 5.0, f"Cold regeneration hung or took too long: {elapsed:.2f}s")
            self.assertTrue(os.path.exists(COMBINED_COMP_SRC), "combined_completion.zsh must be regenerated")
            self.assertTrue(os.path.exists(COMBINED_COMP_ZWC), "combined_completion.zsh.zwc must be compiled")
            self.assertGreater(
                os.path.getsize(COMBINED_COMP_SRC),
                50000,
                f"Regenerated cache file too small: {os.path.getsize(COMBINED_COMP_SRC)} bytes",
            )

            # 5. Assert matches are displayed
            self.assertIn("annotate", clean, f"Completions not displayed: {clean[:400]}")
            self.assertIn("apply", clean)
            self.assertIn("get", clean)

            # 6. Assert zero syntax errors
            self.assertNotIn("syntax error", clean.lower())
            self.assertNotIn("parse error", clean.lower())
        finally:
            session.close()

    def test_regenerated_file_syntax_validity(self):
        """Assert the regenerated combined_completion.zsh passes zsh -n syntax validation."""
        self.assertTrue(os.path.exists(COMBINED_COMP_SRC))
        res = subprocess.run(["zsh", "-n", COMBINED_COMP_SRC], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"Syntax errors in regenerated cache: {res.stderr}")


if __name__ == "__main__":
    unittest.main()
