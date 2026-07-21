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
	_zcache_eval env 0 "_gen_env"
fi

# Fast path for inline script execution (-c flag): env.zsh provides PATH and core env.
# Skip all interactive-only setup (plugins, completions, prompt, ZLE bindings).
# PATH fallback ensures commands work even if env.zsh cache is missing or stale.
if [[ -n "$ZSH_EXECUTION_STRING" ]]; then
	if [[ -z "$_ZSH_PATH_LOADED" ]]; then
		export _ZSH_PATH_LOADED=1
		typeset -U path PATH
		CPUTYPE=${CPUTYPE:-$HOSTTYPE}
		[[ ${OSTYPE} == darwin* ]] && [[ ${CPUTYPE} == arm* || ${CPUTYPE} == aarch64* ]] &&
			export PATH="/opt/homebrew/bin:$PATH"
		export PATH="$HOME/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bun/bin:/usr/local/go/bin:/opt/local/bin:${GOBIN:-$HOME/go/bin}:${CARGO_HOME:-$HOME/.cargo}/bin:/usr/lib/docker/cli-plugins/:$PATH"
	fi
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
	# Disable XON/XOFF immediately so ^S never freezes the terminal before
	# the deferred combined.zsh (03-history.zsh setopt no_flow_control) loads.
	# stty is an external process (~2ms); guard prevents cost in non-TTY contexts.
	setopt no_flow_control
	stty -ixon -ixoff 2>/dev/null
fi

# HISTFILE must be set before the first prompt — 03-history.zsh runs deferred and zsh
# tries to write history immediately on startup, causing a rename error if unset.
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"

# PATH setup from 00-env.zsh normally runs deferred inside combined.zsh, but sheldon
# needs tools like prmt in PATH at load time. Use the same _ZSH_PATH_LOADED guard so
# 00-env.zsh in combined.zsh won't duplicate this when it runs deferred.
if [[ -z "$_ZSH_PATH_LOADED" ]]; then
	export _ZSH_PATH_LOADED=1
	typeset -U path PATH
	CPUTYPE=${CPUTYPE:-$HOSTTYPE}
	[[ ${OSTYPE} == darwin* ]] && [[ ${CPUTYPE} == arm* || ${CPUTYPE} == aarch64* ]] &&
		export PATH="/opt/homebrew/bin:$PATH"
	export PATH="$HOME/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:/usr/local/bun/bin:/usr/local/go/bin:/opt/local/bin:${GOBIN:-$HOME/go/bin}:${CARGO_HOME:-$HOME/.cargo}/bin:/usr/lib/docker/cli-plugins/:$PATH"
fi

# Generate ATUIN_SESSION before sheldon/atuin.zsh loads so it's available even
# when ZSH_EXECUTION_STRING prevents sheldon from running (e.g. zsh -c calls).
# atuin.zsh honours a pre-set ATUIN_SESSION and only regenerates on SHLVL change.
if [[ -z "${ATUIN_SESSION}" ]]; then
	if [[ -r /proc/sys/kernel/random/uuid ]]; then
		read -r _atuin_uuid </proc/sys/kernel/random/uuid
	else
		_atuin_uuid="${$}-${EPOCHREALTIME:-$(date +%s%N)}"
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
	if [[ -f "$combined_cache" ]]; then
		if (($+functions[zsh-defer])); then
			zsh-defer source "$combined_cache"
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
		if [[ -f "$_os_cache" ]]; then
			if (($+functions[zsh-defer])); then
				zsh-defer source "$_os_cache"
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
		if [[ -f "$_gui_cache" ]]; then
			if (($+functions[zsh-defer])); then
				zsh-defer source "$_gui_cache"
			else
				source "$_gui_cache"
			fi
		else
			_zcache_eval "os-gui" 0 "cat '$_gui_src'" "$_gui_src"
		fi
	fi
fi
