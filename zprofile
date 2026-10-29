# Sole sway launcher for tty1 logins without a running Wayland session, whether started by getty or by greetd
# (arch/greetd/config.toml runs `zsh -l` on vt1). $DOTFILES_DIR is usually unset here, so resolve from this file's real path.
# SWAY_AUTOLOGIN=1 marks greetd's passwordless initial_session: it is consumed here (never exported to sway's
# children) and turns into SWAY_LOCK_ON_START for sway.conf.
_sway_autologin=${SWAY_AUTOLOGIN-}
unset SWAY_AUTOLOGIN
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
		[[ -n $_sway_autologin ]] && export SWAY_LOCK_ON_START=1
		_SWAY_LAUNCH=1
		source $_sway_sh
		unset _SWAY_LAUNCH SWAY_LOCK_ON_START
	else
		print -u2 "zprofile: arch/sway.sh not found, sway not started"
	fi
	unset _sway_sh _sway_d
fi
# Nobody typed a password for the autologin session: never hand it an interactive shell (sway.sh exits on a
# clean sway exit; this covers sway failing or not being launched at all).
[[ -n $_sway_autologin ]] && exit 1
unset _sway_autologin
