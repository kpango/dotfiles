#!/usr/bin/env zsh

export ZCACHE_DIR="${ZCACHE_DIR:-$HOME/.zcache}"

if [[ -f "$ZCACHE_DIR/env.zsh" ]]; then
	source "$ZCACHE_DIR/env.zsh"
else
	[[ -d "$ZCACHE_DIR" ]] || mkdir -p "$ZCACHE_DIR"
	if [ -z "$CPUCORES" ]; then
		if (($+commands[nproc])); then
			export CPUCORES="$(nproc)"
		else
			export CPUCORES="$(getconf _NPROCESSORS_ONLN)"
		fi
	fi

	# Determine DOTFILES_DIR
	export GIT_USER=${GIT_USER:-kpango}
	if [ -z "$DOTFILES_DIR" ]; then
		DOTFILE_URL="github.com/$GIT_USER/dotfiles"
		if [ -d "$HOME/go/src/$DOTFILE_URL" ]; then
			export DOTFILES_DIR="$HOME/go/src/$DOTFILE_URL"
		elif [ -d "$HOME/ghq/$DOTFILE_URL" ]; then
			export DOTFILES_DIR="$HOME/ghq/$DOTFILE_URL"
		elif (($+commands[ghq])); then
			export DOTFILES_DIR="$(ghq root)/$DOTFILE_URL"
		else
			export DOTFILES_DIR="$HOME/dotfiles"
		fi
	fi

	fpath=("$DOTFILES_DIR/zfunc" $fpath)
	autoload -Uz _zcache_eval

	autoload -Uz _gen_env
	# Dependency args so this cache actually invalidates when the logic it bakes
	# changes — without them _zcache_eval only regenerates on a missing cache file,
	# never on content drift (confirmed 2026-08-19: a stale env.zsh kept baking a
	# pre-fix _base_path/_gen_env output indefinitely even after both were edited).
	_zcache_eval env 0 "_gen_env" "$DOTFILES_DIR/zfunc/_base_path" "$DOTFILES_DIR/zfunc/_gen_env"
fi

# Fast path for inline script execution (-c flag): env.zsh provides PATH and core env.
# Skip all interactive-only setup (plugins, completions, prompt, ZLE bindings).
# PATH fallback ensures commands work even if env.zsh cache is missing or stale.
if [[ -n "$ZSH_EXECUTION_STRING" ]]; then
	# Deliberately unconditional, not gated on _ZSH_PATH_LOADED: that guard is
	# exported, so it can already read 1 here purely from environment inheritance
	# (an ancestor process ran this before), independent of whether *this*
	# process's own PATH actually has _base_path's dirs. Skipping on an inherited
	# guard risks silently keeping an incomplete PATH; always rebuilding is cheap
	# (one _base_path fork, deduped by typeset -U) and correct regardless of
	# ancestry — see zsh/00-env.zsh for the fuller version of this reasoning.
	export _ZSH_PATH_LOADED=1
	typeset -U path PATH
	# OS-common dirs vs macOS-only additions (Homebrew) live in _base_path,
	# the single source shared with _gen_env (env.zsh cache) and 00-env.zsh.
	autoload -Uz _base_path
	export PATH="$(_base_path):$PATH"
	# Load functions/aliases from zcache for non-interactive shells (e.g., Claude Code, scripts)
	if [[ -z "$_ZSH_FUNCS_LOADED" ]]; then
		export _ZSH_FUNCS_LOADED=1
		local _zc="${ZCACHE_DIR:-$HOME/.zcache}"
		[[ -f "$_zc/combined.zsh" ]] && source "$_zc/combined.zsh" 2>/dev/null
		[[ -n "$_ZSH_OS" && -f "$_zc/os-${_ZSH_OS}.zsh" ]] && source "$_zc/os-${_ZSH_OS}.zsh" 2>/dev/null
	fi
	return
fi

if ! (($+functions[_zcache_eval])); then
	fpath=("$DOTFILES_DIR/zfunc" $fpath)
	autoload -Uz _zcache_eval
fi
if ! (($+functions[_gen_env])); then
	autoload -Uz _gen_env
fi

# OS detection — skipped when already set by env.zsh (cached by _gen_env)
if [[ -z "$_ZSH_OS" ]]; then
	if [[ -f /etc/NIXOS || -f /etc/nixos/configuration.nix ]]; then
		export _ZSH_OS=nixos
	elif [[ -f /etc/arch-release ]]; then
		export _ZSH_OS=arch
	elif [[ -f /etc/debian_version ]]; then
		export _ZSH_OS=debian
	elif [[ $OSTYPE = darwin* ]]; then
		export _ZSH_OS=brew
	else
		export _ZSH_OS=generic
	fi
fi

# TTY-only setup: these only matter when ZLE will actually run
if [[ -t 0 ]]; then
	# Plugin env vars must be set before sheldon loads zsh-autosuggestions
	export ZSH_AUTOSUGGEST_USE_ASYNC=1
	export ZSH_AUTOSUGGEST_MANUAL_REBIND=1
	bindkey -e
	export KEYTIMEOUT=1
	# These options used to live in the deferred zsh/03-history.zsh, but zsh-defer's
	# _zsh-defer-resume wraps every deferred task in `emulate -L zsh` for its own
	# duration, which resets options to the zsh baseline and discards any setopt/
	# unsetopt a deferred task makes once that scope unwinds. A deferred `setopt
	# share_history` (etc.) silently never took effect; only the variable
	# assignments right below it (HISTSIZE, SAVEHIST) survived, which is why this
	# went unnoticed. Setting them here, synchronously and before ZLE starts, is
	# effectively free (setopt itself costs nothing) and makes them actually stick.
	setopt APPEND_HISTORY SHARE_HISTORY hist_ignore_all_dups hist_ignore_space hist_reduce_blanks hist_save_no_dups \
		auto_cd auto_list auto_menu auto_param_keys auto_param_slash auto_pushd correct extended_glob ignore_eof \
		interactive_comments list_packed list_types magic_equal_subst no_beep no_flow_control noautoremoveslash \
		nonomatch notify print_eight_bit prompt_subst pushd_ignore_dups
	# stty is an external process (~2ms); guard prevents cost in non-TTY contexts.
	stty -ixon -ixoff 2>/dev/null
fi

# HISTFILE must be set before the first prompt — 03-history.zsh runs deferred and zsh
# tries to write history immediately on startup, causing a rename error if unset.
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"

# PATH setup from 00-env.zsh normally runs deferred inside combined.zsh, but sheldon
# needs tools like prmt in PATH at load time here, synchronously, before that.
#
# Deliberately unconditional, not gated on _ZSH_PATH_LOADED: an exported guard
# already reading 1 here only means some ancestor process ran this before, not that
# *this* process's own PATH has _base_path's dirs (confirmed 2026-08-19: this exact
# guard-inherited-but-PATH-incomplete gap reproduced a PATH-loss bug on darwin one
# process removed via tmux/nested-shell inheritance). Always rebuilding is cheap —
# a single _base_path fork, deduped by typeset -U — and correct regardless of
# ancestry. Downstream, 00-env.zsh's own guard still skips its redundant copy of
# this on non-darwin once this has run; on darwin it always re-derives PATH from
# scratch after its own PATH="" reset regardless, so this cannot go stale there.
export _ZSH_PATH_LOADED=1
typeset -U path PATH
# OS-common dirs vs macOS-only additions (Homebrew) live in _base_path, the
# single source shared with _gen_env (env.zsh cache) and 00-env.zsh.
autoload -Uz _base_path
export PATH="$(_base_path):$PATH"

# Generate ATUIN_SESSION before sheldon/atuin.zsh loads so it's available even
# when ZSH_EXECUTION_STRING prevents sheldon from running (e.g. zsh -c calls).
# atuin.zsh honours a pre-set ATUIN_SESSION and only regenerates on SHLVL change.
if [[ -z "${ATUIN_SESSION}" ]]; then
	if [[ -r /proc/sys/kernel/random/uuid ]]; then
		read -r _atuin_uuid </proc/sys/kernel/random/uuid
	else
		_atuin_uuid="${$}-${EPOCHREALTIME:-${RANDOM}${RANDOM}}"
	fi
	export ATUIN_SESSION="${_atuin_uuid//-/}"
	unset _atuin_uuid
fi

# Load sheldon only when stdin is a TTY — all deferred tasks require ZLE-idle (never fires
# for non-TTY), and prmt is independently guarded. Skipping for pipe/file stdin saves ~3ms.
if [[ -z "$ZSH_EXECUTION_STRING" && -t 0 ]] && (($+commands[sheldon])); then
	_zcache_eval sheldon 0 "sheldon source" \
		"${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
fi

# Source tmux auto-start synchronously to avoid a visible prompt flash before tmux launches
if [[ -z "$ZSH_EXECUTION_STRING" && -t 0 && -n "$DOTFILES_DIR" ]]; then
	source "$DOTFILES_DIR/zsh/01-tmux.zsh"
fi

# Fallback prompt when prmt is not installed (prmt sets _prmt_precmd when active)
if ! (($+functions[_prmt_precmd])); then
	PROMPT='%F{green}%n@%m%f %F{blue}%~%f %(?.%F{green}.%F{red})%#%f '
fi

# Combined, OS-specific, and GUI caches are only useful for TTY sessions — they rely on
# ZLE-idle deferred execution (or the autosuggestions/completions loaded therein). Skip
# entirely for non-TTY stdin to avoid synchronous sourcing of large cache files.
if [[ -z "$ZSH_EXECUTION_STRING" && -t 0 ]]; then
	# Combined cache: all zsh/*.zsh except OS-specific files (20-os-*.zsh)
	local combined_cache="$ZCACHE_DIR/combined.zsh"
	# Freshness via a single native glob (no subshell/loop): editing an existing
	# file's *contents* previously went undetected here (only "cache file exists?"
	# was checked), so combined.zsh kept sourcing stale code until a manual
	# `zclean` — silently, indefinitely. (N.om[1]) is over-inclusive (also covers
	# 20-os-*.zsh/01-tmux.zsh, which combined.zsh doesn't contain) but that only
	# costs an occasional unnecessary rebuild, never a missed one.
	local _newest_zsh="$DOTFILES_DIR/zsh"/*.zsh(N.om[1])
	if [[ -f "$combined_cache" && ( -z "$_newest_zsh" || ! "$_newest_zsh" -nt "$combined_cache" ) ]]; then
		if (($+functions[zsh-defer])); then
			# -t 0.01 starts a new yield chunk (see sheldon.toml, above [plugins.colors]):
			# sourcing this cache is the single most expensive deferred task, so it must not
			# share a zle callback with the plugin tasks queued before it.
			zsh-defer -mpr -t 0.01 source "$combined_cache"
		else
			source "$combined_cache"
		fi
	else
		local _zsh_deps=()
		for _f in "$DOTFILES_DIR/zsh"/*.zsh; do
			[[ -e "$_f" ]] || continue
			[[ "${_f:t}" = 20-os-*.zsh || "${_f:t}" = 01-tmux.zsh ]] || _zsh_deps+=("$_f")
		done
		_zcache_eval combined 0 \
			'for _f in "$DOTFILES_DIR/zsh"/*.zsh; do [[ "${_f:t}" = 20-os-*.zsh || "${_f:t}" = 01-tmux.zsh ]] || cat "$_f"; done' \
			"${_zsh_deps[@]}"
	fi

	# OS-specific cache: only the file matching the detected OS
	local _os_src="$DOTFILES_DIR/zsh/20-os-${_ZSH_OS}.zsh"
	if [[ -f "$_os_src" ]]; then
		local _os_cache="$ZCACHE_DIR/os-${_ZSH_OS}.zsh"
		if [[ -f "$_os_cache" && ! "$_os_src" -nt "$_os_cache" ]]; then
			if (($+functions[zsh-defer])); then
				zsh-defer -mpr source "$_os_cache"
			else
				source "$_os_cache"
			fi
		else
			_zcache_eval "os-${_ZSH_OS}" 0 "cat '$_os_src'" "$_os_src"
		fi
	fi

	# GUI-specific cache: always loaded on top of the OS file
	local _gui_src="$DOTFILES_DIR/zsh/20-os-gui.zsh"
	if [[ -f "$_gui_src" && "$_gui_src" != "$_os_src" ]]; then
		local _gui_cache="$ZCACHE_DIR/os-gui.zsh"
		if [[ -f "$_gui_cache" && ! "$_gui_src" -nt "$_gui_cache" ]]; then
			if (($+functions[zsh-defer])); then
				zsh-defer -mpr source "$_gui_cache"
			else
				source "$_gui_cache"
			fi
		else
			_zcache_eval "os-gui" 0 "cat '$_gui_src'" "$_gui_src"
		fi
	fi

	# Tasks that combined.zsh queues while it is itself running (direnv, select-word-style,
	# the kubectl completion cache) are appended to zsh-defer's queue with delay 0 *after*
	# every task this file registers, so no -t placed here can reach them and they run
	# back-to-back in one zle callback. Rewriting the leading delay field of whatever is
	# still queued gives each of them the same yield point `zsh-defer -t 0.01` would have
	# given at registration time. Queue elements are "<delay-in-centiseconds> <opts> <cmd>";
	# guarded on the array existing so a zsh-defer rename degrades to today's behaviour
	# rather than erroring at every prompt.
	if (($+functions[zsh-defer])) && (($+_zsh_defer_tasks)); then
		zsh-defer -mpr -c '_zsh_defer_tasks=("${(@)_zsh_defer_tasks/#0 /1 }")'
	fi
fi
