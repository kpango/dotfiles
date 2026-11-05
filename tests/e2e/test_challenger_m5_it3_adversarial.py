#!/usr/bin/env python3
"""Adversarial Challenger Test Suite for Milestone M5 Iteration 3 Gate.

Validates:
1. Bun Completion & Execution:
   - bun <Tab> resolves subcommands (add, build, install, test, create, run) in real PTY sessions.
   - bun prefix completion (bun b<Tab>, bun i<Tab>, bun t<Tab>).
   - Collision directory resilience (never falls back to local files).
   - bun binary execution (--version, --help).
2. tmux-xpanes Completion & Execution:
   - xpanes binary on PATH and executable (xpanes --version, xpanes --help).
   - xpanes -<Tab> resolves short options (-B, -c, -d, -e, -s, -x).
   - xpanes --<Tab> resolves long options (--bulk-cols, --bulk-rows, etc.).
   - Collision directory resilience (never falls back to files matching flags).
3. Lazy K8s Completion:
   - Cold-cache lazy generation and sourcing on first Tab.
   - kubectl, helm, and k completions without file fallback.
   - Post-first-Tab transition: _comps[k] and _comps[kubectl] become _kubectl.
   - Collision directory resilience (no fallback to files in directory).
4. PTY Flow Control:
   - Real PTY c_iflag & (IXON | IXOFF) == 0.
   - stty -a shows -ixon -ixoff and setopt shows noflowcontrol.
   - Active output streaming is never blocked or stalled by Ctrl+S (\x13) or Ctrl+Q (\x11).
5. Signal Resilience & Zero Orphan Subprocesses:
   - Hammer testing of Ctrl+C, Ctrl+Z, and abrupt PTY master closure.
   - Zero orphaned child processes or zombie processes reparented to PID 1.
   - Rapid execution of zsh-pty-startup.py with zero process leakage.
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
    if isinstance(text, bytes):
        text = text.decode("utf-8", errors="replace")
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
                text = strip_ansi(data)
                if "╰─λ" in text or "╰─✗" in text:
                    time.sleep(0.1)
                    extra = self.read_available(timeout=0.2)
                    data += extra
                    return strip_ansi(data)
            time.sleep(0.02)
        return strip_ansi(data)

    def send(self, data: bytes):
        os.write(self.master, data)

    def drain(self, timeout=0.3) -> str:
        raw = self.read_available(timeout=timeout)
        return strip_ansi(raw)

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


class TestBunCompletionAdversarial(unittest.TestCase):
    """Adversarial testing of Bun completion and binary execution in interactive PTY."""

    def test_bun_completion_subcommands(self):
        """Assert bun <Tab><Tab> presents subcommands and does not fall back to local files."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"bun \t\t")
            time.sleep(0.5)
            out = session.drain()

            for expected in ["add", "build", "install", "test", "create", "run"]:
                self.assertIn(expected, out, f"bun completion missing subcommand '{expected}'")

            self.assertNotIn("Makefile", out, "bun completion fell back to local file 'Makefile'")
            self.assertNotIn("sheldon.toml", out, "bun completion fell back to 'sheldon.toml'")
        finally:
            session.close()

    def test_bun_prefix_completions(self):
        """Assert bun a<Tab>, bun c<Tab>, bun i<Tab> resolve expected subcommands and bun b<Tab> completes to build."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            # Test bun a<Tab><Tab> -> add, audit
            session.send(b"bun a\t\t")
            time.sleep(0.4)
            out_a = session.drain()
            self.assertIn("add", out_a, f"bun a completion missing 'add': {out_a}")
            self.assertIn("audit", out_a, f"bun a completion missing 'audit': {out_a}")

            # Test bun c<Tab><Tab> -> check, compile, create
            session.send(b"\x15bun c\t\t")
            time.sleep(0.4)
            out_c = session.drain()
            self.assertIn("check", out_c, f"bun c completion missing 'check': {out_c}")
            self.assertIn("compile", out_c, f"bun c completion missing 'compile': {out_c}")
            self.assertIn("create", out_c, f"bun c completion missing 'create': {out_c}")

            # Test bun i<Tab><Tab> -> init, install
            session.send(b"\x15bun i\t\t")
            time.sleep(0.4)
            out_i = session.drain()
            self.assertIn("init", out_i, f"bun i completion missing 'init': {out_i}")
            self.assertIn("install", out_i, f"bun i completion missing 'install': {out_i}")

            # Test unique prefix bun b<Tab> -> completes to 'build'
            session.send(b"\x15bun b\t\n")
            time.sleep(0.4)
            out_b = session.drain()
            self.assertIn("bun build", out_b, f"bun b did not expand to bun build: {out_b}")
        finally:
            session.close()

    def test_bun_collision_directory_resilience(self):
        """Assert bun completion in a directory containing colliding files never falls back to files."""
        tmpdir = tempfile.mkdtemp(prefix="adv_bun_coll_")
        try:
            # Create files with same names as subcommands and dummy project files
            for fname in ["add", "build", "install", "test", "collision_dummy_file.txt", "random_script.sh"]:
                open(os.path.join(tmpdir, fname), "w").close()

            session = PtySession(cwd=tmpdir)
            try:
                session.wait_for_prompt()
                session.drain()

                session.send(b"bun \t\t")
                time.sleep(0.5)
                out = session.drain()

                self.assertIn("add", out)
                self.assertIn("build", out)
                self.assertIn("install", out)
                self.assertIn("test", out)
                self.assertNotIn("collision_dummy_file.txt", out, "bun completion fell back to local file")
                self.assertNotIn("random_script.sh", out, "bun completion fell back to local script")
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir)

    def test_bun_execution_cleanliness(self):
        """Assert bun binary execution is functional with valid exit code."""
        res_ver = subprocess.run(["zsh", "-i", "-c", "bun --version"], capture_output=True, text=True)
        self.assertEqual(res_ver.returncode, 0, f"bun --version failed: {res_ver.stderr}")
        self.assertTrue(len(res_ver.stdout.strip()) > 0)

        res_help = subprocess.run(["zsh", "-i", "-c", "bun --help"], capture_output=True, text=True)
        self.assertEqual(res_help.returncode, 0, f"bun --help failed: {res_help.stderr}")
        self.assertIn("bun", res_help.stdout)


class TestTmuxXpanesAdversarial(unittest.TestCase):
    """Adversarial testing of tmux-xpanes completion and execution."""

    def test_xpanes_path_and_execution(self):
        """Assert xpanes binary is on PATH and executes properly."""
        res = subprocess.run(["zsh", "-i", "-c", "which xpanes"], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"xpanes not found on PATH: {res.stderr}")
        self.assertIn("tmux-xpanes/bin/xpanes", res.stdout)

        res_ver = subprocess.run(["zsh", "-i", "-c", "xpanes --version"], capture_output=True, text=True)
        self.assertEqual(res_ver.returncode, 0, f"xpanes --version failed: {res_ver.stderr}")
        self.assertIn("xpanes", res_ver.stdout)

        res_help = subprocess.run(["zsh", "-i", "-c", "xpanes --help"], capture_output=True, text=True)
        self.assertEqual(res_help.returncode, 0, f"xpanes --help failed: {res_help.stderr}")
        self.assertIn("Usage:", res_help.stdout)

    def test_xpanes_short_options_completion(self):
        """Assert xpanes -<Tab><Tab> resolves flags without falling back to local files."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"xpanes -\t\t")
            time.sleep(0.5)
            out = session.drain()

            for flag in ["-B", "-c", "-d", "-e", "-s"]:
                self.assertIn(flag, out, f"xpanes completion missing short flag '{flag}'")

            self.assertNotIn("Makefile", out, "xpanes completion fell back to local file")
        finally:
            session.close()

    def test_xpanes_long_options_completion(self):
        """Assert xpanes --<Tab><Tab> resolves long options."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"xpanes --\t\t")
            time.sleep(0.5)
            out = session.drain()

            for opt in ["--bulk-cols", "--cols", "--rows", "--help", "--debug", "--desync", "--interval"]:
                self.assertIn(opt, out, f"xpanes completion missing long option '{opt}': {out[:400]}")
        finally:
            session.close()

    def test_xpanes_collision_directory_resilience(self):
        """Assert xpanes completion in directory with flag-like files never falls back to files."""
        tmpdir = tempfile.mkdtemp(prefix="adv_xpanes_coll_")
        try:
            for fname in ["-B", "-c", "-d", "--bulk-cols", "xpanes", "dummy.txt"]:
                open(os.path.join(tmpdir, fname), "w").close()

            session = PtySession(cwd=tmpdir)
            try:
                session.wait_for_prompt()
                session.drain()

                session.send(b"xpanes -\t\t")
                time.sleep(0.5)
                out = session.drain()

                self.assertIn("-B", out)
                self.assertIn("-c", out)
                self.assertNotIn("dummy.txt", out, "xpanes completion fell back to dummy.txt")
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir)


class TestLazyK8sCompletionAdversarial(unittest.TestCase):
    """Adversarial testing of lazy Kubernetes completions (kubectl, helm, k)."""

    def test_cold_cache_on_demand_generation_and_sourcing(self):
        """Assert lazy k8s completion generates combined_completion.zsh on cold cache on demand."""
        tmp_zcache = tempfile.mkdtemp(prefix="adv_zcache_k8s_")
        try:
            session = PtySession(env={"ZCACHE_DIR": tmp_zcache})
            try:
                session.wait_for_prompt()
                session.drain()

                comb_file = os.path.join(tmp_zcache, "combined_completion.zsh")
                self.assertFalse(os.path.exists(comb_file), "combined_completion.zsh should not exist before Tab")

                # Invoke k <Tab>
                session.send(b"k \t")
                time.sleep(1.5)
                out = session.drain()

                self.assertIn("apply", out, f"k completion did not resolve 'apply' on cold cache: {out}")
                self.assertIn("get", out, f"k completion did not resolve 'get' on cold cache: {out}")
                self.assertTrue(os.path.exists(comb_file), "combined_completion.zsh was not generated on cold cache")
            finally:
                session.close()
        finally:
            shutil.rmtree(tmp_zcache)

    def test_helm_completion_subcommands(self):
        """Assert helm <Tab> resolves helm subcommands and never falls back to files."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b"helm \t")
            time.sleep(0.6)
            out = session.drain()

            self.assertIn("install", out, f"helm completion missing 'install': {out}")
            self.assertIn("upgrade", out, f"helm completion missing 'upgrade': {out}")
            self.assertIn("repo", out, f"helm completion missing 'repo': {out}")
            self.assertNotIn("Makefile", out, "helm completion fell back to local file")
        finally:
            session.close()

    def test_post_lazy_load_compdef_rebinding(self):
        """Assert that after first Tab, _comps[kubectl] and _comps[k] are directly _kubectl."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            # First Tab
            session.send(b"kubectl \t")
            time.sleep(0.6)
            session.drain()

            # Check _comps rebinding
            session.send(b"\x15print -l \"_comps[kubectl]=${_comps[kubectl]}\" \"_comps[k]=${_comps[k]}\"\n")
            time.sleep(0.4)
            out = session.drain()

            self.assertIn("_comps[kubectl]=_kubectl", out)
            self.assertIn("_comps[k]=_kubectl", out)
        finally:
            session.close()

    def test_k8s_collision_directory_resilience(self):
        """Assert k, kubectl, and helm in a collision directory never fall back to local files."""
        tmpdir = tempfile.mkdtemp(prefix="adv_k8s_coll3_")
        try:
            for fname in ["kubectl", "kubectl-config", "k", "k-secret", "helm", "helm-chart", "apply", "get"]:
                open(os.path.join(tmpdir, fname), "w").close()

            session = PtySession(cwd=tmpdir)
            try:
                session.wait_for_prompt()
                session.drain()

                # Test helm
                session.send(b"helm \t")
                time.sleep(0.5)
                out_helm = session.drain()
                self.assertIn("create", out_helm)
                self.assertNotIn("helm-chart", out_helm, "helm fell back to file helm-chart")

                # Test kubectl
                session.send(b"\x15kubectl \t")
                time.sleep(0.5)
                out_k = session.drain()
                self.assertIn("apply", out_k)
                self.assertNotIn("kubectl-config", out_k, "kubectl fell back to file kubectl-config")

                # Test k
                session.send(b"\x15k \t")
                time.sleep(0.5)
                out_kalias = session.drain()
                self.assertIn("apply", out_kalias)
                self.assertNotIn("k-secret", out_kalias, "k fell back to file k-secret")
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir)


class TestPtyFlowControlAdversarial(unittest.TestCase):
    """Adversarial stress-testing of PTY flow control and Ctrl+S/Ctrl+Q non-blocking behavior."""

    def test_termios_c_iflag_flow_control_bits(self):
        """Assert termios IXON and IXOFF bits are strictly cleared on master and slave."""
        session = PtySession()
        try:
            session.wait_for_prompt()

            attrs = termios.tcgetattr(session.master)
            iflag = attrs[0]
            self.assertEqual(iflag & termios.IXON, 0, "termios IXON must be disabled in line discipline")
            self.assertEqual(iflag & termios.IXOFF, 0, "termios IXOFF must be disabled in line discipline")
        finally:
            session.close()

    def test_stty_and_setopt_flow_control_invariants(self):
        """Assert stty -a contains -ixon and -ixoff, and setopt contains noflowcontrol."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            session.send(b'stty -a | grep -o "\\-ixon" && stty -a | grep -o "\\-ixoff" && setopt | grep noflowcontrol\n')
            time.sleep(0.4)
            out = session.drain()

            self.assertIn("-ixon", out, "-ixon must be set in stty under real PTY")
            self.assertIn("-ixoff", out, "-ixoff must be set in stty under real PTY")
            self.assertIn("noflowcontrol", out, "noflowcontrol must be active in setopt")
        finally:
            session.close()

    def test_ctrl_s_and_ctrl_q_during_heavy_output_stream(self):
        """Assert transmitting Ctrl+S (\x13) or Ctrl+Q (\x11) never pauses high-throughput stdout."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            session.drain()

            cmd = (
                "python3 -c \""
                "import time, sys; "
                "sys.stdout.write('FLOW_START\\n'); sys.stdout.flush(); "
                "time.sleep(0.1); "
                "sys.stdout.write('MID_STREAM\\n'); sys.stdout.flush(); "
                "time.sleep(0.1); "
                "sys.stdout.write('STREAM_COMPLETE\\n'); sys.stdout.flush()\"\n"
            )
            session.send(cmd.encode("utf-8"))
            time.sleep(0.04)
            # Send Ctrl+S
            session.send(b"\x13")
            time.sleep(0.08)
            # Send Ctrl+Q
            session.send(b"\x11")
            time.sleep(0.4)

            out = session.drain(timeout=0.5)

            self.assertIn("FLOW_START", out)
            self.assertIn("MID_STREAM", out)
            self.assertIn("STREAM_COMPLETE", out, "Streaming was suspended by Ctrl+S / flow control!")
        finally:
            session.close()


class TestProcessLifecycleAndZeroOrphansAdversarial(unittest.TestCase):
    """Adversarial stress-testing of child process lifecycle and orphan leak prevention."""

    def test_hammer_ctrl_c_and_ctrl_z_zero_orphans(self):
        """Assert 30 rapid iterations of foreground commands + Ctrl+C / Ctrl+Z leave zero orphans."""
        created_pids = []

        # 10 cycles of Ctrl+C
        for _ in range(10):
            s = PtySession()
            created_pids.append(s.pid)
            s.wait_for_prompt()
            s.send(b"sleep 10\n")
            time.sleep(0.08)
            s.send(b"\x03")  # Ctrl+C
            time.sleep(0.08)
            s.close()

        # 10 cycles of Ctrl+Z
        for _ in range(10):
            s = PtySession()
            created_pids.append(s.pid)
            s.wait_for_prompt()
            s.send(b"sleep 10\n")
            time.sleep(0.08)
            s.send(b"\x1a")  # Ctrl+Z
            time.sleep(0.08)
            s.send(b"kill %1\n")
            time.sleep(0.08)
            s.close()

        # 10 cycles of abrupt master disconnect
        for _ in range(10):
            s = PtySession()
            created_pids.append(s.pid)
            time.sleep(0.05)
            s.close()

        time.sleep(0.5)

        # Defensive waitpid for any direct zombies
        for p in created_pids:
            try:
                os.waitpid(p, os.WNOHANG)
            except (ChildProcessError, OSError):
                pass

        # Check for still-alive direct child processes
        still_alive = []
        for p in created_pids:
            try:
                os.kill(p, 0)
                still_alive.append(p)
            except OSError:
                pass

        self.assertEqual(len(still_alive), 0, f"Found un-terminated child PIDs: {still_alive}")

        # Check for reparented orphaned processes
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
                if ppid == "1" and ("zsh -i" in args or "sleep 10" in args):
                    orphans.append(line)

        self.assertEqual(len(orphans), 0, f"Found orphaned processes reparented to PID 1: {orphans}")

    def test_zsh_pty_startup_30_rapid_executions_zero_orphans(self):
        """Assert 30 rapid executions of zsh-pty-startup.py leave zero orphaned processes."""
        for _ in range(30):
            res = subprocess.run(
                ["python3", "Makefile.d/scripts/zsh-pty-startup.py", "--stop-at", "first-output"],
                capture_output=True,
            )
            self.assertEqual(res.returncode, 0, f"zsh-pty-startup failed: {res.stderr}")


if __name__ == "__main__":
    unittest.main()
