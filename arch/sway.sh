# /etc/profile
sudo rm -rf /tmp/* \
    /var/cache \
    $HOME/.cache \
    $HOME/.ccache

export DefaultImModule=fcitx
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"

export XKB_DEFAULT_OPTIONS=ctrl:nocaps
export XKB_DEFAULT_LAYOUT=us

setxkbmap -option ctrl:nocaps

ulimit -n 500000

if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    DefaultImModule=fcitx \
    GTK_IM_MODULE=fcitx \
    QT_IM_MODULE=fcitx \
    XMODIFIERS="@im=fcitx" \
    XKB_DEFAULT_OPTIONS=ctrl:nocaps \
    XKB_DEFAULT_LAYOUT=us \
    WLR_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0 \
    exec sway
fi
# sway
