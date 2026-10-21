# Sole sway launcher for tty logins: tty1 without a running Wayland session (greetd-started
# sessions never read this). $DOTFILES_DIR is usually unset here, so resolve from this file's real path.
if [[ -o interactive && $TTY == /dev/tty1 && -z $WAYLAND_DISPLAY ]] && (( EUID )) && (( $+commands[sway] )); then
	_sway_sh=${${(%):-%x}:A:h}/arch/sway.sh
	if [[ ! -r $_sway_sh ]]; then
		# MODE=copy leaves ~/.zprofile as a plain file, so probe zshrc's locations (minus the ghq root fork)
		_sway_sh=
		for _sway_d in $DOTFILES_DIR $HOME/go/src/github.com/${GIT_USER:-kpango}/dotfiles $HOME/ghq/github.com/${GIT_USER:-kpango}/dotfiles $HOME/dotfiles; do
			[[ -r $_sway_d/arch/sway.sh ]] && { _sway_sh=$_sway_d/arch/sway.sh; break; }
		done
	fi
	if [[ -n $_sway_sh ]]; then
		_SWAY_LAUNCH=1
		source $_sway_sh
		unset _SWAY_LAUNCH
	else
		print -u2 "zprofile: arch/sway.sh not found, sway not started"
	fi
	unset _sway_sh _sway_d
fi
