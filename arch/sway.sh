# /etc/profile
rm -rf /tmp

export XKB_DEFAULT_OPTIONS=ctrl:nocaps

setxkbmap -option ctrl:nocaps

if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    exec sway
fi
# sway
