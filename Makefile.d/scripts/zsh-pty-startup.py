#!/usr/bin/env python3
"""Launch an interactive zsh under a real pty and exit once it goes idle.

`zsh -i -c exit` and `zsh -i < file` (used by earlier bench.mk targets) both set
$ZSH_EXECUTION_STRING or fail the `[[ -t 0 ]]` check in zshrc, so they skip every
TTY-gated block (sheldon, zsh-defer, tmux, atuin, completion). Neither measures what
a real terminal actually pays. A pty makes `-t 0` true and keeps $ZSH_EXECUTION_STRING
unset, so the full interactive path (including zsh-defer's first-idle burst) runs.

Idle is detected by watching the pty for a quiet period (no bytes for --quiet-ms),
then the shell gets SIGHUP and is waited on. hyperfine wraps this whole
script as one command and measures its wall time -- that wall time is what a user
actually experiences between opening a shell and it being ready for input.
No command is ever typed: the shell runs the user's real rc files, so a typed
`exit` went through atuin's preexec and landed in the real history (once per
run; ~425 `exit` entries from a single benchmarking session on 2026-10-21).

--stop-at first-output switches to a different measurement: return as soon as the
first byte hits the pty (no idle wait), for time-to-first-prompt-byte
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
import errno
import fcntl
import os
import select
import signal
import sys
import time

quiet_ms = 300
max_wait_s = 10.0
stop_at = "idle"
print_output = False
share_zcompdump = False

argv = sys.argv[1:]
i = 0
while i < len(argv):
    arg = argv[i]
    if arg in ("-h", "--help"):
        print(
            "usage: zsh-pty-startup.py [-h] [--quiet-ms QUIET_MS] "
            "[--max-wait-s MAX_WAIT_S] [--stop-at {idle,first-output}] "
            "[--print-output] [--share-zcompdump]"
        )
        sys.exit(0)
    elif arg == "--print-output":
        print_output = True
    elif arg == "--share-zcompdump":
        share_zcompdump = True
    elif arg == "--quiet-ms" or arg.startswith("--quiet-ms="):
        val = arg.split("=", 1)[1] if "=" in arg else argv[i := i + 1]
        quiet_ms = int(val)
    elif arg == "--max-wait-s" or arg.startswith("--max-wait-s="):
        val = arg.split("=", 1)[1] if "=" in arg else argv[i := i + 1]
        max_wait_s = float(val)
    elif arg == "--stop-at" or arg.startswith("--stop-at="):
        val = arg.split("=", 1)[1] if "=" in arg else argv[i := i + 1]
        if val not in ("idle", "first-output"):
            print(f"zsh-pty-startup.py: error: argument --stop-at: invalid choice: {val!r}", file=sys.stderr)
            sys.exit(2)
        stop_at = val
    else:
        print(f"zsh-pty-startup.py: error: unrecognized arguments: {arg}", file=sys.stderr)
        sys.exit(2)
    i += 1

if share_zcompdump:
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

flags = fcntl.fcntl(fd, fcntl.F_GETFL)
fcntl.fcntl(fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

captured = [] if print_output else None

start = time.monotonic()
deadline = start + max_wait_s
quiet_s = quiet_ms / 1000.0
last_activity = start
exit_sent = False
pty_open = True

while True:
    now = time.monotonic()
    if now >= deadline:
        break

    if pty_open:
        if stop_at == "first-output":
            wait_s = max(0.0, deadline - now)
        elif not exit_sent:
            wait_s = max(0.0, min(last_activity + quiet_s, deadline) - now)
        else:
            wait_s = max(0.0, min(0.005, deadline - now))

        try:
            rlist, _, _ = select.select([fd], [], [], wait_s)
        except InterruptedError:
            rlist = []

        if rlist:
            got_bytes = False
            while True:
                try:
                    chunk = os.read(fd, 65536)
                    if not chunk:
                        pty_open = False
                        break
                    got_bytes = True
                    if captured is not None:
                        captured.append(chunk)
                except OSError as e:
                    if e.errno not in (errno.EAGAIN, errno.EWOULDBLOCK, errno.EINTR):
                        pty_open = False
                    break
            if got_bytes:
                last_activity = time.monotonic()
                if stop_at == "first-output":
                    break
    else:
        time.sleep(0.001)

    now = time.monotonic()
    if stop_at == "idle" and not exit_sent and (now - last_activity) >= quiet_s:
        # SIGHUP rather than typed input: Ctrl-D never exits this zshrc (ignore_eof),
        # and a typed `exit` would be recorded in the real history.
        try:
            os.kill(pid, signal.SIGHUP)
        except ProcessLookupError:
            pass
        exit_sent = True

    wpid, _ = os.waitpid(pid, os.WNOHANG)
    if wpid == pid:
        break

if stop_at == "first-output":
    # We never sent SIGHUP, so the shell is still running -- kill it so it
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
