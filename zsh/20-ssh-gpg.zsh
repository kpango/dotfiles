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
		sudo chown -R "${UID}:${GID:-$(id -g)}" "$HOME/.ssh" &&
			find "$HOME/.ssh" -type d -print0 | xargs -0 -P "${CPUCORES:-4}" sudo chmod 700 &&
			find "$HOME/.ssh" -type f -print0 | xargs -0 -P "${CPUCORES:-4}" sudo chmod 600
	}
	_keygen() {
		local type=$1
		local file=$2
		shift 2
		# No -P/-N here: an explicit passphrase argument would sit in this process's
		# argv (visible to any other user via ps/procfs) for the command's duration.
		# ssh-keygen prompts interactively for the passphrase instead when neither
		# flag is given, which never exposes it outside the terminal.
		ssh-keygen -t "$type" "$@" -f "$HOME/.ssh/$file" -C "$USER" || return
		sshperm
	}

	# $1, if given, used to be forwarded as the passphrase (see _keygen's comment
	# on why that's no longer accepted); warn instead of silently discarding it,
	# since callers relying on the old argv-passphrase behavior would otherwise
	# get no indication ssh-keygen is about to prompt interactively instead.
	rsagen() { [ -n "$1" ] && echo "note: passphrase argument ignored, ssh-keygen will prompt"; _keygen rsa id_rsa -b 4096; }

	ecdsagen() { [ -n "$1" ] && echo "note: passphrase argument ignored, ssh-keygen will prompt"; _keygen ecdsa id_ecdsa -b 521; }

	edgen() { [ -n "$1" ] && echo "note: passphrase argument ignored, ssh-keygen will prompt"; _keygen ed25519 id_ed; }
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
	gpgbackup() {
		local backup_dir="$HOME/gpgbackup"
		sudo rm -rf "$backup_dir" || return
		# umask 077 so the directory and every exported key file land as
		# owner-only from creation, not the default-umask 0755/0644 --
		# without this, mkdir/gpg's export redirects leave the secret key
		# world-readable for the window between here and the chmod below.
		# Also chained with && plus explicit -s checks (not independent
		# statements, and not just relying on gpg's own exit status): a wrong
		# key id makes `gpg -a --export` print "WARNING: nothing exported" to
		# stderr but still exit 0 with empty stdout (verified against gpg
		# 2.4.9) -- && alone would not catch that, and the chmod/tar below
		# would then happily ship an empty "secret key". No -s check on the
		# ownertrust file: it's legitimately empty when no trust has been set.
		if ! (
			umask 077
			mkdir -p "$backup_dir" &&
				gpg -a --export "$1" > "$backup_dir/${GIT_USER}-public.key" &&
				[ -s "$backup_dir/${GIT_USER}-public.key" ] &&
				gpg -a --export-secret-keys "$1" > "$backup_dir/${GIT_USER}-secret.key" &&
				[ -s "$backup_dir/${GIT_USER}-secret.key" ] &&
				gpg --export-ownertrust > "$backup_dir/${GIT_USER}-ownertrust.txt"
		); then
			print -u2 "gpgbackup: failed to export GPG keys (empty export? check the key id), aborting"
			return 1
		fi
		# Owner-only: this directory holds an exported GPG *secret* key, so
		# there is no reason for group/other to read or write it.
		sudo chmod -R u+rwX,go-rwx "$backup_dir"
		sudo chown -R "$USER" "$backup_dir"
		if (($+commands[tar])); then
			# No sudo: backup_dir is already owner-chown'd above (and created
			# owner-only by the umask 077 block before that -- the `sudo rm -rf`
			# at the top means there's no root-owned leftover from a prior run
			# to guard against here), and archiving as root would leave a
			# root-owned tarball under $HOME/Downloads with the same secret-key
			# exposure the chmod above exists to close. umask 077 again so the
			# archive itself isn't world-readable either. Only delete backup_dir
			# once tar has actually succeeded -- otherwise a failed archive
			# silently takes the only copy of the exported keys down with it.
			if ( umask 077; tar Jcvf "$HOME/Downloads/gpgbackup.tar.gz" "$backup_dir" ); then
				rm -rf "$backup_dir"
			else
				print -u2 "gpgbackup: tar failed, leaving $backup_dir in place (not deleted)"
				return 1
			fi
		fi
	}
	alias gpgbu=gpgbackup

	gpgrestore() {
		local backup_dir="$HOME/gpgbackup"
		if (($+commands[tar])); then
			sudo tar Jxvf "$HOME/Downloads/gpgbackup.tar.gz" || return
		fi
		gpg --import "$backup_dir/${GIT_USER}-secret.key"
		gpg --import-ownertrust "$backup_dir/${GIT_USER}-ownertrust.txt"
	}
	alias gpgrs=gpgrestore
fi

if (($+commands[fzf])) && (($+commands[rg])); then
	sshf() {
		ssh $(rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*" | fzf --tmux +m)
	}
fi
