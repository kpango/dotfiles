if (($+commands[atuin])); then
	# Persistent override: atuin init zsh emits ATUIN_TMUX_POPUP=false, which forces
	# the broken non-popup code path (3>&1 1>&2 2>&3 fd-swap discards the result in
	# atuin 18.x). The popup path works correctly: TUI renders on stdout (the popup
	# PTY), result goes to stderr which is redirected to a temp file for capture.
	export ATUIN_TMUX_POPUP=true

	# Both jobs below are for interactive shells only (a `zsh -c` from a script or tool
	# runner never opens the popup and need not check the daemon) and share one
	# background subshell, i.e. one fork of this shell.
	if [[ -z "$ZSH_EXECUTION_STRING" ]]; then
		local _needs_tmux_env=0
		[[ -n "${TMUX:-}" && -z "$_TMUX_ATUIN_ENV_SET" ]] && _needs_tmux_env=1

		local _needs_daemon_restart=0
		if [[ ! -f /.dockerenv ]] && (($+commands[systemctl])); then
			local _m="${ZCACHE_DIR:-$HOME/.zcache}/atuin-daemon.ver"
			local _sock="${XDG_RUNTIME_DIR:-/run/user/$UID}/atuin.sock"
			[[ -S "$_sock" ]] || _sock="${XDG_DATA_HOME:-$HOME/.data}/atuin/atuin.sock"
			[[ -S "$_sock" ]] || _sock="$HOME/.local/share/atuin/atuin.sock"

			local _is_live=0
			if [[ -S "$_sock" ]]; then
				if zmodload -F zsh/net/socket b:zsocket 2>/dev/null; then
					if zsocket "$_sock" 2>/dev/null; then
						exec {REPLY}<&-
						_is_live=1
					fi
				else
					_is_live=1
				fi
			fi
			if (( ! _is_live )) || [[ "$commands[atuin]" -nt "$_m" ]]; then
				_needs_daemon_restart=1
			fi
		fi

		if (( _needs_tmux_env || _needs_daemon_restart )); then
			(( _needs_tmux_env )) && export _TMUX_ATUIN_ENV_SET=1
			(
				if (( _needs_tmux_env )); then
					tmux set-environment -g XDG_DATA_HOME "${XDG_DATA_HOME:-$HOME/.data}" \; \
						set-environment -g XDG_CONFIG_HOME "${XDG_CONFIG_HOME:-$HOME/.config}" \; \
						set-environment -g _TMUX_ATUIN_ENV_SET 1
				fi
				if (( _needs_daemon_restart )); then
					local _m="${ZCACHE_DIR:-$HOME/.zcache}/atuin-daemon.ver"
					systemctl --user restart atuin.service 2>/dev/null
					touch "$_m"
				fi
			) &|
		fi
	fi

	# Async _atuin_preexec: the atuin-generated version runs `atuin history start`
	# synchronously via command substitution, blocking every command on atuin's own
	# process-startup cost (~140-150ms here, independent of the daemon — a 12MB
	# static binary, not an IPC cost; see AGENTS.md 2026-08-05 zsh-startup-perf).
	# This mirrors prmt's existing async-fd pattern: fire the call in the background,
	# collect the id via a zle -F callback once it's idle. If a command finishes
	# before the previous start call's id arrives, that stale fd is dropped instead
	# of risking a misattributed history end (precmd's empty-id guard then just
	# skips recording duration/exit code for that one entry).
	typeset -gi _atuin_history_start_fd=-1
	_atuin_preexec() {
		__atuin_preexec_time=${EPOCHREALTIME-}
		if (( _atuin_history_start_fd >= 0 )); then
			zle -F $_atuin_history_start_fd
			exec {_atuin_history_start_fd}<&-
		fi
		ATUIN_HISTORY_ID=""
		exec {_atuin_history_start_fd}< <(atuin history start -- "$1" 2>/dev/null)
		zle -F $_atuin_history_start_fd _atuin_history_start_callback
	}
	_atuin_history_start_callback() {
		local fd=$1 id
		IFS= read -r -u $fd id
		zle -F $fd
		exec {fd}<&-
		_atuin_history_start_fd=-1
		ATUIN_HISTORY_ID=$id
	}
	# _atuin_precmd: no override here — atuin's own generated version already
	# backgrounds `history end` (fire-and-forget). A prior override made it
	# synchronous to guarantee same-pane-vs-other-pane history ordering; that
	# traded ~140ms/command for cross-pane sync ordering and was reverted after
	# confirming the cost was atuin's binary startup, not daemon IPC (user
	# confirmed prioritizing speed — see AGENTS.md 2026-08-05 zsh-startup-perf).
fi
