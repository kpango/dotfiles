.PHONY: bench/zsh bench/zsh/cold bench/zsh/compare bench/zsh/profile bench/zsh/startup

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
bench/zsh/startup: _bench_check
	hyperfine --warmup 3 --min-runs 20 '$(PTY_BENCH) --send eof'

## Profile zsh startup with zprof — shows per-function timing (top 60 lines).
## Runs under a real pty so TTY-gated blocks (sheldon/zsh-defer/atuin) actually execute.
bench/zsh/profile:
	@_D=$$(mktemp -d); \
	{ printf 'zmodload zsh/zprof\n'; cat "$(HOME)/.zshenv" 2>/dev/null || true; } > "$$_D/.zshenv"; \
	printf 'source "%s/.zshrc"\nzprof\n' "$(HOME)" > "$$_D/.zshrc"; \
	ZDOTDIR="$$_D" $(PTY_BENCH) --quiet-ms 500 --max-wait-s 15 2>&1 | head -60; \
	rm -rf "$$_D"
