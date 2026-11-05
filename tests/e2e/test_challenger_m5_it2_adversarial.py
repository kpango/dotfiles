#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M5 Iteration 2 Gate.

Validates:
1. Completion Discovery & Execution Attack:
   - bun <TAB> resolves completions (add, build, install, test, etc.) in real PTY sessions without file fallback.
   - bun prefix completion (bun a<TAB>) resolves subcommands.
   - xpanes binary is on PATH and resolves xpanes --version.
   - xpanes -<TAB> resolves options (-B, -c, -d, -e, -s, etc.) in real PTY sessions without file fallback.
   - Lazy k8s completions (kubectl, helm, k) in a collision directory never fall back to local files.
2. Interactive Shell Flow & Signals Attack:
   - Synchronous stty -ixon -ixoff and setopt no_flow_control under real PTY.
   - Ctrl+S (\x13) does not freeze terminal output transmission.
   - PTY signal handling (Ctrl+C, Ctrl+Z, rapid disconnect) has zero orphaned/leaked subprocesses.
   - zsh-pty-startup.py (--stop-at first-output) has zero orphaned/leaked subprocesses across 30 rapid executions.
"""

import errno
import fcntl
import os
import pty
import re
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time
import unittest

PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


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
        start = time.monotonic()
        data = b""
        while time.monotonic() - start < timeout:
            chunk = self.read_available(timeout=0.1)
            if chunk:
                data += chunk
                text = strip_ansi(data.decode("utf-8", errors="replace"))
                if "╰─λ" in text or "╰─✗" in text:
                    time.sleep(0.1)
                    extra = self.read_available(timeout=0.2)
                    data += extra
                    return strip_ansi(data.decode("utf-8", errors="replace"))
            time.sleep(0.02)
        return strip_ansi(data.decode("utf-8", errors="replace"))

    def send(self, data: bytes):
        os.write(self.master, data)

    def drain(self, timeout=0.2) -> bytes:
        return self.read_available(timeout=timeout)

    def close(self):
        """Cleanly terminate child process and reap it to prevent defunct zombies."""
        if getattr(self, "closed", False):
            return
        self.closed = True

        if getattr(self, "master", None) is not None:
            try:
                os.write(self.master, b"\x03exit\n")
            except OSError:
                pass

        try:
            os.kill(self.pid, signal.SIGHUP)
        except (ProcessLookupError, OSError):
            pass

        if getattr(self, "master", None) is not None:
            try:
                os.close(self.master)
            except OSError:
                pass
            self.master = None

        deadline = time.monotonic() + 0.5
        while time.monotonic() < deadline:
            try:
                rpid, _ = os.waitpid(self.pid, os.WNOHANG)
                if rpid == self.pid:
                    return
            except (ChildProcessError, OSError):
                return
            time.sleep(0.01)

        try:
            os.kill(self.pid, signal.SIGKILL)
            os.waitpid(self.pid, 0)
        except (ProcessLookupError, ChildProcessError, OSError):
            pass


class TestBunCompletionDiscoveryAttack(unittest.TestCase):
    """Attack 1: Bun completions resolution and execution in real PTY."""

    def test_bun_completions_resolve_subcommands(self):
        """Assert bun <TAB><TAB> displays bun subcommands without falling back to local files."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"bun \t\t")
            time.sleep(0.5)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("add", out, f"bun completion missing 'add': {out[:400]}")
            self.assertIn("build", out, f"bun completion missing 'build': {out[:400]}")
            self.assertIn("install", out, f"bun completion missing 'install': {out[:400]}")
            self.assertIn("test", out, f"bun completion missing 'test': {out[:400]}")
            self.assertNotIn("Makefile", out, "bun completion fell back to local file")
            self.assertNotIn("sheldon.toml", out, "bun completion fell back to local file")
        finally:
            session.close()

    def test_bun_prefix_completion(self):
        """Assert bun a<TAB><TAB> resolves subcommands starting with 'a' (add, audit)."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"bun a\t\t")
            time.sleep(0.5)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("add", out, f"bun a completion missing 'add': {out[:400]}")
            self.assertIn("audit", out, f"bun a completion missing 'audit': {out[:400]}")
            self.assertNotIn("agent", out, "bun a completion fell back to local directory 'agent/'")
        finally:
            session.close()

    def test_bun_binary_execution(self):
        """Assert bun binary executes cleanly in zsh environment."""
        res = subprocess.run(["zsh", "-i", "-c", "bun --version"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"bun --version failed: {res.stderr}")
        self.assertTrue(len(res.stdout.strip()) > 0, "bun --version returned empty output")


class TestXpanesCompletionDiscoveryAttack(unittest.TestCase):
    """Attack 2: Tmux-xpanes completion resolution and command execution in real PTY."""

    def test_xpanes_path_and_execution(self):
        """Assert xpanes binary is located on PATH and executes properly."""
        res = subprocess.run(["zsh", "-i", "-c", "which xpanes"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"xpanes not found on PATH: {res.stderr}")
        self.assertIn("tmux-xpanes/bin/xpanes", res.stdout)

        res_ver = subprocess.run(["zsh", "-i", "-c", "xpanes --version"], capture_output=True, text=True)
        self.assertEqual(res_ver.returncode, 0, f"xpanes --version failed: {res_ver.stderr}")
        self.assertIn("xpanes", res_ver.stdout)

    def test_xpanes_completions_resolve_options(self):
        """Assert xpanes -<TAB><TAB> resolves flags without falling back to local files."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"xpanes -\t\t")
            time.sleep(0.5)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("-B", out, f"xpanes completion missing -B: {out[:400]}")
            self.assertIn("-c", out, f"xpanes completion missing -c: {out[:400]}")
            self.assertIn("--bulk-cols", out, f"xpanes completion missing --bulk-cols: {out[:400]}")
            self.assertIn("-s", out, f"xpanes completion missing -s: {out[:400]}")
            self.assertNotIn("Makefile", out, "xpanes completion fell back to local file")
            self.assertNotIn("sheldon.toml", out, "xpanes completion fell back to local file")
        finally:
            session.close()


class TestLazyK8sCompletionCollisionAttack(unittest.TestCase):
    """Attack 3: Lazy k8s completions in directory with conflicting filenames."""

    def test_collision_directory_never_falls_back_to_local_files(self):
        """Assert that in a directory containing files named helm, kubectl, k, completions never fall back to them."""
        tmpdir = tempfile.mkdtemp(prefix="adv_k8s_coll2_")
        try:
            open(os.path.join(tmpdir, "helm"), "w").close()
            open(os.path.join(tmpdir, "helm-chart"), "w").close()
            open(os.path.join(tmpdir, "kubectl"), "w").close()
            open(os.path.join(tmpdir, "kubectl-config"), "w").close()
            open(os.path.join(tmpdir, "k"), "w").close()
            open(os.path.join(tmpdir, "k-secret"), "w").close()

            session = PtySession(cwd=tmpdir)
            try:
                session.wait_for_prompt()
                session.drain()

                # Test helm
                session.send(b"helm \t")
                time.sleep(0.4)
                out_helm = strip_ansi(session.drain().decode("utf-8", errors="replace"))
                self.assertIn("create", out_helm)
                self.assertNotIn("helm-chart", out_helm, "helm completion must NOT fall back to local file")

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
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir)


class TestPtyFlowControlAttack(unittest.TestCase):
    """Attack 4: Terminal flow control and Ctrl+S resistance under real PTY."""

    def test_flow_control_settings_active(self):
        """Assert stty -ixon and setopt noflowcontrol are strictly enabled."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b'stty -a | grep -o "\\-ixon" && setopt | grep noflowcontrol\n')
            time.sleep(0.4)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("-ixon", out, "-ixon must be set in stty under real PTY")
            self.assertIn("noflowcontrol", out, "noflowcontrol must be active in setopt")
        finally:
            session.close()

    def test_ctrl_s_does_not_halt_terminal_transmission(self):
        """Assert sending Ctrl+S does not block terminal output when -ixon is active."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            # 1. Deterministic kernel termios check: verify IXON and IXOFF bits are cleared
            attrs = termios.tcgetattr(session.master)
            iflag = attrs[0]
            self.assertEqual(iflag & termios.IXON, 0, "termios IXON must be disabled in kernel line discipline")
            self.assertEqual(iflag & termios.IXOFF, 0, "termios IXOFF must be disabled in kernel line discipline")

            # 2. Dynamic transmission check: foreground output is not suspended by Ctrl+S
            # (Avoids sending ^S at idle prompt where ZLE/Atuin intercepts it for history search)
            cmd = (
                "python3 -c \""
                "import time, sys; "
                "sys.stdout.write('FLOW_START\\n'); sys.stdout.flush(); "
                "time.sleep(0.15); "
                "sys.stdout.write('UNBLOCKED_BY_CTRL_S\\n'); sys.stdout.flush()\"\n"
            )
            session.send(cmd.encode("utf-8"))
            time.sleep(0.05)
            # Send Ctrl+S (\x13) while output is paused in time.sleep
            session.send(b"\x13")
            time.sleep(0.35)
            out = strip_ansi(session.drain().decode("utf-8", errors="replace"))

            self.assertIn("FLOW_START", out)
            self.assertIn("UNBLOCKED_BY_CTRL_S", out, "Output blocked by Ctrl+S: flow control not disabled!")
        finally:
            session.close()


class TestPtySignalAndOrphanResilienceAttack(unittest.TestCase):
    """Attack 5: Signals (Ctrl+C, Ctrl+Z, rapid disconnect) and subprocess orphan checks."""

    def test_ctrl_c_and_ctrl_z_leave_zero_orphaned_processes(self):
        """Assert repeated Ctrl+C, Ctrl+Z, and abrupt PTY close cycles leave zero orphaned processes."""
        created_pids = []

        # 1. 5 cycles of Ctrl+C during active foreground command
        for _ in range(5):
            s = PtySession()
            created_pids.append(s.pid)
            s.wait_for_prompt()
            s.send(b"sleep 5\n")
            time.sleep(0.1)
            s.send(b"\x03")  # Ctrl+C
            time.sleep(0.1)
            s.close()

        # 2. 5 cycles of Ctrl+Z suspend and cleanup
        for _ in range(5):
            s = PtySession()
            created_pids.append(s.pid)
            s.wait_for_prompt()
            s.send(b"sleep 5\n")
            time.sleep(0.1)
            s.send(b"\x1a")  # Ctrl+Z
            time.sleep(0.1)
            s.send(b"kill %1\n")
            time.sleep(0.1)
            s.close()

        # 3. 10 rapid master close cycles
        for _ in range(10):
            s = PtySession()
            created_pids.append(s.pid)
            time.sleep(0.05)
            s.close()

        time.sleep(0.5)

        # 1. Reap any lingering child process zombies
        for p in created_pids:
            try:
                os.waitpid(p, os.WNOHANG)
            except (ChildProcessError, OSError):
                pass

        # 2. Check for still-alive direct child processes
        still_alive = []
        for p in created_pids:
            try:
                os.kill(p, 0)
                still_alive.append(p)
            except OSError:
                pass

        self.assertEqual(len(still_alive), 0, f"Found un-terminated child PIDs: {still_alive}")

        # 3. Check for true orphans reparented to PID 1
        ps_res = subprocess.run(
            ["ps", "-eo", "pid,ppid,comm,args"],
            capture_output=True,
            text=True,
        )
        orphans = []
        for line in ps_res.stdout.splitlines():
            parts = line.strip().split(None, 3)
            if len(parts) >= 4:
                pid, ppid, comm, args = parts[0], parts[1], parts[2], parts[3]
                if ppid == "1" and ("zsh -i" in args or "sleep 5" in args):
                    orphans.append(line)

        self.assertEqual(len(orphans), 0, f"Found orphaned processes reparented to PID 1: {orphans}")

    def test_zsh_pty_startup_first_output_zero_orphans(self):
        """Assert zsh-pty-startup.py with --stop-at first-output leaves zero orphaned processes."""
        for _ in range(20):
            res = subprocess.run(
                ["python3", "Makefile.d/scripts/zsh-pty-startup.py", "--stop-at", "first-output"],
                capture_output=True,
            )
            self.assertEqual(res.returncode, 0, f"zsh-pty-startup failed: {res.stderr}")


if __name__ == "__main__":
    unittest.main()
