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
	# This allows the auto-attach logic below to reconnect to the live server.
	if [[ -n "$TMUX" ]] && ! tmux info &>/dev/null; then
		unset TMUX TMUX_PANE
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

	# Refresh ~/.zcache/tmux-* from ~/.tmux.conf.d/ when missing or stale.
	# Handles cold-start containers where ~/.zcache is empty but ~/.tmux.conf.d is mounted.
	if [[ -d "$HOME/.tmux.conf.d" ]]; then
		mkdir -p "$HOME/.zcache"
		for _tmux_pair in "kube:tmux-kube" "status-left:tmux-status-left" "short-path:tmux-short-path"; do
			_tmux_src="$HOME/.tmux.conf.d/${_tmux_pair%%:*}"
			_tmux_dst="$HOME/.zcache/${_tmux_pair##*:}"
			if [[ -f "$_tmux_src" ]] && { [[ ! -f "$_tmux_dst" ]] || [[ "$_tmux_src" -nt "$_tmux_dst" ]]; }; then
				cp "$_tmux_src" "$_tmux_dst" && chmod +x "$_tmux_dst" && zcompile "$_tmux_dst" 2>/dev/null
			fi
		done
		unset _tmux_pair _tmux_src _tmux_dst
	fi

	# If not inside a tmux session
	if [[ -z "$TMUX" && -o interactive ]]; then
		USER=${USER:-$USERNAME}
		HOST=${HOST:-$HOSTNAME}

		export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"
		mkdir -p "$TMUX_PLUGIN_MANAGER_PATH"
		if [ ! -d "$TMUX_PLUGIN_MANAGER_PATH/tpm" ]; then
			echo "Installing Tmux Plugin Manager..."
			git clone --depth 1 --recursive https://github.com/tmux-plugins/tpm "$TMUX_PLUGIN_MANAGER_PATH/tpm"
		fi

		SESSION_NAME="${USER}@${HOST}"

		if [[ -f /.dockerenv ]]; then
			# ── Docker: single shared server per container ─────────────────────
			# /tmp is always writable; systemd-tmpfiles-clean does not run inside containers.
			TMUX_SOCK="/tmp/tmux-main.sock"
			if [[ -S /var/run/docker.sock ]] && ! [ -w /var/run/docker.sock ]; then
				sudo chown -R "$USER:$GID" /var/run/docker.sock
			fi
			if ! tmux -S "$TMUX_SOCK" has-session 2>/dev/null; then
				tmux -u -2 -S "$TMUX_SOCK" new-session -d -s "$SESSION_NAME"
			fi
			exec tmux -u -2 -S "$TMUX_SOCK" new-session -A -s "$SESSION_NAME"
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
					systemctl --user start tmux.service 2>/dev/null
					_tmux_wait=0
					while [[ ! -S "$TMUX_SOCK" ]] && ((_tmux_wait++ < 30)); do sleep 0.1; done
					unset _tmux_wait
				fi
				# Direct fallback for non-systemd environments or if service start timed out
				if [[ ! -S "$TMUX_SOCK" ]]; then
					tmux -u -2 -S "$TMUX_SOCK" new-session -d -s "$SESSION_NAME"
				fi
			fi

			exec tmux -u -2 -S "$TMUX_SOCK" new-session -A -s "$SESSION_NAME"
		fi
	fi
fi
