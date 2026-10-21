# Sole sway launcher: tty1 login without a running Wayland session.
# $DOTFILES_DIR is not set yet at this point, so resolve from this file's own real path.
if [[ $TTY == /dev/tty1 && -z $WAYLAND_DISPLAY ]] && (( EUID )) && (( $+commands[sway] )); then
	_SWAY_LAUNCH=1
	source ${${(%):-%x}:A:h}/arch/sway.sh
	unset _SWAY_LAUNCH
fi
