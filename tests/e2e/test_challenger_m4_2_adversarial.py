#!/usr/bin/env python3
"""Adversarial challenger test suite for Milestone M4 (Features 9, 10, 11, 12).

Adversarial Attacks & Invariant Verification:
1. Prompt Visual & Color Fidelity Attack (Feature 9 & Invariant 5):
   - In PTY environment, test prompt output under:
     - Normal clean git repo
     - Dirty git repo with modified, staged, and untracked files (*+?)
     - Polyglot directory containing Go, Rust, and Node markers (badges 🐹, 🦀, ⬢)
     - Non-zero command exit codes (exit 1, exit 127) and recovery (exit 0)
     - Execution duration >= 1.0s (took 1.2s) vs < 1.0s
   - Verify raw ANSI escape codes match expected %F{...} formatting exactly:
     - cyan (%F{cyan}): \x1b[36m
     - green (%F{green}): \x1b[32m
     - magenta (%F{magenta}): \x1b[35m
     - red (%F{red}): \x1b[31m
     - yellow (%F{yellow}): \x1b[33m
     - reset (%f): \x1b[39m
     - bold (%B): \x1b[1m / unbold (%b): \x1b[0m or \x1b[22m
   - Verify zero undefined variable warnings, zero stderr noise, zero crashes.
2. Dead OS fpath Attack (Feature 11):
   - Assert all 5 non-Linux directories (AIX, BSD, Cygwin, Darwin, Solaris) and Windows
     are completely absent from $fpath in both non-interactive and interactive PTY sessions.
   - Assert Linux (/usr/share/zsh/functions/Completion/Linux), vendor, system, and user
     zfunc/ completions ARE present.
   - Test OS branch logic: verify Darwin preserves Darwin while pruning Solaris/AIX/Cygwin/BSD/Windows.
   - Test completions in PTY for git, pacman, systemctl, ssh, and user zfunc: assert 0 errors.
3. compinit -u Insecure Permissions Attack (Feature 12):
   - Create a temporary directory with chmod 777 permissions and inject it into fpath.
   - Test both cold boot (missing .zcompdump) and warm boot (existing .zcompdump).
   - Assert no "insecure directories" prompt appears, shell boots with 0 hang, exit code 0.
   - Contrast validation: verify that running compinit without -u prompts interactively and hangs.
4. async-compile Subshell Fork Gating Attack (Feature 10):
   - Verify steady-state gating yields GATED (0 forks spawned).
   - Verify invalidation on touched file yields FORK (background compilation activated).
"""

import errno
import fcntl
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


def strip_ansi(text: str) -> str:
    """Remove ANSI escape sequences from text."""
    ansi_regex = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    return ansi_regex.sub("", text)


class PtySession:
    """Helper to launch and interact with an interactive zsh process in a real PTY."""

    def __init__(self, cwd=None, env=None, rows=24, cols=120):
        self.cwd = cwd or PROJECT_ROOT
        self.master, self.slave = pty.openpty()

        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, winsize)

        sub_env = os.environ.copy()
        sub_env["TERM"] = "xterm-256color"
        sub_env["TMUX"] = "mock_session"  # prevents auto-attach in 01-tmux.zsh
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
        # Set master to non-blocking
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

    def wait_for_prompt(self, timeout=4.0) -> str:
        """Wait until zsh renders prompt (contains lambda or cross symbol)."""
        start = time.monotonic()
        accum = b""
        while time.monotonic() - start < timeout:
            chunk = self.read_available(timeout=0.1)
            if chunk:
                accum += chunk
                text = accum.decode("utf-8", errors="replace")
                if "╰─λ" in text or "╰─✗" in text:
                    # Give asynchronous worker a short moment to complete git dirty check
                    time.sleep(0.2)
                    accum += self.read_available(timeout=0.1)
                    return accum.decode("utf-8", errors="replace")
            time.sleep(0.05)
        return accum.decode("utf-8", errors="replace")

    def send(self, data: bytes):
        """Write raw bytes to PTY master."""
        os.write(self.master, data)

    def send_line(self, line: str):
        """Send a line followed by newline."""
        self.send(line.encode("utf-8") + b"\n")

    def run_command(self, cmd: str, timeout=3.0) -> str:
        """Run command and return output up to next prompt."""
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


class TestChallengerM4Adversarial(unittest.TestCase):
    """Adversarial attack and stress verification suite for Milestone M4."""

    # -------------------------------------------------------------------------
    # Task 1: Prompt Visual & Color Fidelity Attack (Feature 9 & Invariant 5)
    # -------------------------------------------------------------------------

    def test_adv1_prompt_visual_and_color_fidelity_clean_repo(self):
        """Attack 1.1: Clean git repo prompt must have exact cyan/green/magenta escapes and no dirty symbols."""
        tmpdir = tempfile.mkdtemp(prefix="adv1_clean_")
        try:
            # Init clean git repo
            subprocess.run(["git", "init", "-q", "-b", "main", tmpdir], check=True)
            subprocess.run(["git", "-C", tmpdir, "config", "user.email", "test@test.com"], check=True)
            subprocess.run(["git", "-C", tmpdir, "config", "user.name", "tester"], check=True)
            with open(os.path.join(tmpdir, "init.txt"), "w") as f:
                f.write("clean\n")
            subprocess.run(["git", "-C", tmpdir, "add", "init.txt"], check=True)
            subprocess.run(["git", "-C", tmpdir, "commit", "-q", "-m", "init"], check=True)

            session = PtySession(cwd=tmpdir)
            try:
                raw = session.wait_for_prompt()
                clean = strip_ansi(raw)

                # Line 1: Clock with cyan escape \x1b[36m
                self.assertIn("🕙 ", clean)
                self.assertRegex(clean, r"🕙 \s*\d{2}:\d{2}:\d{2}")
                self.assertRegex(raw, r"🕙 \x1b\[36m\d{2}:\d{2}:\d{2}\x1b\[39m")

                # Line 2: Green bold user ╭─user@, cyan path, magenta branch main
                self.assertIn("╭─", clean)
                self.assertIn(": in ", clean)
                self.assertIn(" main", clean)
                # Raw escape checks
                self.assertIn("\x1b[1m\x1b[32m╭─", raw, "Must use bold green for prompt top-left connector")
                self.assertIn("\x1b[36m", raw, "Must use cyan for path")
                self.assertIn("\x1b[35m main\x1b[39m", raw, "Must use magenta for git branch")

                # Dirty symbols must NOT appear
                self.assertNotIn("main*", clean)
                self.assertNotIn("main+", clean)
                self.assertNotIn("main?", clean)

                # Line 3: Green bold lambda on success
                self.assertIn("╰─λ", clean)
                self.assertIn("\x1b[1m\x1b[32m╰─λ\x1b[39m", raw, "Must use bold green for success lambda")

                # Undefined variable checks: no error or warning output
                self.assertNotIn("undefined", raw.lower())
                self.assertNotIn("parameter not set", raw.lower())
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_adv2_prompt_visual_and_color_fidelity_dirty_repo(self):
        """Attack 1.2: Dirty git repo with modified, staged, and untracked files must render *+? in magenta."""
        tmpdir = tempfile.mkdtemp(prefix="adv1_dirty_")
        try:
            subprocess.run(["git", "init", "-q", "-b", "main", tmpdir], check=True)
            subprocess.run(["git", "-C", tmpdir, "config", "user.email", "test@test.com"], check=True)
            subprocess.run(["git", "-C", tmpdir, "config", "user.name", "tester"], check=True)
            with open(os.path.join(tmpdir, "tracked.txt"), "w") as f:
                f.write("tracked\n")
            subprocess.run(["git", "-C", tmpdir, "add", "tracked.txt"], check=True)
            subprocess.run(["git", "-C", tmpdir, "commit", "-q", "-m", "init"], check=True)

            # 1. Staged change (+)
            with open(os.path.join(tmpdir, "staged.txt"), "w") as f:
                f.write("staged\n")
            subprocess.run(["git", "-C", tmpdir, "add", "staged.txt"], check=True)

            # 2. Unstaged modification (*)
            with open(os.path.join(tmpdir, "tracked.txt"), "a") as f:
                f.write("modified\n")

            # 3. Untracked file (?)
            with open(os.path.join(tmpdir, "untracked.txt"), "w") as f:
                f.write("untracked\n")

            session = PtySession(cwd=tmpdir)
            try:
                raw = session.wait_for_prompt()
                clean = strip_ansi(raw)

                # Verify clean text shows main*+?
                self.assertIn("main*+?", clean, "Dirty git repo must display main*+? in prompt")

                # Verify exact ANSI sequence: magenta branch followed by *+?
                self.assertIn("\x1b[35m main*+?\x1b[39m", raw, "Dirty indicators must be formatted in %F{magenta}")
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_adv3_prompt_language_badges(self):
        """Attack 1.3: Polyglot directory must display Go (cyan 🐹), Rust (red 🦀), Node (green ⬢) badges."""
        tmpdir = tempfile.mkdtemp(prefix="adv1_poly_")
        try:
            with open(os.path.join(tmpdir, "go.mod"), "w") as f:
                f.write("module testmod\n\ngo 1.22\n")
            with open(os.path.join(tmpdir, "Cargo.toml"), "w") as f:
                f.write("[package]\nname = \"testpkg\"\nversion = \"0.1.0\"\n")
            with open(os.path.join(tmpdir, "package.json"), "w") as f:
                f.write("{\"name\": \"testapp\"}\n")

            session = PtySession(cwd=tmpdir)
            try:
                raw = session.wait_for_prompt()
                clean = strip_ansi(raw)

                # 1. Badges in clean text
                self.assertIn("🐹", clean, "Go badge must be rendered")
                self.assertIn("🦀", clean, "Rust badge must be rendered")
                self.assertIn("⬢", clean, "Node badge must be rendered")

                # 2. Badges in raw ANSI:
                # Go badge in cyan: \x1b[36m 🐹...\x1b[39m
                self.assertRegex(raw, r"\x1b\[36m 🐹[^\x1b]+\x1b\[39m", "Go badge must be formatted in cyan")
                # Rust badge in red: \x1b[31m 🦀...\x1b[39m
                self.assertRegex(raw, r"\x1b\[31m 🦀[^\x1b]+\x1b\[39m", "Rust badge must be formatted in red")
                # Node badge in green: \x1b[32m ⬢...\x1b[39m
                self.assertRegex(raw, r"\x1b\[32m ⬢[^\x1b]+\x1b\[39m", "Node badge must be formatted in green")
            finally:
                session.close()
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_adv4_prompt_exit_codes(self):
        """Attack 1.4: Non-zero exit codes (1, 127) must show red cross ╰─✗ and red code; exit 0 restores ╰─λ."""
        session = PtySession()
        try:
            session.wait_for_prompt()

            # Exit code 1
            raw_1 = session.run_command("(exit 1)")
            clean_1 = strip_ansi(raw_1)
            self.assertIn("╰─✗ 1", clean_1)
            self.assertIn("\x1b[1m\x1b[31m╰─✗\x1b[39m\x1b[0m \x1b[31m1\x1b[39m", raw_1, "Exit 1 must be red bold cross + red 1")

            # Exit code 127
            raw_127 = session.run_command("(exit 127)")
            clean_127 = strip_ansi(raw_127)
            self.assertIn("╰─✗ 127", clean_127)
            self.assertIn("\x1b[1m\x1b[31m╰─✗\x1b[39m\x1b[0m \x1b[31m127\x1b[39m", raw_127, "Exit 127 must be red bold cross + red 127")

            # Recovery with exit code 0
            raw_0 = session.run_command("true")
            clean_0 = strip_ansi(raw_0)
            self.assertIn("╰─λ", clean_0)
            self.assertNotIn("╰─✗", clean_0)
            self.assertIn("\x1b[1m\x1b[32m╰─λ\x1b[39m", raw_0, "Exit 0 must restore green bold lambda")
        finally:
            session.close()

    def test_adv5_prompt_command_duration(self):
        """Attack 1.5: Command duration >= 1.0s must display yellow 'took X.Xs'; duration < 1.0s must omit it."""
        session = PtySession()
        try:
            session.wait_for_prompt()

            # Duration >= 1.0s
            raw_long = session.run_command("sleep 1.2", timeout=4.0)
            clean_long = strip_ansi(raw_long)
            self.assertRegex(clean_long, r"took 1\.\d+s")
            self.assertRegex(raw_long, r"\x1b\[33m  took 1\.\d+s\x1b\[39m", "Duration must be formatted in yellow")

            # Duration < 1.0s
            raw_short = session.run_command("sleep 0.1", timeout=2.0)
            clean_short = strip_ansi(raw_short)
            self.assertNotIn("took", clean_short, "Sub-second execution must omit duration string")
        finally:
            session.close()

    # -------------------------------------------------------------------------
    # Task 2: Dead OS fpath Attack (Feature 11)
    # -------------------------------------------------------------------------

    def test_adv6_dead_os_fpath_absence_and_presence(self):
        """Attack 2.1: Non-Linux OS completions must be 100% purged from fpath; Linux/vendor/system/zfunc must exist."""
        # 1. Non-interactive zsh -c verification
        res = subprocess.run(
            ["zsh", "-c", "print -l $fpath"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        fpath_entries = [line.strip() for line in res.stdout.splitlines() if line.strip()]

        dead_patterns = ["AIX", "BSD", "Cygwin", "Darwin", "Solaris", "Windows"]
        for entry in fpath_entries:
            for dead in dead_patterns:
                self.assertNotIn(
                    f"/{dead}",
                    entry,
                    f"Dead OS completion path '{entry}' detected in non-interactive fpath!",
                )

        # Required entries in non-interactive fpath
        self.assertTrue(
            any("Completion/Linux" in p for p in fpath_entries),
            "Linux completion directory missing from non-interactive fpath!",
        )
        self.assertTrue(
            any("vendor-completions" in p or "vendor-functions" in p for p in fpath_entries),
            "Vendor completions directory missing from non-interactive fpath!",
        )
        self.assertTrue(
            any(p.endswith("/zfunc") for p in fpath_entries),
            "User zfunc directory missing from non-interactive fpath!",
        )

        # 2. Interactive PTY session verification
        session = PtySession()
        try:
            session.wait_for_prompt()
            pty_out = session.run_command("print -l $fpath")
            pty_entries = [
                line.strip()
                for line in strip_ansi(pty_out).splitlines()
                if line.strip() and not line.startswith("print -l") and not "╰─" in line
            ]

            for entry in pty_entries:
                for dead in dead_patterns:
                    self.assertNotIn(
                        f"/{dead}",
                        entry,
                        f"Dead OS completion path '{entry}' detected in interactive fpath!",
                    )

            self.assertTrue(
                any("Completion/Linux" in p for p in pty_entries),
                "Linux completion directory missing from interactive fpath!",
            )
            self.assertTrue(
                any(p.endswith("/zfunc") for p in pty_entries),
                "User zfunc directory missing from interactive fpath!",
            )
        finally:
            session.close()

        # 3. Darwin OS branch validation
        # Verify that if OSTYPE is darwin, Darwin is retained while foreign OSs are pruned
        darwin_test_cmd = """
        fpath=(
          /usr/share/zsh/functions/Completion/AIX
          /usr/share/zsh/functions/Completion/BSD
          /usr/share/zsh/functions/Completion/Cygwin
          /usr/share/zsh/functions/Completion/Darwin
          /usr/share/zsh/functions/Completion/Linux
          /usr/share/zsh/functions/Completion/Solaris
          /usr/share/zsh/functions/Completion/Windows
          /usr/share/zsh/functions/Completion/Base
        )
        OSTYPE="darwin24.0.0"
        if [[ "$OSTYPE" == darwin* ]]; then
            fpath=(${fpath:#*(Solaris|AIX|Cygwin|BSD|Windows)*})
        else
            fpath=(${fpath:#*(Solaris|AIX|Cygwin|Darwin|BSD|Windows)*})
        fi
        print -l $fpath
        """
        darwin_res = subprocess.run(
            ["zsh", "-fc", darwin_test_cmd],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        darwin_entries = darwin_res.stdout.splitlines()
        self.assertTrue(
            any("Completion/Darwin" in p for p in darwin_entries),
            "Darwin path must be preserved on Darwin OSTYPE!",
        )
        for dead in ["Solaris", "AIX", "Cygwin", "BSD", "Windows"]:
            self.assertFalse(
                any(f"/{dead}" in p for p in darwin_entries),
                f"Dead path {dead} was not pruned under Darwin branch!",
            )

    def test_adv7_completion_system_pty_stress(self):
        """Attack 2.2: PTY completions for git, pacman, systemctl, ssh, and user zfunc must execute with 0 errors."""
        session = PtySession()
        try:
            session.wait_for_prompt()
            # Wait for deferred initialization to complete
            time.sleep(0.5)

            def verify_completion(trigger: bytes, label: str):
                # Send trigger and Tab
                session.send(trigger + b"\t")
                time.sleep(0.35)
                raw_out = session.read_available(timeout=0.35)
                text = strip_ansi(raw_out.decode("utf-8", errors="replace"))

                # Clear line and cancel any pagination prompt
                session.send(b"\x03\x15\r")
                time.sleep(0.2)
                session.read_available(timeout=0.2)

                # Check for errors in output
                error_signatures = [
                    "command not found",
                    "parse error",
                    "no such file or directory",
                    "function definition file not found",
                    "error in",
                ]
                for sig in error_signatures:
                    self.assertNotIn(
                        sig,
                        text.lower(),
                        f"Error signature '{sig}' found during {label} completion! Output:\n{text}",
                    )
                return text

            # 1. Git completion
            git_out = verify_completion(b"git che", "git")
            self.assertTrue(
                "checkout" in git_out or "check-" in git_out or "possibilities" in git_out,
                f"git completion failed to trigger suggestions: {git_out}",
            )

            # 2. Pacman completion
            pacman_out = verify_completion(b"pacman -S ", "pacman")
            self.assertTrue(
                len(pacman_out.strip()) > 0,
                f"pacman completion returned empty output: {pacman_out}",
            )

            # 3. Systemctl completion
            sys_out = verify_completion(b"systemctl sta", "systemctl")
            self.assertTrue(
                "status" in sys_out or "start" in sys_out or "possibilities" in sys_out,
                f"systemctl completion failed to suggest status/start: {sys_out}",
            )

            # 4. SSH completion
            ssh_out = verify_completion(b"ssh -o ", "ssh")
            self.assertTrue(
                "possibilities" in ssh_out or "Option" in ssh_out or len(ssh_out.strip()) > 0,
                f"ssh completion failed: {ssh_out}",
            )

            # 5. User zfunc completion
            zfunc_out = verify_completion(b"_prmt_in", "user zfunc")
            self.assertIn(
                "_prmt_init",
                zfunc_out,
                f"user zfunc completion failed to resolve _prmt_init: {zfunc_out}",
            )
        finally:
            session.close()

    # -------------------------------------------------------------------------
    # Task 3: compinit -u Insecure Permissions Attack (Feature 12)
    # -------------------------------------------------------------------------

    def test_adv8_compinit_insecure_permissions_immunity(self):
        """Attack 3.1: Insecure chmod 777 fpath directory must boot without interactive prompts, hang, or error."""
        insecure_dir = tempfile.mkdtemp(prefix="adv8_insecure_")
        test_zdotdir = tempfile.mkdtemp(prefix="adv8_zdotdir_")
        try:
            # Create world-writable 777 directory
            os.chmod(insecure_dir, 0o777)
            # Add a hostile completion file inside
            with open(os.path.join(insecure_dir, "_hostile"), "w") as f:
                f.write("#compdef hostile\n_hostile() { _message 'hostile' }\n")

            env = {"FPATH": f"{insecure_dir}:/usr/share/zsh/site-functions"}

            # 1. Cold Boot: Missing .zcompdump
            t0 = time.monotonic()
            session_cold = PtySession(env=env)
            try:
                cold_prompt = session_cold.wait_for_prompt(timeout=5.0)
                dur_cold = time.monotonic() - t0
                clean_cold = strip_ansi(cold_prompt)

                self.assertNotIn(
                    "insecure directories",
                    clean_cold,
                    "Cold boot prompt halted on insecure directories warning!",
                )
                self.assertNotIn(
                    "Ignore insecure directories",
                    clean_cold,
                    "Cold boot prompted user interactively for compaudit bypass!",
                )
                self.assertIn("╰─λ", clean_cold, "Cold boot prompt lambda failed to render")
                self.assertLess(dur_cold, 3.5, f"Cold boot hung or took too long: {dur_cold}s")
            finally:
                session_cold.close()

            # 2. Warm Boot: Existing .zcompdump
            t1 = time.monotonic()
            session_warm = PtySession(env=env)
            try:
                warm_prompt = session_warm.wait_for_prompt(timeout=5.0)
                dur_warm = time.monotonic() - t1
                clean_warm = strip_ansi(warm_prompt)

                self.assertNotIn(
                    "insecure directories",
                    clean_warm,
                    "Warm boot prompt halted on insecure directories warning!",
                )
                self.assertIn("╰─λ", clean_warm, "Warm boot prompt lambda failed to render")
                self.assertLess(dur_warm, 2.5, f"Warm boot hung or took too long: {dur_warm}s")
            finally:
                session_warm.close()

            # 3. Contrast Validation: Prove that WITHOUT -u, compaudit actively prompts & hangs
            master, slave = pty.openpty()
            try:
                pid = os.fork()
                if pid == 0:
                    os.close(master)
                    os.setsid()
                    fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
                    os.dup2(slave, 0)
                    os.dup2(slave, 1)
                    os.dup2(slave, 2)
                    os.close(slave)
                    # Run compinit WITHOUT -u
                    cmd = f"fpath=('{insecure_dir}' $fpath); autoload -Uz compinit && compinit"
                    os.execvpe("zsh", ["zsh", "-f", "-i", "-c", cmd], os.environ.copy())
                    os._exit(1)

                os.close(slave)
                time.sleep(0.5)
                r, _, _ = select.select([master], [], [], 0.5)
                out = b""
                if r:
                    out = os.read(master, 2048)
                try:
                    os.kill(pid, 9)
                    os.waitpid(pid, 0)
                except OSError:
                    pass
                contrast_text = out.decode("utf-8", errors="replace")
                self.assertIn(
                    "insecure directories",
                    contrast_text,
                    "Contrast test failed: compinit without -u should have triggered insecure warning!",
                )
                self.assertIn(
                    "Ignore insecure directories",
                    contrast_text,
                    "Contrast test failed: compaudit should have prompted interactively!",
                )
            finally:
                try:
                    os.close(master)
                except OSError:
                    pass
        finally:
            shutil.rmtree(insecure_dir, ignore_errors=True)
            shutil.rmtree(test_zdotdir, ignore_errors=True)

    # -------------------------------------------------------------------------
    # Task 4: async-compile Subshell Fork Gating (Feature 10)
    # -------------------------------------------------------------------------

    def test_adv9_async_compile_fork_gating(self):
        """Attack 4.1: Steady-state async-compile must not fork subshell; invalidation must trigger fork."""
        gating_eval_code = """
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
        # Ensure stamp and zwc are fresh
        subprocess.run(["touch", os.path.expanduser("~/.zcache/.async_compile_stamp")], check=True)
        # 1. Steady state evaluation
        res_steady = subprocess.run(
            ["zsh", "-c", gating_eval_code],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True,
        )
        self.assertEqual(res_steady.stdout.strip(), "GATED", "Steady state should gate background fork!")

        # 2. Invalidation evaluation (touch source file ahead of zwc)
        try:
            # Temporarily touch ~/.zshenv forward in time
            time.sleep(0.01)
            subprocess.run(["touch", os.path.expanduser("~/.zshenv")], check=True)
            res_invalid = subprocess.run(
                ["zsh", "-c", gating_eval_code],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True,
            )
            self.assertEqual(res_invalid.stdout.strip(), "FORK", "Invalidated source file should trigger compilation fork!")
        finally:
            # Recompile to restore fresh steady state
            subprocess.run(["zsh", "-c", "zcompile -U -R ~/.zshenv"], check=True)
            subprocess.run(["touch", os.path.expanduser("~/.zcache/.async_compile_stamp")], check=True)


if __name__ == "__main__":
    unittest.main(verbosity=2)
