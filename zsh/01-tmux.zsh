if (($+commands[tmux])); then
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

	# If not inside a tmux session
	if [[ -z "$TMUX" && -o interactive ]]; then
		echo "welcome to tmux"
		USER=${USER:-$USERNAME}
		HOST=${HOST:-$HOSTNAME}
		TMUX_TMPDIR_PREFIX="/tmp/tmux-sockets/${UID}"
		TMUX_TMPDIR="$TMUX_TMPDIR_PREFIX/$HOST"
		# If connected via SSH
		if [ ! -z "$SSH_CLIENT" ]; then
			SSH_IP="${SSH_CLIENT%% *}"
			TMUX_TMPDIR="$TMUX_TMPDIR_PREFIX/ssh/$SSH_IP"
			echo "starting tmux for ssh $SSH_TTY from $SSH_CLIENT"
		fi
		export TMUX_TMPDIR=$TMUX_TMPDIR

		_ensure_dir() {
			if [ ! -d "$1" ]; then
				if mkdir -p "$1"; then
					echo "Successfully created $2 directory on $1."
				else
					echo "Failed to create $2 directory on $1."
					exit 1
				fi
			fi
		}

		_ensure_dir "$TMUX_TMPDIR" "tmux temp"
		chmod 700 "$TMUX_TMPDIR"
		export TMUX_PLUGIN_MANAGER_PATH="$HOME/.tmux/plugins"
		_ensure_dir "$TMUX_PLUGIN_MANAGER_PATH" "tmux plugin"

		TPM_PATH="$TMUX_PLUGIN_MANAGER_PATH/tpm"
		if [ ! -d $TPM_PATH ]; then
			echo "Installing Tmux Plugin Manager..."
			git clone --depth 1 --recursive https://github.com/tmux-plugins/tpm $TPM_PATH
		fi

		if [[ -f /.dockerenv ]] && [[ -S /var/run/docker.sock ]] && ! [ -w /var/run/docker.sock ]; then # Docker specific settings
			group=$GID
			# Ensure the user has access to the Docker socket
			sudo chown -R $USER:$group /var/run/docker.sock
		fi
		# Determine Session Name & Socket Path based on SSH context
		SESSION_NAME="${USER}@${HOST}"
		echo "Attaching to tmux session: $SESSION_NAME at $TMUX_TMPDIR"
		# Try to attach to the session, or create it if it doesn't exist.
		# -u: Force UTF-8
		# -2: Force 256 colors
		# new-session -A: Attach if exists, create if not (Atomic operation)
		# -s: Session name
		if TMUX_TMPDIR=$TMUX_TMPDIR tmux -u -2 new-session -A -n "$USER" -s "$SESSION_NAME"; then
			echo "finished tmux session for $TMUX_TMPDIR:$SESSION_NAME"
		else
			echo "failed to create/attach tmux session for $TMUX_TMPDIR:$SESSION_NAME"
			exit 1
		fi
		exit
	fi
fi
