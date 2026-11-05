#!/usr/bin/env python3
"""Interactive PTY test harness validating all 5 UX and functional invariants.

Invariants tested:
1. Zsh completion UX:
   - menu select navigation
   - Shift+Tab (reverse-menu-complete)
   - strict prefix matcher-list before fuzzy
2. zsh-autosuggestions UX:
   - Right Arrow (forward-char) and End (end-of-line) full accept
   - forward-word (Alt+f) single-word accept
   - zle-line-pre-redraw is not wrapped or defined
3. Terminal flow control and options:
   - Real PTY synchronous stty -ixon -ixoff (termios IXON/IXOFF disabled)
   - setopt no_flow_control active in interactive session
   - ^S does not freeze terminal foreground output
4. Tmux status interval:
   - set -g status-interval 5 in tmux.conf.d/status.conf
   - tmux server reports status-interval 5
5. Prompt visual structure and asynchronous lifecycle:
   - 3-line visual match (time, user@host, path, branch, dirty markers, language badges, exit code)
   - took >= 1.0s execution duration reporting
   - delayed _prmt_stale_fd closing to prevent ZLE fd reuse race
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

    def read_available(self, timeout=0.3):
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

    def wait_for_prompt(self, timeout=4.0):
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
                    time.sleep(0.15)
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

    def run_command(self, cmd: str, timeout=3.0):
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


class TestUxInvariants(unittest.TestCase):
    """Test suite verifying the 5 strict UX invariants."""

    def test_invariant_1_completion_ux(self):
        """Invariant 1: Completion menu select, Shift+Tab reverse, strict prefix."""
        session = PtySession()
        try:
            session.wait_for_prompt()

            # 1. Verify zstyle ':completion:*' menu select
            out = session.run_command("zstyle -L ':completion:*' | grep 'menu select'")
            clean = strip_ansi(out)
            self.assertIn("zstyle ':completion:*' menu select", clean)

            # 2. Verify matcher-list: exact prefix first ('') then case-insensitive and partial-word
            out = session.run_command("zstyle -L ':completion:*' | grep 'matcher-list'")
            clean = strip_ansi(out)
            self.assertIn("matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'", clean)

            # 3. Verify bindkey '^[[Z' reverse-menu-complete
            out = session.run_command('bindkey "^[[Z"')
            clean = strip_ansi(out)
            self.assertIn('"^[[Z" reverse-menu-complete', clean)

            # 4. Interactive completion behavior under PTY in isolated directory
            tmpdir = tempfile.mkdtemp(prefix="dotfiles_inv1_")
            try:
                # Create two files sharing a strict common prefix
                open(os.path.join(tmpdir, "prefix_apple"), "w").close()
                open(os.path.join(tmpdir, "prefix_banana"), "w").close()

                session.send_line(f"cd {tmpdir}")
                session.wait_for_prompt()

                # Type 'ls pre' and hit Tab -> must strictly complete to 'prefix_'
                session.send(b"ls pre\t")
                time.sleep(0.2)
                tab1_out = session.read_available(timeout=0.3)
                tab1_text = strip_ansi(tab1_out.decode("utf-8", errors="replace"))
                self.assertIn("ls prefix_", tab1_text)

                # Hit Tab again -> enters menu selection
                session.send(b"\t")
                time.sleep(0.2)
                tab2_out = session.read_available(timeout=0.3)
                tab2_text = strip_ansi(tab2_out.decode("utf-8", errors="replace"))
                self.assertTrue("prefix_apple" in tab2_text or "prefix_banana" in tab2_text)

                # Hit Shift+Tab ('\x1b[Z') -> reverse-menu-complete selects the last item
                session.send(b"\x1b[Z")
                time.sleep(0.2)
                shift_tab_out = session.read_available(timeout=0.3)
                # Raw output will contain terminal standout selection for prefix_banana
                raw_shift_tab = shift_tab_out.decode("utf-8", errors="replace")
                self.assertTrue("prefix_banana" in raw_shift_tab)

                # Cancel command line with Ctrl+C
                session.send(b"\x03")
                session.wait_for_prompt()
            finally:
                shutil.rmtree(tmpdir, ignore_errors=True)
        finally:
            session.close()

    def test_invariant_2_autosuggestions_ux(self):
        """Invariant 2: Autosuggestions Right Arrow / End full accept, forward-word single word, no zle-line-pre-redraw wrap."""
        session = PtySession()
        try:
            session.wait_for_prompt()

            # 1. Verify zle-line-pre-redraw is NOT defined or wrapped
            out = session.run_command("typeset -p functions[zle-line-pre-redraw] widgets[zle-line-pre-redraw]")
            clean = strip_ansi(out)
            self.assertIn("no such variable: functions[zle-line-pre-redraw]", clean)
            self.assertIn("no such variable: widgets[zle-line-pre-redraw]", clean)

            # 2. Verify ZSH_AUTOSUGGEST_ACCEPT_WIDGETS and PARTIAL_ACCEPT_WIDGETS
            out = session.run_command('echo ACC: "${(j:,:)ZSH_AUTOSUGGEST_ACCEPT_WIDGETS}"; echo PART: "${(j:,:)ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS}"')
            clean = strip_ansi(out)
            self.assertIn("forward-char", clean)
            self.assertIn("end-of-line", clean)
            self.assertIn("forward-word", clean)

            # 3. Interactive autosuggestion accept in PTY
            # Prime history with a unique test command
            marker = f"inv2_test_{int(time.time())}"
            cmd = f"echo {marker}_wordone {marker}_wordtwo"
            session.run_command(cmd)

            # Type prefix
            prefix = f"echo {marker}_"
            session.send(prefix.encode("utf-8"))
            time.sleep(0.25)
            sugg_out = session.read_available(timeout=0.3)
            sugg_raw = sugg_out.decode("utf-8", errors="replace")
            # Autosuggestion should appear (color 90 / dim text)
            self.assertIn("wordone", sugg_raw)
            self.assertIn("wordtwo", sugg_raw)

            # Forward-word (Alt+f -> \x1bf) should accept only the first word
            session.send(b"\x1bf")
            time.sleep(0.2)
            part_out = session.read_available(timeout=0.3)
            part_clean = strip_ansi(part_out.decode("utf-8", errors="replace"))
            self.assertIn("wordone", part_clean)

            # Right Arrow (\x1b[C) should accept the remaining suggestion (full accept)
            session.send(b"\x1b[C")
            time.sleep(0.2)
            full_out = session.read_available(timeout=0.3)
            full_clean = strip_ansi(full_out.decode("utf-8", errors="replace"))
            self.assertIn("wordtwo", full_clean)

            # Clear line
            session.send(b"\x03")
            session.wait_for_prompt()

            # Test End key (\x05 -> Ctrl+E, end-of-line) accepts full suggestion
            session.send(prefix.encode("utf-8"))
            time.sleep(0.2)
            session.read_available(timeout=0.2)
            session.send(b"\x05")  # Ctrl+E / end-of-line
            time.sleep(0.2)
            end_out = session.read_available(timeout=0.3)
            end_clean = strip_ansi(end_out.decode("utf-8", errors="replace"))
            self.assertIn("wordone", end_clean)
            self.assertIn("wordtwo", end_clean)

            session.send(b"\x03")
            session.wait_for_prompt()
        finally:
            session.close()

    def test_invariant_3_flow_control_options(self):
        """Invariant 3: Real PTY synchronous stty -ixon -ixoff and setopt no_flow_control."""
        session = PtySession()
        try:
            session.wait_for_prompt()

            # 1. Inspect termios iflag on PTY master directly via kernel syscall
            attrs = termios.tcgetattr(session.master)
            iflag = attrs[0]
            self.assertEqual(iflag & termios.IXON, 0, "termios IXON must be disabled")
            self.assertEqual(iflag & termios.IXOFF, 0, "termios IXOFF must be disabled")

            # 2. Verify stty -a output reflects -ixon and -ixoff
            out = session.run_command("stty -a")
            clean = strip_ansi(out)
            self.assertIn("-ixon", clean, "stty must report -ixon")
            self.assertIn("-ixoff", clean, "stty must report -ixoff")

            # 3. Verify zsh option no_flow_control is set
            out = session.run_command('[[ -o no_flow_control ]] && echo "NO_FLOW_CONTROL_OK"')
            clean = strip_ansi(out)
            self.assertIn("NO_FLOW_CONTROL_OK", clean)

            # 4. Verify ^S (\x13) does NOT freeze a running foreground command output
            cmd = (
                "python3 -c \"import time, sys; "
                "sys.stdout.write('FLOW_LINE1\\n'); sys.stdout.flush(); "
                "time.sleep(0.15); "
                "sys.stdout.write('FLOW_LINE2\\n'); sys.stdout.flush()\"\n"
            )
            session.send(cmd.encode("utf-8"))
            time.sleep(0.05)
            # Send Ctrl+S during foreground execution
            session.send(b"\x13")
            time.sleep(0.35)
            fg_out = session.read_available(timeout=0.5)
            clean_fg = strip_ansi(fg_out.decode("utf-8", errors="replace"))
            self.assertIn("FLOW_LINE1", clean_fg)
            self.assertIn("FLOW_LINE2", clean_fg)
        finally:
            session.close()

    def test_invariant_4_tmux_status_interval(self):
        """Invariant 4: set -g status-interval 5 in tmux.conf.d/status.conf and daemon."""
        status_conf = os.path.join(PROJECT_ROOT, "tmux.conf.d", "status.conf")
        self.assertTrue(os.path.isfile(status_conf), f"Missing {status_conf}")

        # 1. Static file check
        with open(status_conf, "r", encoding="utf-8") as f:
            content = f.read()
        self.assertTrue(
            bool(re.search(r"^\s*set\s+(-g\s+)?status-interval\s+5\b", content, re.MULTILINE)),
            "tmux.conf.d/status.conf must contain 'set -g status-interval 5'",
        )

        # 2. Live tmux daemon validation
        sock_name = f"dotfiles_test_inv4_{os.getpid()}"
        cmd = [
            "tmux",
            "-L",
            sock_name,
            "-f",
            "/dev/null",
            "start-server",
            ";",
            "source-file",
            status_conf,
            ";",
            "show-options",
            "-g",
            "status-interval",
            ";",
            "kill-server",
        ]
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.assertEqual(proc.returncode, 0, f"tmux execution failed: {proc.stderr}")
        self.assertEqual(proc.stdout.strip(), "status-interval 5")

    def test_invariant_5_prompt_visual_and_stale_fd(self):
        """Invariant 5: Prompt 3-line visual match, badges, exit code, delayed stale fd."""
        session = PtySession()
        try:
            raw_prompt = session.wait_for_prompt()
            clean_prompt = strip_ansi(raw_prompt)

            # 1. Visual 3-line prompt validation
            # Line 1: 🕙 HH:MM:SS
            self.assertRegex(clean_prompt, r"🕙 \s*\d{2}:\d{2}:\d{2}")
            # Line 2: ╭─user@host: in path
            self.assertIn("╭─", raw_prompt)
            self.assertIn(": in ", raw_prompt)
            # Line 3: ╰─λ on success
            self.assertIn("╰─λ", raw_prompt)

            # 2. Exit code reporting
            # Run false -> prompt line 3 must show ╰─✗ 1
            out = session.run_command("false")
            self.assertIn("╰─✗ 1", strip_ansi(out))

            # Run (exit 42) -> prompt line 3 must show ╰─✗ 42
            out = session.run_command("(exit 42)")
            self.assertIn("╰─✗ 42", strip_ansi(out))

            # Run true -> restores ╰─λ
            out = session.run_command("true")
            self.assertIn("╰─λ", strip_ansi(out))

            # 3. Execution duration reporting (took >= 1.0s)
            out = session.run_command("sleep 1.1", timeout=3.0)
            self.assertRegex(strip_ansi(out), r"took 1\.\d+s")

            # 4. Git branch & dirty indicators (* = unstaged, ? = untracked)
            # When inside git repo with modifications, branch and dirty symbols appear
            out = session.run_command("pwd")
            self.assertIn("main", strip_ansi(out))

            # 5. Language badges: in tmux.conf.d/tmux-pane-info (has go.mod)
            go_dir = os.path.join(PROJECT_ROOT, "tmux.conf.d", "tmux-pane-info")
            session.send_line(f"cd {go_dir}")
            time.sleep(0.4)
            out_go = session.wait_for_prompt()
            self.assertIn("🐹", strip_ansi(out_go), "Prompt must show Go badge (🐹) in go.mod dir")

            # 6. Delayed _prmt_stale_fd closing contract
            # Verify functions and variables exist in shell session
            out_fd = session.run_command("typeset -p _prmt_stale_fd functions[_prmt_stale_fd_close]")
            clean_fd = strip_ansi(out_fd)
            self.assertIn("typeset -i _prmt_stale_fd", clean_fd)
            self.assertIn("_prmt_stale_fd_close", clean_fd)

            # Verify _prmt_init source implementation contains delayed closing pattern
            init_path = os.path.join(PROJECT_ROOT, "zfunc", "_prmt_init")
            with open(init_path, "r", encoding="utf-8") as f:
                init_content = f.read()
            self.assertIn("_prmt_stale_fd=$fd", init_content)
            self.assertIn("zsh-defer -mprs -c '_prmt_stale_fd_close'", init_content)
        finally:
            session.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
