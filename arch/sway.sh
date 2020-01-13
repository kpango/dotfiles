# /etc/profile
rm -rf /tmp

export XKB_DEFAULT_OPTIONS=ctrl:nocaps

setxkbmap -option ctrl:nocaps

sway
