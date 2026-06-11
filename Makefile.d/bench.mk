.PHONY: bench/zsh bench/zsh/cold bench/zsh/compare bench/zsh/profile bench/zsh/startup

_bench_check:
	@command -v hyperfine >/dev/null 2>&1 || { printf 'Error: hyperfine not found\n' >&2; exit 1; }

# bench/zsh: measures true interactive startup (sheldon+defer path, no ZSH_EXECUTION_STRING)
# bench/zsh/compare also shows the scripted baseline (zsh -c, skips heavy loading)
# Run from inside a tmux session so TMUX is set (avoids tmux auto-attach in 01-tmux.zsh)

## Benchmark true interactive zsh startup — sheldon+deferred path (warm cache, 20 runs)
bench/zsh: _bench_check
	@printf 'exit\n' > /tmp/.zsh-bench-stdin
	hyperfine --warmup 3 --min-runs 20 --shell sh 'zsh -i < /tmp/.zsh-bench-stdin'
	@rm -f /tmp/.zsh-bench-stdin

## Benchmark zsh startup after clearing all zsh caches via zclean
bench/zsh/cold: _bench_check
	zsh -i -c 'zclean'
	@printf 'exit\n' > /tmp/.zsh-bench-stdin
	hyperfine --warmup 1 --min-runs 10 --shell sh 'zsh -i < /tmp/.zsh-bench-stdin'
	@rm -f /tmp/.zsh-bench-stdin

## Compare: no-rc baseline vs scripted (env-only) vs full interactive
bench/zsh/compare: _bench_check
	@printf 'exit\n' > /tmp/.zsh-bench-stdin
	@printf '=== Raw process floor (no shell wrapper) ===\n'
	hyperfine \
	  --warmup 10 \
	  --min-runs 200 \
	  --shell=none \
	  -n 'zsh-only (raw floor)' 'zsh --no-rcs -c exit'
	@printf '=== With shell wrapper (scripted vs full interactive) ===\n'
	hyperfine \
	  --warmup 10 \
	  --min-runs 200 \
	  --shell sh \
	  -n 'scripted (env-only)' 'zsh -i -c exit' \
	  -n 'interactive (full)' 'zsh -i < /tmp/.zsh-bench-stdin'
	@rm -f /tmp/.zsh-bench-stdin

## Benchmark time-to-first-prompt: no command runs, no atuin preexec overhead
bench/zsh/startup: _bench_check
	hyperfine --warmup 3 --min-runs 30 --shell sh 'zsh -i </dev/null'

## Profile zsh startup with zprof — shows per-function timing (top 60 lines)
bench/zsh/profile:
	@_D=$$(mktemp -d); \
	{ printf 'zmodload zsh/zprof\n'; cat "$(HOME)/.zshenv" 2>/dev/null || true; } > "$$_D/.zshenv"; \
	printf 'source "%s/.zshrc"\n' "$(HOME)" > "$$_D/.zshrc"; \
	printf 'exit\n' > "$$_D/stdin"; \
	ZDOTDIR="$$_D" zsh -i < "$$_D/stdin" 2>&1 | head -60; \
	rm -rf "$$_D"
