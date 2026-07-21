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

	# Synchronous _atuin_precmd: with the daemon running, atuin history end goes via
	# Unix socket (~sub-ms), so removing the background & doesn't add latency but
	# guarantees the entry is in the DB before the next prompt — visible in all panes.
	_atuin_precmd() {
		local EXIT="$?" __atuin_precmd_time=${EPOCHREALTIME-}
		[[ -z "${ATUIN_HISTORY_ID:-}" ]] && return
		local duration=""
		if [[ -n $__atuin_preexec_time && -n $__atuin_precmd_time ]]; then
			printf -v duration %.0f $(((__atuin_precmd_time-__atuin_preexec_time) * 1000000000))
		fi
		ATUIN_LOG=error atuin history end --exit $EXIT ${duration:+--duration=$duration} -- $ATUIN_HISTORY_ID 2>/dev/null
		export ATUIN_HISTORY_ID=""
	}
fi
