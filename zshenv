skip_global_compinit=1
# ZSH_DEFER_MAX_MS=1
ZCACHE_DIR="${ZCACHE_DIR:-$HOME/.zcache}"
if [[ "$OSTYPE" == darwin* ]]; then
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.local/run}"
else
	XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
fi
unsetopt GLOBAL_RCS

# Dedup fpath once, before anything ever assigns to it: zshrc (both the
# cache-miss branch and the interactive combined.zsh path), $ZCACHE_DIR/env.zsh
# (baked by zfunc/_gen_env), and zsh/00-env.zsh (baked into combined.zsh) each
# independently prepend "$DOTFILES_DIR/zfunc" to $fpath with no dedup of their
# own -- confirmed via `zsh -c 'print -l $fpath'` landing the same path twice,
# in both the interactive and non-interactive `zsh -c` cases. `typeset -U`
# marks the array unique from here on: every later `fpath=(...)` reassignment
# (regardless of which of those sites runs) silently drops the repeat instead
# of accumulating it. Same idiom as `typeset -U path PATH` in _apply_base_path.
typeset -U fpath

# Default committer identity (GIT_COMMITTER_NAME/EMAIL): no longer set here as a
# hardcoded literal. It's now baked into $ZCACHE_DIR/env.zsh by zfunc/_gen_env
# (sourced by the fast path below for non-interactive `zsh -c`, and by zshrc for
# interactive shells) from `git config --global user.*`, so it stays a single
# source of truth with ~/.gitconfig instead of a second hardcoded copy that can
# drift out of sync. See zfunc/_gen_env for the full rationale (including why
# GIT_AUTHOR_* is deliberately left alone) and zshrc's env cache dependency list
# for how a `git config --global` edit invalidates the cache.

# Fast path for inline script execution (-c flag): skip .zshrc and ATUIN_SESSION setup.
# .zshrc only provides interactive features (plugins, completions, prompt, ZLE bindings).
# Load functions/aliases from zcache so they are available in non-interactive shells
# (e.g., Claude Code Bash tool, shell scripts invoked with zsh -c).
if [[ -n "$ZSH_EXECUTION_STRING" ]]; then
	unsetopt RCS
	# POSIX-like behavior for inline scripts: unquoted parameter expansions
	# word-split like sh/bash (SH_WORD_SPLIT) and unmatched globs fall
	# through as literal patterns instead of aborting (NO_NOMATCH). Inline
	# one-liners (Claude Code Bash tool, CI snippets) are written against
	# sh semantics; zsh's defaults silently break loops like
	# `for f in $files` by not splitting $files.
	setopt SH_WORD_SPLIT NO_NOMATCH
	[[ -f "$ZCACHE_DIR/env.zsh" ]] && source "$ZCACHE_DIR/env.zsh"
	[[ -f "$ZCACHE_DIR/combined.zsh" ]] && source "$ZCACHE_DIR/combined.zsh" 2>/dev/null
	[[ -n "$_ZSH_OS" && -f "$ZCACHE_DIR/os-${_ZSH_OS}.zsh" ]] && source "$ZCACHE_DIR/os-${_ZSH_OS}.zsh" 2>/dev/null
else
	# Generate ATUIN_SESSION early — required for daemon IPC even before atuin.zsh loads.
	# atuin.zsh will keep this value (only regenerates when unset or SHLVL changes).
	if [[ -z "${ATUIN_SESSION}" ]]; then
		if [[ -r /proc/sys/kernel/random/uuid ]]; then
			read -r _atuin_uuid < /proc/sys/kernel/random/uuid
		else
			_atuin_uuid="${$}-${EPOCHREALTIME:-${RANDOM}${RANDOM}}"
		fi
		export ATUIN_SESSION="${_atuin_uuid//-/}"
		unset _atuin_uuid
	fi
fi
