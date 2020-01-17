# /etc/profile
sudo rm -rf /tmp/* \
	/var/cache \
	$HOME/.cache \
	$HOME/.ccache

export XKB_DEFAULT_OPTIONS=ctrl:nocaps

setxkbmap -option ctrl:nocaps

if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    XKB_DEFAULT_LAYOUT=us exec sway
fi
# sway
