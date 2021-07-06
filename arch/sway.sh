# /etc/profile
sudo rm -rf /tmp/* \
    /var/cache \
    $HOME/.cache \
    $HOME/.ccache

export DefaultImModule=fcitx5
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
export XMODIFIERS="@im=fcitx5"

export XKB_DEFAULT_OPTIONS=ctrl:nocaps
export XKB_DEFAULT_LAYOUT=us

setxkbmap -option ctrl:nocaps

ulimit -n 500000

if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    DefaultImModule=fcitx5 \
    GTK_IM_MODULE=fcitx5 \
    QT_IM_MODULE=fcitx5 \
    XMODIFIERS="@im=fcitx5" \
    XKB_DEFAULT_OPTIONS=ctrl:nocaps \
    XKB_DEFAULT_LAYOUT=us \
    LIBSEAT_BACKEND=logind \
    WLR_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0 \
    exec sway
fi
# sway
