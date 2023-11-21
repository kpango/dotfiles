# /etc/profile
sudo rm -rf /tmp/* \
    $HOME/.ccache

export DefaultImModule=fcitx5
export GTK_IM_MODULE=fcitx5
export LIBSEAT_BACKEND=logind
export QT_IM_MODULE=fcitx5
export QT_QPA_PLATFORM=wayland
export SDL_IM_MODULE=fcitx5
export XDG_CURRENT_DESKTOP=sway
export XDG_CURRENT_SESSION=sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
export XKB_DEFAULT_LAYOUT=us
export XKB_DEFAULT_OPTIONS=ctrl:nocaps
export XMODIFIERS="@im=fcitx5"
# export GDK_DPI_SCALE=1.5
# export QT_SCALE_FACTOR=1.5
# export MOZ_ENABLE_WAYLAND=1
# export WINIT_UNIX_BACKEND=x11

setxkbmap -option ctrl:nocaps

ulimit -n 500000

if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    CLUTTER_BACKEND=wayland \
    DefaultImModule=fcitx5 \
    DESKTOP_SESSION=sway \
    GBM_BACKEND=nvidia-drm \
    GDK_BACKEND=wayland \
    GTK_IM_MODULE=fcitx5 \
    KITTY_ENABLE_WAYLAND=1 \
    LIBSEAT_BACKEND=logind \
    LIBVA_DRIVER_NAME=nvidia \
    MOZ_ENABLE_WAYLAND=1 \
    QT_AUTO_SCREEN_SCALE_FACTOR=1 \
    QT_IM_MODULE=fcitx5 \
    QT_QPA_PLATFORM="wayland-egl;xcb" \
    QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
    SDL_IM_MODULE=fcitx5 \
    SDL_VIDEODRIVER=wayland \
    WLR_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0 \
    WLR_DRM_NO_ATOMIC=1 \
    WLR_NO_HARDWARE_CURSORS=1 \
    XDG_CURRENT_DESKTOP=sway \
    XDG_CURRENT_SESSION=sway \
    XDG_SESSION_DESKTOP=sway \
    XDG_SESSION_TYPE=wayland \
    XKB_DEFAULT_LAYOUT=us \
    XKB_DEFAULT_OPTIONS=ctrl:nocaps \
    XMODIFIERS="@im=fcitx5" \
    __GLX_VENDOR_LIBRARY_NAME=nvidia \
    exec sway --unsupported-gpu -d -V
fi
