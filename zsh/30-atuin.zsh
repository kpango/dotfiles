if (($+commands[atuin])); then
	# Persistent override: atuin init zsh emits ATUIN_TMUX_POPUP=false, which forces
	# the broken non-popup code path (3>&1 1>&2 2>&3 fd-swap discards the result in
	# atuin 18.x). The popup path works correctly: TUI renders on stdout (the popup
	# PTY), result goes to stderr which is redirected to a temp file for capture.
	export ATUIN_TMUX_POPUP=true

	# The tmux popup runs sh -c and only inherits the tmux session environment, not
	# the current shell's exported vars. XDG_DATA_HOME/XDG_CONFIG_HOME are set in
	# combined.zsh (00-env.zsh) but not in tmux's session env, so atuin falls back
	# to ~/.local/share/atuin and fails if that path has a stale symlink.
	if [[ -n "${TMUX:-}" ]]; then
		tmux set-environment XDG_DATA_HOME "${XDG_DATA_HOME:-$HOME/.data}"
		tmux set-environment XDG_CONFIG_HOME "${XDG_CONFIG_HOME:-$HOME/.config}"
	fi

	# On the host only (not inside a container): restart the atuin daemon when the
	# binary is newer than the last-restart marker. A stale daemon (version mismatch)
	# causes atuin to fall back to direct SQLite writes, breaking real-time sync
	# between tmux panes and the dev container. auto_start=false in config prevents
	# atuin from silently spawning a second daemon on connection failure.
	if [[ ! -f /.dockerenv ]] && (($+commands[systemctl])); then
		(
			local _m="${ZCACHE_DIR:-$HOME/.zcache}/atuin-daemon.ver"
			local _ds
			_ds=$(atuin daemon status 2>/dev/null)
			if ! echo "$_ds" | rg -qF 'Daemon running'; then
				# Daemon is down — restart unconditionally (e.g. after container stop)
				systemctl --user restart atuin.service 2>/dev/null
				touch "$_m"
			elif echo "$_ds" | rg -qF 'needs restart'; then
				# Version mismatch — only restart if binary was updated since last check
				if [[ "$commands[atuin]" -nt "$_m" ]]; then
					systemctl --user restart atuin.service 2>/dev/null
				fi
				touch "$_m"
			elif [[ "$commands[atuin]" -nt "$_m" ]]; then
				# Daemon healthy and binary updated — just refresh marker
				touch "$_m"
			fi
		) &|
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
