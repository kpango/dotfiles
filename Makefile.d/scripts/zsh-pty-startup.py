#!/usr/bin/env python3
"""Launch an interactive zsh under a real pty and exit once it goes idle.

`zsh -i -c exit` and `zsh -i < file` (used by earlier bench.mk targets) both set
$ZSH_EXECUTION_STRING or fail the `[[ -t 0 ]]` check in zshrc, so they skip every
TTY-gated block (sheldon, zsh-defer, tmux, atuin, completion). Neither measures what
a real terminal actually pays. A pty makes `-t 0` true and keeps $ZSH_EXECUTION_STRING
unset, so the full interactive path (including zsh-defer's first-idle burst) runs.

Idle is detected by watching the pty for a quiet period (no bytes for --quiet-ms),
then "exit\n" is written and the process is waited on. hyperfine wraps this whole
script as one command and measures its wall time -- that wall time is what a user
actually experiences between opening a shell and it being ready for input.
"""
import argparse
import os
import time

parser = argparse.ArgumentParser()
parser.add_argument("--quiet-ms", type=int, default=300,
                     help="consider zsh idle after this many ms with no pty output")
parser.add_argument("--max-wait-s", type=float, default=10.0)
parser.add_argument("--send", choices=["exit", "eof"], default="exit",
                     help="'exit' types the exit command (fires preexec/precmd like a real "
                          "command would); 'eof' sends Ctrl-D so the shell exits without ever "
                          "running a command -- use this to measure startup in isolation from "
                          "atuin's per-command preexec cost")
args = parser.parse_args()

pid, fd = os.forkpty()
if pid == 0:
    os.execvp("zsh", ["zsh", "-i"])
    os._exit(1)

import fcntl
flags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

start = time.monotonic()
last_activity = start
exit_sent = False
while True:
    now = time.monotonic()
    try:
        chunk = os.read(fd, 65536)
        if chunk:
            last_activity = now
    except OSError:
        pass
    if not exit_sent and (now - last_activity) * 1000 >= args.quiet_ms:
        os.write(fd, b"exit\n" if args.send == "exit" else b"\x04")
        exit_sent = True
    if now - start > args.max_wait_s:
        break
    wpid, _ = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        break
    time.sleep(0.01)
