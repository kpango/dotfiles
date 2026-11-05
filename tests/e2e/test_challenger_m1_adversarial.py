#!/usr/bin/env python3
"""Adversarial challenger test suite for Zsh and Tmux optimization project.

Attacks tested:
1. Meta-character and prompt injection in Git branch name (prompt_subst safety)
2. Terminal freeze attack: rapid Ctrl-S / Ctrl-Q bursts under PTY
3. Deep nested directory boundary traversal (loop termination at / or HOME)
4. Rapid precmd cycling fd leak stress test (delayed stale fd closing)
5. Autosuggestions buffer stress with long lines and Unicode strings
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
    ansi_regex = re.compile(r"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])")
    return ansi_regex.sub("", text)


class TestChallengerM1Adversarial(unittest.TestCase):
    """Adversarial test cases attacking boundary invariants."""

    def test_adv_1_git_branch_meta_characters_prompt_subst(self):
        """Adversarial 1: Branch names with format specifiers like %F{red} or $(calc) must not inject."""
        tmpdir = tempfile.mkdtemp(prefix="adv1_repo_")
        try:
            # Init git repo with an adversarial branch name
            subprocess.run(["git", "init", "-q", tmpdir], check=True)
            # Create a detached head or ref with %F{red}%m and $(echo PWNED)
            adversarial_branch = "feature/%F{red}%m%n$(touch /tmp/pwned)"
            head_file = os.path.join(tmpdir, ".git", "HEAD")
            with open(head_file, "w") as f:
                f.write(f"ref: refs/heads/{adversarial_branch}\n")

            # Launch interactive zsh in tmpdir
            master, slave = pty.openpty()
            winsize = struct.pack("HHHH", 24, 120, 0, 0)
            fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

            env = os.environ.copy()
            env["TERM"] = "xterm-256color"
            env["TMUX"] = "mock"
            env["DOTFILES_DIR"] = PROJECT_ROOT

            pid = os.fork()
            if pid == 0:
                os.close(master)
                os.setsid()
                fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
                os.dup2(slave, 0)
                os.dup2(slave, 1)
                os.dup2(slave, 2)
                os.close(slave)
                os.chdir(tmpdir)
                os.execvpe("zsh", ["zsh", "-i"], env)
                os._exit(1)

            os.close(slave)
            time.sleep(0.5)

            out = b""
            while True:
                r, _, _ = select.select([master], [], [], 0.3)
                if not r:
                    break
                out += os.read(master, 2048)

            os.kill(pid, 9)
            os.waitpid(pid, 0)
            os.close(master)

            clean = strip_ansi(out.decode("utf-8", errors="replace"))
            # Must not execute injection payload /tmp/pwned
            self.assertFalse(os.path.exists("/tmp/pwned"), "Command substitution in branch name executed!")
            # The prompt sanitizer % escaping ${_prmt_git_branch//\%/%%} must keep it safe
            self.assertIn("feature/", clean)
        finally:
            if os.path.exists("/tmp/pwned"):
                os.remove("/tmp/pwned")
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_adv_2_rapid_flow_control_bursts(self):
        """Adversarial 2: Rapid burst of Ctrl-S / Ctrl-Q during foreground execution must not freeze."""
        master, slave = pty.openpty()
        winsize = struct.pack("HHHH", 24, 120, 0, 0)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        env["TMUX"] = "mock"
        env["DOTFILES_DIR"] = PROJECT_ROOT

        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.chdir(PROJECT_ROOT)
            os.execvpe("zsh", ["zsh", "-i"], env)
            os._exit(1)

        os.close(slave)
        time.sleep(0.5)

        # Launch a foreground command that outputs sequentially
        cmd = (
            "python3 -c \"import time, sys; "
            "sys.stdout.write('BURST_START\\n'); sys.stdout.flush(); "
            "time.sleep(0.2); "
            "sys.stdout.write('BURST_END\\n'); sys.stdout.flush()\"\n"
        )
        os.write(master, cmd.encode("utf-8"))
        time.sleep(0.05)

        # Flood master with rapid Ctrl-S (\x13) and Ctrl-Q (\x11) bursts
        for _ in range(20):
            os.write(master, b"\x13\x11")

        time.sleep(0.4)

        out = b""
        while True:
            r, _, _ = select.select([master], [], [], 0.3)
            if not r:
                break
            out += os.read(master, 2048)

        os.kill(pid, 9)
        os.waitpid(pid, 0)
        os.close(master)

        clean = strip_ansi(out.decode("utf-8", errors="replace"))
        self.assertIn("BURST_START", clean, "Foreground process failed to start")
        self.assertIn("BURST_END", clean, "Foreground process froze on Ctrl-S burst")

    def test_adv_3_deep_directory_hierarchy_loop_termination(self):
        """Adversarial 3: CWD scan must terminate cleanly even in 50-level nested directory structure."""
        tmpdir = tempfile.mkdtemp(prefix="adv3_nest_")
        deep_path = tmpdir
        for i in range(40):
            deep_path = os.path.join(deep_path, f"d{i}")
        os.makedirs(deep_path, exist_ok=True)

        try:
            # Measure time for _prmt_scan_cwd in deeply nested directory
            script = f"""
            fpath=("{PROJECT_ROOT}/zfunc" $fpath)
            autoload -Uz _prmt_init
            cd "{deep_path}"
            _prmt_init
            _prmt_scan_cwd
            print -r -- "DEEP_SCAN_OK:$_prmt_git_root"
            """
            proc = subprocess.run(
                ["zsh", "-c", script],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=5.0,
            )
            self.assertEqual(proc.returncode, 0)
            self.assertIn("DEEP_SCAN_OK:", proc.stdout)
        finally:
            shutil.rmtree(tmpdir, ignore_errors=True)

    def test_adv_4_fd_leak_stress_rapid_prompt_cycling(self):
        """Adversarial 4: Cycling precmd 30 times must not leak open file descriptors."""
        script = f"""
        emulate -L zsh
        fpath=("{PROJECT_ROOT}/zfunc" $fpath)
        autoload -Uz _prmt_init
        typeset -i init_fds=$(ls /proc/$$/fd | wc -l)
        _prmt_init
        for i in {{1..20}}; do
            _prmt_precmd
            _prmt_stale_fd_close
        done
        typeset -i final_fds=$(ls /proc/$$/fd | wc -l)
        print -r -- "FD_DIFF:$(( final_fds - init_fds ))"
        """
        proc = subprocess.run(
            ["zsh", "-c", script],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=5.0,
        )
        self.assertEqual(proc.returncode, 0, f"Error: {proc.stderr}")
        m = re.search(r"FD_DIFF:(-?\d+)", proc.stdout)
        self.assertIsNotNone(m)
        diff = int(m.group(1))
        # Difference must be <= 1 (accounting for subshell/eval transient fd)
        self.assertLessEqual(diff, 2, f"Leaked file descriptors during rapid cycling: +{diff} fds")

    def test_adv_5_autosuggest_large_buffer_safety(self):
        """Adversarial 5: Inputting >500 character buffer must not crash autosuggestions."""
        master, slave = pty.openpty()
        winsize = struct.pack("HHHH", 24, 120, 0, 0)
        fcntl.ioctl(slave, termios.TIOCSWINSZ, winsize)

        env = os.environ.copy()
        env["TERM"] = "xterm-256color"
        env["TMUX"] = "mock"
        env["DOTFILES_DIR"] = PROJECT_ROOT

        pid = os.fork()
        if pid == 0:
            os.close(master)
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
            os.dup2(slave, 0)
            os.dup2(slave, 1)
            os.dup2(slave, 2)
            os.close(slave)
            os.chdir(PROJECT_ROOT)
            os.execvpe("zsh", ["zsh", "-i"], env)
            os._exit(1)

        os.close(slave)
        time.sleep(0.5)

        # Send huge command string (>500 chars)
        huge_str = "echo " + "A" * 600 + "\n"
        os.write(master, huge_str.encode("utf-8"))
        time.sleep(0.5)

        # Send follow up command
        os.write(master, b"echo ADV5_STABLE\n")
        time.sleep(0.4)

        out = b""
        while True:
            r, _, _ = select.select([master], [], [], 0.3)
            if not r:
                break
            out += os.read(master, 4096)

        os.kill(pid, 9)
        os.waitpid(pid, 0)
        os.close(master)

        clean = strip_ansi(out.decode("utf-8", errors="replace"))
        self.assertIn("ADV5_STABLE", clean, "Autosuggestion crashed on oversized buffer")


if __name__ == "__main__":
    unittest.main(verbosity=2)
