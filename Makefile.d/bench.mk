.PHONY: bench/zsh bench/zsh/cold bench/zsh/compare bench/zsh/profile bench/zsh/startup bench/zsh/first-prompt

_bench_check:
	@command -v hyperfine >/dev/null 2>&1 || { printf 'Error: hyperfine not found\n' >&2; exit 1; }

PTY_BENCH := python3 $(CURDIR)/Makefile.d/scripts/zsh-pty-startup.py

# All targets below launch zsh under a real pty (scripts/zsh-pty-startup.py), not
# `zsh -i -c exit` or `zsh -i < file`/`</dev/null`: both of those leave `[[ -t 0 ]]`
# false (or set $ZSH_EXECUTION_STRING), so zshrc's TTY-gated block never runs and
# sheldon/zsh-defer/tmux/atuin/completion are silently skipped — they measured
# almost nothing. A pty is required to see what a real terminal actually pays.
# Run from inside a tmux session so TMUX is set (avoids tmux auto-attach in 01-tmux.zsh).

## Benchmark true interactive zsh startup — sheldon+deferred path (warm cache, 20 runs)
bench/zsh: _bench_check
	hyperfine --warmup 3 --min-runs 20 '$(PTY_BENCH)'

## Benchmark zsh startup after clearing all zsh caches via zclean
bench/zsh/cold: _bench_check
	zsh -i -c 'zclean'
	hyperfine --warmup 1 --min-runs 10 '$(PTY_BENCH)'

## Compare: no-rc baseline vs scripted (env-only) vs full interactive
bench/zsh/compare: _bench_check
	@printf '=== Raw process floor (no shell wrapper) ===\n'
	hyperfine \
	  --warmup 10 \
	  --min-runs 200 \
	  --shell=none \
	  -n 'zsh-only (raw floor)' 'zsh --no-rcs -c exit'
	@printf '=== Scripted (-c exit, skips TTY-gated setup) vs full interactive (pty) ===\n'
	hyperfine \
	  --warmup 10 \
	  --min-runs 30 \
	  -n 'scripted (env-only, -t 0 is false)' 'zsh -i -c exit' \
	  -n 'interactive (full, real pty)' '$(PTY_BENCH)'

## Benchmark time-to-first-idle with no command run (EOF instead of `exit`, so
## atuin's preexec never fires — isolates pure startup from per-command overhead)
##
## KNOWN BUG (found independently during zsh-startup-perf T-B1/T-B5, not fixed here):
## this zshrc sets `setopt ignore_eof` (see zshrc's TTY-only block), and `^D` is bound
## to `delete-char-or-list` (auto_list/auto_menu), so a single 0x04 byte is absorbed as
## a (no-op, buffer-empty) list request rather than an exit signal. zsh's own semantics
## say ten *consecutive* EOFs should force an exit regardless, but that was tested here
## too (10x 0x04, both batched and individually spaced ~50ms apart) and neither made the
## shell exit within a 10s window -- confirmed empirically, --send eof always times out
## at --max-wait-s in this environment. Root cause of why the "ten EOFs" rule doesn't
## apply here is unconfirmed (possibly delete-char-or-list's list-and-redisplay path
## resets whatever consecutive-EOF counter zsh tracks). Net effect: `bench/zsh/startup`
## currently measures --max-wait-s's timeout, not real startup -- use `bench/zsh/first-prompt`
## or `bench/zsh` (--send exit, the default) instead until this is fixed.
bench/zsh/startup: _bench_check
	hyperfine --warmup 3 --min-runs 20 '$(PTY_BENCH) --send eof'

## Benchmark time-to-first-output — how long until the pty prints its first byte.
## Returns on that first byte alone; unlike bench/zsh/startup it does NOT wait for
## --quiet-ms of silence, so it excludes zsh-defer's deferred-load burst entirely.
## Closer to perceived "shell feels ready to type into" latency than time-to-idle.
bench/zsh/first-prompt: _bench_check
	hyperfine --warmup 3 --min-runs 20 '$(PTY_BENCH) --stop-at first-output'

## Profile zsh startup with zprof — shows per-function timing (top 60 lines).
## Runs under a real pty so TTY-gated blocks (sheldon/zsh-defer/atuin) actually execute.
##
## `zprof` is queued as the LAST zsh-defer task rather than called directly at the end of
## .zshrc: zsh-defer's queue only drains via a zle -F fd callback, which zle only services
## once the shell reaches its interactive read loop -- strictly after .zshrc finishes
## sourcing. A `zprof` placed directly in .zshrc therefore always ran before every deferred
## task (zsh-defer/sheldon/compinit) executed, so this table never showed any of that cost,
## no matter how it was actually spent. Queuing it as one more zsh-defer call (appended after
## everything .zshrc itself registers) puts it strictly last in the FIFO queue, so it now
## runs after the real deferred burst completes. It also can't be a bare `zsh-defer zprof`:
## zsh-defer redirects a deferred task's stdout to /dev/null by default (option `1`, part of
## its default `12dmszpr`) and restores it only after the task returns, so zprof's own output
## would be silently discarded -- explicitly redirecting it to a file from inside the task
## (which overrides that temporary redirect for zprof's own fd) is what actually gets it out.
## No -t delay is needed: FIFO order alone already guarantees zprof runs after every task
## queued ahead of it, however long they take (confirmed empirically -- -t 0/0.01/0.3/0.45
## all produce an identical table). A large enough delay is actively harmful, though: this
## recipe's --quiet-ms 500 races it -- once 500ms of silence elapses the harness sends `exit`,
## which sets KEYS_QUEUED_COUNT and breaks _zsh-defer-resume's drain loop
## (`while (( $#_zsh_defer_tasks && !KEYS_QUEUED_COUNT && !PENDING ))`) before zprof's turn
## comes up, so it never runs (confirmed: -t 0.6 and -t 1.0 both leave zprof.out unwritten).
##
## The throwaway $ZDOTDIR this target profiles under has no .zcompdump of its own, so
## sheldon.toml's compinit freshness check always takes the slow full-compinit path (visible
## below as a heavy compinit/compdef burst) — that's a synthetic cold-cache cost, not
## everyday warm-cache startup. Pass SHARE_ZCOMPDUMP=1 to symlink the real
## $(HOME)/.zcompdump(.zwc) into $ZDOTDIR so compinit takes the same fast `-C` path a warm
## real $HOME gets (see --share-zcompdump in scripts/zsh-pty-startup.py for details/caveats).
bench/zsh/profile:
	@_D=$$(mktemp -d); \
	{ printf 'zmodload zsh/zprof\n'; cat "$(HOME)/.zshenv" 2>/dev/null || true; } > "$$_D/.zshenv"; \
	printf 'source "%s/.zshrc"\nzsh-defer -c "zprof > \"%s/zprof.out\" 2>&1"\n' "$(HOME)" "$$_D" > "$$_D/.zshrc"; \
	ZDOTDIR="$$_D" $(PTY_BENCH) --quiet-ms 500 --max-wait-s 15 $(if $(SHARE_ZCOMPDUMP),--share-zcompdump,) >/dev/null 2>&1; \
	if [ -s "$$_D/zprof.out" ]; then head -60 "$$_D/zprof.out"; else printf 'Error: zprof.out was not written (deferred zprof task never ran)\n' >&2; rm -rf "$$_D"; exit 1; fi; \
	rm -rf "$$_D"
