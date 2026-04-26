if (($+commands[gpg])); then
	export GPG_TTY=$TTY
# export PINENTRY_USER_DATA="USE_CURSES=1"
fi
if (($+commands["ssh-keygen"])); then
	sshperm() {
		sudo chown -R $UID:$GID $HOME/.ssh
		find $HOME/.ssh -type d -print | xargs sudo chmod 700
		find $HOME/.ssh -type f -print | xargs sudo chmod 600
	}
	rsagen() {
		ssh-keygen -t rsa -b 4096 -P $1 -f $HOME/.ssh/id_rsa -C $USER
		sshperm
	}
	alias rsagen=rsagen
	ecdsagen() {
		ssh-keygen -t ecdsa -b 521 -P $1 -f $HOME/.ssh/id_ecdsa -C $USER
		sshperm
	}
	alias ecdsagen=ecdsagen

	edgen() {
		ssh-keygen -t ed25519 -P $1 -f $HOME/.ssh/id_ed -C $USER
		sshperm
	}
	alias edgen=edgen
	alias sedit="$EDITOR $HOME/.ssh/config"
	sshls() {
		rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*"
	}
	alias sshls=sshls
	sshinit() {
		rm -rf $HOME/.ssh/known_hosts \
			$HOME/.ssh/master_$GIT_USER@192.168.2.* \
			/tmp/ssh-.*.sock
		sshperm
	}
	alias sshinit=sshinit
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

if (($+commands[fzf])); then
	if (($+commands["fzf-tmux"])); then
		if (($+commands[rg])); then
			sshf() {
				ssh $(rg "Host " $HOME/.ssh/config | awk '{print $2}' | rg -v "\*" | fzf-tmux +m)
			}
			alias sshf=sshf
		fi
	fi
fi
