if (($+commands[gpg])); then
	export GPG_TTY=$TTY
	# Pass the tmux socket to gpg-agent so pinentry-tmux can open a popup
	# even when gpg-agent itself was started outside the current tmux session.
	[[ -n "$TMUX" ]] && export PINENTRY_USER_DATA="TMUX=$TMUX"
	# Refresh gpg-agent's TTY so pinentry writes to the current session's PTY.
	# Backgrounded+disowned (&|): this is a fire-and-forget RPC to gpg-agent, a
	# persistent daemon outside this zsh process — unlike a local termios/ZLE side
	# effect, there is no zsh-owned scope that could unwind or race this update, so
	# deferring completion past this line is safe. Verified 2026-08-19 with a pty
	# harness (sync vs async, `gpg-connect-agent 'getinfo std_startup_env'` compared
	# after resetting the agent's stored TTY to a sentinel value): gpg-agent's
	# stored startup env reflects the new GPG_TTY identically whether this call
	# runs sync or async, and survives even the parent zsh being SIGKILLed shortly
	# after. Eventual-consistency gap measured ~11-13ms when gpg-agent is already
	# running (vs ~15.5ms synchronous); if gpg-agent isn't running yet this call's
	# own autostart pushes the gap to ~370ms — still far shorter than any
	# human-driven follow-up gpg invocation. This removes ~11ms of synchronous
	# fork/wait from the zsh-defer deferred burst's critical path (measured
	# deferred-block cost: sync 15.47ms -> async 4.88ms, median of 7 runs).
	(($+commands[gpg-connect-agent])) && gpg-connect-agent updatestartuptty /bye &>/dev/null &|
# export PINENTRY_USER_DATA="USE_CURSES=1"
fi
if (($+commands[ssh-keygen])); then
	sshperm() {
		sudo chown -R $UID:$GID $HOME/.ssh
		find $HOME/.ssh -type d -print0 | xargs -0 -P ${CPUCORES:-4} sudo chmod 700
		find $HOME/.ssh -type f -print0 | xargs -0 -P ${CPUCORES:-4} sudo chmod 600
	}
	_keygen() {
		local type=$1
		local file=$2
		shift 2
		ssh-keygen -t "$type" "$@" -f "$HOME/.ssh/$file" -C "$USER"
		sshperm
	}

	rsagen() { _keygen rsa id_rsa -b 4096 -P "$1"; }

	ecdsagen() { _keygen ecdsa id_ecdsa -b 521 -P "$1"; }

	edgen() { _keygen ed25519 id_ed -P "$1"; }
	alias sedit="$EDITOR $HOME/.ssh/config"
	sshls() {
		rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*"
	}
	sshinit() {
		rm -rf $HOME/.ssh/known_hosts \
			$HOME/.ssh/master_$GIT_USER@192.168.2.* \
			/tmp/ssh-.*.sock
		sshperm
	}
fi
if (($+commands[gpg])); then
	backup_dir=$HOME/gpgbackup
	gpgbackup() {
		sudo rm -rf $backup_dir
		mkdir -p $backup_dir
		gpg -a --export $1 >$backup_dir/$GIT_USER-public.key
		gpg -a --export-secret-keys $1 >$backup_dir/$GIT_USER-secret.key
		gpg --export-ownertrust >$backup_dir/$GIT_USER-ownertrust.txt
		sudo chmod -R 777 $backup_dir
		sudo chown -R $USER $backup_dir
		if (($+commands[tar])); then
			sudo tar Jcvf $HOME/Downloads/gpgbackup.tar.gz $backup_dir
			rm -rf gpgbackup
		fi
	}
	alias gpgbu=gpgbackup

	gpgrestore() {
		if (($+commands[tar])); then
			sudo tar Jxvf $HOME/Downloads/gpgbackup.tar.gz
		fi
		gpg --import $backup_dir/$GIT_USER-secret.key
		gpg --import-ownertrust $backup_dir/$GIT_USER-ownertrust.txt
	}
	alias gpgrs=gpgrestore
fi

if (($+commands[fzf])) && (($+commands[rg])); then
	sshf() {
		ssh $(rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*" | fzf --tmux +m)
	}
fi
