# /etc/profile
sudo rm -rf /tmp/* \
    /var/cache \
    $HOME/.cache \
    $HOME/.ccache

export DefaultImModule=fcitx5
export GTK_IM_MODULE=fcitx5
export QT_IM_MODULE=fcitx5
export XMODIFIERS="@im=fcitx5"
export SDL_IM_MODULE=fcitx5

export XKB_DEFAULT_OPTIONS=ctrl:nocaps
export XKB_DEFAULT_LAYOUT=us

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=sway
export XDG_CURRENT_SESSION=sway
export LIBSEAT_BACKEND=logind
export QT_QPA_PLATFORM=wayland
# export GDK_DPI_SCALE=1.5
# export QT_SCALE_FACTOR=1.5
# export MOZ_ENABLE_WAYLAND=1
# export WINIT_UNIX_BACKEND=x11

setxkbmap -option ctrl:nocaps

ulimit -n 500000

if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    DefaultImModule=fcitx5 \
    GTK_IM_MODULE=fcitx5 \
    QT_IM_MODULE=fcitx5 \
    XMODIFIERS="@im=fcitx5" \
    SDL_IM_MODULE=fcitx5 \
    XKB_DEFAULT_OPTIONS=ctrl:nocaps \
    XKB_DEFAULT_LAYOUT=us \
    XDG_SESSION_TYPE=wayland \
    XDG_CURRENT_DESKTOP=sway \
    XDG_CURRENT_SESSION=sway \
    LIBSEAT_BACKEND=logind \
    QT_QPA_PLATFORM=wayland \
    WLR_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0 \
    exec sway
fi
