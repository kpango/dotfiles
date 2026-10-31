[[ -n "$_ZSH_TMUX_LOADED" ]] && return
export _ZSH_TMUX_LOADED=1

# ── Herdr: ctrl+space prefix — no readline conflict (ctrl+a = beginning-of-line)
if (($+commands[herdr])); then
	export HERDR_SESSION="${USER:-$USERNAME}-${HOST:-$HOSTNAME}"
	# ~/.config/herdr/config.toml is a read-only bind mount in this container;
	# point herdr at the writable dotfiles source instead.
	if [[ -n "$DOTFILES_DIR" && -f "$DOTFILES_DIR/herdr/config.toml" ]]; then
		export HERDR_CONFIG_PATH="$DOTFILES_DIR/herdr/config.toml"
	fi
	# Docker container that herdr/shell execs into for every new pane
	export HERDR_DOCKER_CONTAINER="${HERDR_DOCKER_CONTAINER:-dev}"
	export HERDR_DOCKER_SHELL="${HERDR_DOCKER_SHELL:-/usr/bin/zsh}"
	# Capture panic backtraces if the server crashes silently
	export RUST_BACKTRACE=1
	export HERDR_LOG=herdr=debug
fi

if (($+commands[tmux])); then
	# Unset $TMUX if the server it points to is no longer running (stale socket).
	# Fast path on Linux checks socket file and /proc/<pid>/comm with zero forks,
	# falling back to `tmux info` on macOS or cross-PID-namespace sockets.
	if [[ -n "$TMUX" ]]; then
		_tmux_sock="${TMUX%%,*}"
		_tmux_pid="${TMUX#*,}"
		_tmux_pid="${_tmux_pid%%,*}"
		_tmux_comm=""
		if [[ ! -S "$_tmux_sock" ]] || {
			! { [[ -r "/proc/$_tmux_pid/comm" ]] && IFS= read -r _tmux_comm <"/proc/$_tmux_pid/comm" && [[ "$_tmux_comm" == tmux* ]]; } &&
				! tmux info &>/dev/null
		}; then
			unset TMUX TMUX_PANE
		fi
		unset _tmux_sock _tmux_pid _tmux_comm
	fi

	if [ -z "$_TMUX_KEYS_SET" ] && [ -n "$TMUX" ]; then
		export _TMUX_KEYS_SET=1
		if [ -f /.dockerenv ]; then
			tmux unbind C-b \; set -g prefix C-w \; bind C-w send-prefix &|
		else
			case ${OSTYPE} in
			darwin*)
				tmux unbind C-b \; set -g prefix C-g \; bind C-g send-prefix &|
				;;
			linux*)
				tmux bind C-b send-prefix &|
				;;
			esac
		fi
	fi
	alias tedit="$EDITOR $HOME/.tmux.conf"

	if [[ -f /.dockerenv ]]; then
		# Clean up the per-exec servers below: kill those with no client and drop dead
		# sockets. -a kills every server but the current one, attached or not -- closing a
		# docker exec on the host can leave its tmux client running inside the container.
		tmuxgc() {
			emulate -L zsh -o null_glob
			local all=0 s n
			[[ "$1" == -a ]] && all=1
			for s in /var/tmp/tmux-$UID/*.sock; do
				[[ "$s" == "${TMUX%%,*}" ]] && continue
				if ! tmux -S "$s" has-session 2>/dev/null; then
					command rm -f -- "$s" && echo "removed dead socket $s"
					continue
				fi
				n=$(tmux -S "$s" list-clients 2>/dev/null | wc -l)
				if ((all || n == 0)); then
					tmux -S "$s" kill-server && command rm -f -- "$s" && echo "killed $s (clients: $n)"
				fi
			done
		}
	fi

	# If not inside a tmux session
	if [[ -z "$TMUX" && -o interactive ]]; then
		USER=${USER:-$USERNAME}
		HOST=${HOST:-$HOSTNAME}

		# Refresh ~/.zcache/tmux-* from ~/.tmux.conf.d/ when missing or stale.
		# Handles cold-start containers where ~/.zcache is empty but ~/.tmux.conf.d is mounted.
		if [[ -d "$HOME/.tmux.conf.d" ]]; then
			[[ -d "$HOME/.zcache" ]] || mkdir -p "$HOME/.zcache"
			for _tmux_pair in "kube:tmux-kube" "status-left:tmux-status-left" "short-path:tmux-short-path" "status-branch:tmux-status-branch"; do
				_tmux_src="$HOME/.tmux.conf.d/${_tmux_pair%%:*}"
				_tmux_dst="$HOME/.zcache/${_tmux_pair##*:}"
				if [[ -f "$_tmux_src" ]] && { [[ ! -f "$_tmux_dst" ]] || [[ "$_tmux_src" -nt "$_tmux_dst" ]]; }; then
					cp "$_tmux_src" "$_tmux_dst" && chmod +x "$_tmux_dst" && zcompile "$_tmux_dst" 2>/dev/null
				fi
			done
			unset _tmux_pair _tmux_src _tmux_dst
		fi

		export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"
		mkdir -p "$TMUX_PLUGIN_MANAGER_PATH"
		# One-time only: gated on tpm's absence, so this network clone never runs
		# again once installed -- no recurring startup cost on subsequent shells.
		if [ ! -d "$TMUX_PLUGIN_MANAGER_PATH/tpm" ]; then
			echo "Installing Tmux Plugin Manager..."
			git clone --depth 1 --recursive https://github.com/tmux-plugins/tpm "$TMUX_PLUGIN_MANAGER_PATH/tpm"
		fi

		SESSION_NAME="${USER}@${HOST}"

		if [[ -f /.dockerenv ]]; then
			# ── Docker: one server per exec, nested inside the host tmux ───────
			# /tmp is bind-mounted from the host and shared by every container (whose hostname
			# is the host's, too), so sockets live in /var/tmp, which is container-local.
			# Each exec gets its own server ($$), which survives detach; reattach with
			# `tmux -S /var/tmp/tmux-$UID/<pid>.sock attach`. Prefix is C-w via options.conf.
			mkdir -p -m 700 "/var/tmp/tmux-$UID"
			TMUX_SOCK="/var/tmp/tmux-$UID/$$.sock"
			if [[ -S /var/run/docker.sock ]] && ! [ -w /var/run/docker.sock ]; then
				sudo chown -R "$USER:$GID" /var/run/docker.sock ||
					echo "warning: failed to chown docker.sock — docker commands may need sudo" >&2
			fi
			# exec replaces this shell process with tmux: nothing after this line in
			# .zshrc runs for this shell -- a fresh zshrc runs inside each tmux pane.
			exec tmux -u -2 -S "$TMUX_SOCK" new-session -A -s "$SESSION_NAME-$$"
		else
			# ── Host / SSH: single shared session via persistent socket ────────
			# Socket: /run/user/$UID when systemd-logind is active; $HOME/.tmux/ otherwise.
			# /run/user/$UID is created by systemd-logind for any logged-in user,
			# but $XDG_RUNTIME_DIR is not propagated to SSH sessions without pam_systemd.
			_TMUX_UID="${UID:-$(id -u)}"
			if [[ -d "/run/user/$_TMUX_UID" ]]; then
				TMUX_SOCK="/run/user/$_TMUX_UID/tmux-main.sock"
			else
				mkdir -p "$HOME/.tmux"
				TMUX_SOCK="$HOME/.tmux/tmux-main.sock"
			fi
			unset _TMUX_UID
			export TMUX_SOCK

			# Ensure the server is running.
			# Prefer systemd (which also creates the session), fall back to direct start.
			if ! tmux -S "$TMUX_SOCK" has-session 2>/dev/null; then
				if (($+commands[systemctl])) && systemctl --user is-enabled tmux.service &>/dev/null; then
					# tmux.service is Type=oneshot+RemainAfterExit: once the server has died the unit
					# stays "active" and start would be a no-op, so reload (ExecReload re-runs the
					# idempotent ExecStart) recreates it. Never restart here: its ExecStop and the
					# cgroup kill would destroy a live server when has-session fails spuriously.
					# start covers a unit that was never started. Two shells racing right after
					# server death can still collide; rare.
					systemctl --user reload tmux.service 2>/dev/null || systemctl --user start tmux.service 2>/dev/null
					# Wait for the socket; tmux leaves a stale socket file behind after the server
					# exits, so this can return at once, in which case the exec below still
					# reaches a server via new-session -A. Bounded at ~3s (30 * 0.1s).
					_tmux_wait=0
					while [[ ! -S "$TMUX_SOCK" ]] && ((_tmux_wait++ < 30)); do sleep 0.1; done
					unset _tmux_wait
				fi
				# Direct fallback for non-systemd environments or if service start timed out
				if [[ ! -S "$TMUX_SOCK" ]]; then
					tmux -u -2 -S "$TMUX_SOCK" new-session -d -s "$SESSION_NAME"
				fi
			fi

			# exec replaces this shell process with tmux (auto-attach design, same as
			# the Docker branch above): nothing after this line in .zshrc runs for this
			# shell -- the tmux client takes over and a fresh zshrc runs inside each pane.
			exec tmux -u -2 -S "$TMUX_SOCK" new-session -A -s "$SESSION_NAME"
		fi
	fi
fi
