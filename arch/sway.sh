# /etc/profile
rm -rf /tmp
rm -rf $HOME/.cache
rm -rf $HOME/.ccache

export XKB_DEFAULT_OPTIONS=ctrl:nocaps

setxkbmap -option ctrl:nocaps

export SWAYSOCK=$(ls /run/user/*/sway-ipc.*.sock | head -n 1)
if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    exec sway
fi
# sway
