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

	# Determine DOTFILES_DIR. This is the only place that actually detects it --
	# zfunc/_gen_env doesn't duplicate this logic, it just bakes the value this
	# block resolves into the generated $ZCACHE_DIR/env.zsh cache (its `print
	# "export DOTFILES_DIR=\"$DOTFILES_DIR\""` line is a consumer, not a second
	# detector). It has to run here, before fpath below can even include
	# $DOTFILES_DIR/zfunc, so _gen_env couldn't be autoloaded yet regardless.
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
	# $HOME/.gitconfig is a data dependency, not a logic one: _gen_env's committer
	# block reads `git config --global user.*` at generation time, so a `git config
	# --global user.email ...` edit needs to invalidate this cache the same way an
	# edit to _gen_env's own code does, or the old identity would keep baking in
	# indefinitely (same failure mode the comment above already names).
	_zcache_eval env 0 "_gen_env" "$DOTFILES_DIR/zfunc/_base_path" "$DOTFILES_DIR/zfunc/_gen_env" "$HOME/.gitconfig"
	# _zcache_eval sources the regenerated env.zsh inside a function, so its baked
	# `typeset -U path PATH` is function-local and the PATH it exports is lost on return.
	# Non-exported flag: makes the pre-01-tmux.zsh block below rebuild PATH itself.
	_zsh_cold_env=1
fi

# Reached when a tool explicitly sources ~/.zshrc from a `zsh -c` (e.g. Claude Code's shell
# snapshot), despite zshenv's unsetopt RCS -- do not remove as dead code.
# Fast path for inline script execution (-c flag): env.zsh provides PATH and core env.
# Skip all interactive-only setup (plugins, completions, prompt, ZLE bindings).
# PATH fallback ensures commands work even if env.zsh cache is missing or stale.
if [[ -n "$ZSH_EXECUTION_STRING" ]]; then
	# Deliberately unconditional, not gated on _ZSH_PATH_LOADED: that guard is
	# exported, so it can already read 1 here purely from environment inheritance
	# (an ancestor process ran this before), independent of whether *this*
	# process's own PATH actually has _base_path's dirs. Skipping on an inherited
	# guard risks silently keeping an incomplete PATH; always rebuilding is cheap
	# (one _base_path call, no fork since `_base_path -v`; deduped by typeset -U)
	# and correct regardless of ancestry — see zsh/00-env.zsh for the fuller version of this reasoning.
	export _ZSH_PATH_LOADED=1
	# _apply_base_path (zfunc/) holds the typeset -g -U / _base_path / export
	# triplet shared with 00-env.zsh and the synchronous call below — see its
	# header for why -g matters even though this call site itself runs at the
	# top level, not inside a function.
	autoload -Uz _apply_base_path
	_apply_base_path
	# Load functions/aliases from zcache for non-interactive shells (e.g., Claude Code, scripts)
	if [[ -z "$_ZSH_FUNCS_LOADED" ]]; then
		export _ZSH_FUNCS_LOADED=1
		_zc="${ZCACHE_DIR:-$HOME/.zcache}"
		[[ -f "$_zc/combined.zsh" ]] && source "$_zc/combined.zsh" 2>/dev/null
		[[ -n "$_ZSH_OS" && -f "$_zc/os-${_ZSH_OS}.zsh" ]] && source "$_zc/os-${_ZSH_OS}.zsh" 2>/dev/null
	fi
	return
fi

# Per-name $commands lookups only until the end of this file (see zshenv's fast path):
# with HASH_LIST_ALL the first one hashes all of PATH (~1.9ms), and with HASH_DIRS
# (on here; zsh itself leaves it off for `zsh -c`) each one after a PATH change hashes
# every directory up to the match (~0.8ms for /usr/bin) -- all before the first prompt.
# Both only change how lookups are cached; a per-name lookup finds the same command.
# Restored at the end of this file, so the deferred tasks already run with them on.
unsetopt HASH_LIST_ALL HASH_DIRS
# zsh 5.9 (e.g. the Ubuntu dev container) has no per-name fallback: every $commands
# lookup then misses. Probe and keep the full hash there (as in zshenv).
(($+commands[zsh])) || setopt HASH_LIST_ALL

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

# Source tmux auto-start synchronously to avoid a visible prompt flash before tmux launches.
# Shells OUTSIDE tmux (-z "$TMUX") source 01-tmux.zsh here, before the TTY-only setup and
# sheldon: such a shell normally ends in `exec tmux`, which discards all of that work.
# Shells INSIDE tmux (-n "$TMUX") normally do not exec (only a stale $TMUX does), so they source it at its original position,
# right after the sheldon block below; running it early there would fill zsh's command hash
# from the inherited PATH only for the later _apply_base_path to flush it again.
# 01-tmux.zsh needs DOTFILES_DIR and a PATH with tmux/herdr/git/systemctl; a
# cache-hit env.zsh bakes that PATH (non-darwin), but it is missing when (a) this is darwin
# (env.zsh never bakes PATH there), (b) env.zsh was just regenerated (_zsh_cold_env, see
# above) or (c) tmux is not resolvable. Only then is _apply_base_path run here, ahead of
# 01-tmux.zsh (and of any tmux server it starts, which inherits PATH); _zsh_early_base
# makes the synchronous call further down skip its redundant second _base_path call.
# Both flags are plain, non-exported shell variables so they never leak to children, unlike
# the exported _ZSH_PATH_LOADED guard (which is deliberately not trusted, see below).
# EDITOR comes from the deferred zsh/10-editor.zsh both before and after this placement.
# Also skipped when _ZSH_TMUX_LOADED is inherited: 01-tmux.zsh would return at once, and the
# $+commands probe below would only build a command hash that _apply_base_path then discards.
if [[ -z "$ZSH_EXECUTION_STRING" && -t 0 && -n "$DOTFILES_DIR" && -z "$TMUX" && -z "$_ZSH_TMUX_LOADED" ]]; then
	if [[ "$_ZSH_OS" == brew || -n "$_zsh_cold_env" ]] || ! (($+commands[tmux])); then
		autoload -Uz _apply_base_path
		_apply_base_path
		_zsh_early_base=1
	fi
	source "$DOTFILES_DIR/zsh/01-tmux.zsh"
fi

# TTY-only setup: these only matter when ZLE will actually run
if [[ -t 0 ]]; then
	# Plugin env vars must be set before sheldon loads zsh-autosuggestions
	export ZSH_AUTOSUGGEST_USE_ASYNC=1
	export ZSH_AUTOSUGGEST_MANUAL_REBIND=1
	export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=60
	export ZSH_AUTOSUGGEST_STRATEGY=(history)
	export ZSH_AUTOSUGGEST_IGNORE_WIDGETS+=(
		forward-char backward-char forward-word backward-word
		vi-forward-char vi-backward-char vi-forward-word vi-backward-word
		beginning-of-line end-of-line
	)
	export WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'
	bindkey -e
	export KEYTIMEOUT=1

	# Completion caching and smart matching for instantaneous Tab responsiveness
	zstyle ':completion:*' use-cache on
	zstyle ':completion:*' cache-path "${ZCACHE_DIR:-$HOME/.zcache}/zcompcache"
	zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*'

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
	unsetopt auto_name_dirs
	# stty -ixon -ixoff disables the terminal driver's own ^S/^Q flow control. This is
	# NOT the same thing as no_flow_control set above: no_flow_control only tells zsh's
	# own line editor to not treat ^S/^Q specially while ZLE is active — it does not
	# touch the pty's actual termios IXON/IXOFF bits, which is what still freezes a
	# foreground child (less/vim/cat/etc.) on an accidental ^S. Verified 2026-08-19
	# with a pty harness: `setopt no_flow_control` alone did not stop a foreground
	# job's output from freezing on ^S, so this call cannot be deleted.
	#
	# Deferring this via zsh-defer was tried and reverted: zsh-defer runs its queued
	# tasks from inside a `zle -F` callback, and ZLE restores the termios settings it
	# saved on entry when that callback returns, discarding whatever stty changed
	# during it. Measured 2026-08-19 with a pty harness: synchronous stty here left
	# IXON off as intended; the same call run via zsh-defer left IXON on (no-op), and
	# a foreground command actually froze on ^S in that configuration. It's an
	# external process (~7ms measured 2026-08-19) but must run synchronously,
	# before ZLE starts.
	#
	# Moving it into a `zle-line-init` widget (add-zle-hook-widget, same idiom sheldon.toml's
	# prmt plugin uses for _prmt_zle_init) was also tried and reverted: it hits the exact
	# same revert bug as zsh-defer, not a different code path. Confirmed 2026-08-19 with a
	# pty harness across 2 warmup commands+a real ^S/^Q foreground-loop test: `stty -a`
	# read back `ixon` (no leading dash, i.e. ON) after the hook ran, and a foreground loop
	# genuinely froze on ^S (1 line arrived in a 1.5s window that should have carried ~28-30
	# at the loop's own cadence, matching the freeze signature of an explicit `stty ixon
	# ixoff` positive control). zle-line-init fires only once ZLE's own raw-mode session is
	# already active, which is exactly the "mid-session" timing that gets discarded on exit —
	# the same trap as zsh-defer, just reached via a different hook. Also measured no
	# meaningful first-prompt-byte latency difference either way (hyperfine, n=20:
	# 84.8ms ± 13.9ms baseline vs 81.5ms ± 16.8ms candidate — within noise). Do not
	# re-attempt via any hook that fires after the first zle-line-init; this must stay
	# synchronous, before ZLE ever starts.
	stty -ixon -ixoff 2>/dev/null
fi

# HISTFILE must be set before the first prompt — 03-history.zsh runs deferred and zsh
# tries to write history immediately on startup, causing a rename error if unset.
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"

# PATH setup from 00-env.zsh normally runs deferred inside combined.zsh, but sheldon
# needs tools like prmt in PATH at load time here, synchronously, before that.
#
# Skipped only when the early call before 01-tmux.zsh already rebuilt PATH in this
# same process (the non-exported _zsh_early_base flag, set only in the early block for
# shells outside tmux); otherwise unconditional.
# Never gated on _ZSH_PATH_LOADED: an exported guard
# already reading 1 here only means some ancestor process ran this before, not that
# *this* process's own PATH has _base_path's dirs (confirmed 2026-08-19: this exact
# guard-inherited-but-PATH-incomplete gap reproduced a PATH-loss bug on darwin one
# process removed via tmux/nested-shell inheritance). Always rebuilding is cheap —
# a single _base_path call, deduped by typeset -U — and correct regardless of
# ancestry. Downstream, 00-env.zsh's own guard still skips its redundant copy of
# this on non-darwin once this has run; on darwin it always re-derives PATH from
# scratch after its own PATH="" reset regardless, so this cannot go stale there.
export _ZSH_PATH_LOADED=1
# _apply_base_path (zfunc/) holds the typeset -g -U / _base_path / export
# triplet shared with 00-env.zsh, the fast-path call and the early call above — see its header
# for why -g matters even though this call site itself runs at the top level,
# not inside a function.
autoload -Uz _apply_base_path
[[ -n "$_zsh_early_base" ]] || _apply_base_path
unset _zsh_cold_env _zsh_early_base

# Load sheldon only when stdin is a TTY — all deferred tasks require ZLE-idle (never fires
# for non-TTY), and prmt is independently guarded. Skipping for pipe/file stdin saves ~3ms.
if [[ -z "$ZSH_EXECUTION_STRING" && -t 0 ]] && (($+commands[sheldon])); then
	_zcache_eval sheldon 0 "sheldon source" \
		"${XDG_CONFIG_HOME:-$HOME/.config}/sheldon/plugins.toml"
fi

# Shells inside tmux: 01-tmux.zsh at its original position (the early block above covers
# shells outside tmux). It still unsets a stale $TMUX and may then exec tmux from here.
if [[ -z "$ZSH_EXECUTION_STRING" && -t 0 && -n "$DOTFILES_DIR" && -n "$TMUX" ]]; then
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
	autoload -Uz _source_deferred
	# Combined cache: all zsh/*.zsh except OS-specific files (20-os-*.zsh)
	combined_cache="$ZCACHE_DIR/combined.zsh"
	# Freshness via a single native glob (no subshell/loop): editing an existing
	# file's *contents* previously went undetected here (only "cache file exists?"
	# was checked), so combined.zsh kept sourcing stale code until a manual
	# `zclean` — silently, indefinitely. (N.om[1]) is over-inclusive (also covers
	# 20-os-*.zsh/01-tmux.zsh, which combined.zsh doesn't contain) but that only
	# costs an occasional unnecessary rebuild, never a missed one. An array assignment:
	# a scalar one does not glob (GLOB_ASSIGN is off), so it used to hold the literal
	# pattern, which is never -nt anything, and the check always passed.
	_newest_zsh=("$DOTFILES_DIR/zsh"/*.zsh(N.om[1]))
	if [[ -f "$combined_cache" && ( -z "$_newest_zsh[1]" || ! "$_newest_zsh[1]" -nt "$combined_cache" ) ]]; then
		# -t 0.01 starts a new yield chunk (see sheldon.toml, above [plugins.colors]):
		# sourcing this cache is the single most expensive deferred task, so it must not
		# share a zle callback with the plugin tasks queued before it.
		_source_deferred "$combined_cache" "-mpr -t 0.01"
	else
		_zsh_deps=()
		for _f in "$DOTFILES_DIR/zsh"/*.zsh; do
			[[ -e "$_f" ]] || continue
			[[ "${_f:t}" = 20-os-*.zsh || "${_f:t}" = 01-tmux.zsh ]] || _zsh_deps+=("$_f")
		done
		_zcache_eval combined 0 \
			'for _f in "$DOTFILES_DIR/zsh"/*.zsh; do [[ "${_f:t}" = 20-os-*.zsh || "${_f:t}" = 01-tmux.zsh ]] || cat "$_f"; done' \
			"${_zsh_deps[@]}"
	fi

	# OS-specific cache: only the file matching the detected OS
	_os_src="$DOTFILES_DIR/zsh/20-os-${_ZSH_OS}.zsh"
	if [[ -f "$_os_src" ]]; then
		_os_cache="$ZCACHE_DIR/os-${_ZSH_OS}.zsh"
		if [[ -f "$_os_cache" && ! "$_os_src" -nt "$_os_cache" ]]; then
			_source_deferred "$_os_cache" "-mpr"
		else
			_zcache_eval "os-${_ZSH_OS}" 0 "cat '$_os_src'" "$_os_src"
		fi
	fi

	# GUI-specific cache: always loaded on top of the OS file
	_gui_src="$DOTFILES_DIR/zsh/20-os-gui.zsh"
	if [[ -f "$_gui_src" && "$_gui_src" != "$_os_src" ]]; then
		_gui_cache="$ZCACHE_DIR/os-gui.zsh"
		if [[ -f "$_gui_cache" && ! "$_gui_src" -nt "$_gui_cache" ]]; then
			_source_deferred "$_gui_cache" "-mpr"
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

setopt HASH_LIST_ALL HASH_DIRS

# Appended by an installer writing through the ~/.zshrc -> repo symlink. Guarded
# because the target does not exist on every machine, and an unguarded `.` of a
# missing file prints an error on every interactive shell start. An `if`, not
# `[ -f ] && .`: as the last command its status 1 became $? for the first prompt,
# which prmt then rendered as a failed command (red "✗ 1").
if [ -f "$HOME/bin/env" ]; then
	. "$HOME/bin/env"
fi
