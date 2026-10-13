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

--stop-at first-output switches to a different measurement: return as soon as the
first byte hits the pty (no --send, no idle wait), for time-to-first-prompt-byte
instead of time-to-idle. --print-output captures all pty bytes and dumps them to
stdout at the end for ad-hoc inspection; it only runs when explicitly requested so
it never perturbs the timing runs above. bench/zsh/profile does NOT use this flag:
it queues zprof as a deferred task, and zsh-defer redirects a deferred task's
stdout to /dev/null for the task's duration (option `1`, see bench.mk), so the
table never reaches the pty to be captured in the first place. That target
instead has the deferred task write zprof's output to a file and reads the file
directly.

--share-zcompdump symlinks the real $HOME/.zcompdump(.zwc) into $ZDOTDIR before
launching zsh. bench/zsh/profile runs under a throwaway $ZDOTDIR (see bench.mk)
so it has no .zcompdump of its own -- sheldon.toml's compinit freshness check
(`${ZDOTDIR:-$HOME}/.zcompdump` missing or >24h old) then always takes the full,
slow compinit path instead of the `compinit -C` fast path a warm real $HOME gets.
Without this flag that's what you're measuring: a synthetic cold-cache cost, not
everyday warm-cache startup. This only matters for $ZDOTDIR-scoped profiling runs;
it's a no-op when $ZDOTDIR is unset or already the real $HOME.
"""
import argparse
import os
import signal
import sys
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
parser.add_argument("--stop-at", choices=["idle", "first-output"], default="idle",
                     help="'idle' (default) waits for --quiet-ms of silence, then sends --send "
                          "and waits for the shell to exit -- measures time-to-idle. "
                          "'first-output' returns as soon as the first byte arrives on the pty "
                          "and kills the shell without sending anything -- measures "
                          "time-to-first-prompt-byte, closer to perceived 'shell feels ready' "
                          "latency than time-to-idle")
parser.add_argument("--print-output", action="store_true",
                     help="capture all pty output and dump it to stdout once the run ends, for "
                          "ad-hoc inspection. Default is to discard output entirely so "
                          "hyperfine's timing is never affected by buffering/printing")
parser.add_argument("--share-zcompdump", action="store_true",
                     help="symlink the real $HOME/.zcompdump(.zwc) into $ZDOTDIR before "
                          "launching zsh, so a throwaway $ZDOTDIR gets the same compinit "
                          "freshness check (and fast path) a warm real $HOME would. No-op if "
                          "$ZDOTDIR is unset/equals $HOME, or if $HOME has no .zcompdump yet")
args = parser.parse_args()

if args.share_zcompdump:
    home = os.path.expanduser("~")
    zdotdir = os.environ.get("ZDOTDIR") or home
    if os.path.abspath(zdotdir) == os.path.abspath(home):
        # ZDOTDIR isn't actually pointing at a separate directory -- nothing to
        # share, and symlinking $HOME/.zcompdump onto itself would risk
        # clobbering the real cache file.
        pass
    else:
        src_dump = os.path.join(home, ".zcompdump")
        if not os.path.exists(src_dump):
            print(f"zsh-pty-startup: --share-zcompdump: {src_dump} does not exist, "
                  f"skipping (compinit will take its normal first-run path)", file=sys.stderr)
        else:
            for name in (".zcompdump", ".zcompdump.zwc"):
                src = os.path.join(home, name)
                dst = os.path.join(zdotdir, name)
                if os.path.exists(src) and not os.path.lexists(dst):
                    try:
                        os.symlink(src, dst)
                    except OSError as e:
                        # Non-fatal: compinit just falls back to its normal
                        # freshness check against whatever ended up in $ZDOTDIR.
                        print(f"zsh-pty-startup: --share-zcompdump: failed to symlink "
                              f"{dst}: {e}", file=sys.stderr)

pid, fd = os.forkpty()
if pid == 0:
    os.execvp("zsh", ["zsh", "-i"])
    os._exit(1)

import fcntl
flags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

captured = [] if args.print_output else None

start = time.monotonic()
last_activity = start
exit_sent = False
while True:
    now = time.monotonic()
    try:
        chunk = os.read(fd, 65536)
        if chunk:
            last_activity = now
            if captured is not None:
                captured.append(chunk)
            if args.stop_at == "first-output":
                break
    except OSError:
        pass
    if args.stop_at == "idle" and not exit_sent and (now - last_activity) * 1000 >= args.quiet_ms:
        os.write(fd, b"exit\n" if args.send == "exit" else b"\x04")
        exit_sent = True
    if now - start > args.max_wait_s:
        break
    wpid, _ = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        break
    time.sleep(0.01)

if args.stop_at == "first-output":
    # We never sent exit/EOF, so the shell is still running -- kill it so it
    # doesn't leak as an orphaned zsh -i process. SIGTERM alone can be
    # ignored by this shell's job-control setup, and even SIGKILL followed
    # by a synchronous waitpid here can block for hundreds of ms on pty
    # teardown -- both would leak into hyperfine's measured wall time for
    # this process. Fork a grandchild to send SIGKILL asynchronously instead,
    # so this process can exit immediately. The grandchild is pid's sibling,
    # not its parent, so it can't waitpid(pid) itself (ECHILD) -- reaping
    # happens once this process exits and pid gets reparented to init/launchd.
    try:
        if os.fork() == 0:
            try:
                os.kill(pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            os._exit(0)
    except OSError:
        # fork() itself failed (fd/process exhaustion) -- fall back to a
        # synchronous kill from this process rather than leaking the shell.
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

if captured is not None:
    try:
        os.write(1, b"".join(captured))
    except BrokenPipeError:
        pass
