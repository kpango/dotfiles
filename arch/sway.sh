# /etc/profile
sudo rm -rf /tmp/* \
    $HOME/.ccache

export CLUTTER_BACKEND=wayland
export DESKTOP_SESSION=sway
export DefaultImModule=fcitx5
export GBM_BACKEND=nvidia-drm
export GDK_BACKEND=wayland
export GTK_IM_MODULE=fcitx5
export KITTY_ENABLE_WAYLAND=1
export LIBSEAT_BACKEND=logind
export LIBVA_DRIVER_NAME=nvidia
export MOZ_ENABLE_WAYLAND=1
export MOZ_USE_XINPUT2=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export QT_IM_MODULE=fcitx5
export QT_QPA_PLATFORM="wayland-egl;xcb"
export QT_QPA_PLATFORM=wayland
export QT_WAYLAND_DISABLE_WINDOWDECORATION=1
export SDL_IM_MODULE=fcitx5
export SDL_VIDEODRIVER=wayland
export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json"
export WLR_DRM_DEVICES=/dev/dri/card1:/dev/dri/card0
export WLR_DRM_NO_ATOMIC=1
export WLR_NO_HARDWARE_CURSORS=1
export XDG_CURRENT_DESKTOP=sway
export XDG_CURRENT_SESSION=sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
export XKB_DEFAULT_LAYOUT=us
export XKB_DEFAULT_OPTIONS=ctrl:nocaps
export XMODIFIERS="@im=fcitx5"
export XWAYLAND_NO_GLAMOR=1
export __EGL_VENDOR_LIBRARY_DIRS="/usr/share/glvnd/egl_vendor.d/"
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __GL_GSYNC_ALLOWED=0
export __GL_VRR_ALLOWED=0

setxkbmap -option ctrl:nocaps

ulimit -n 500000

if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    CLUTTER_BACKEND=wayland \
    DESKTOP_SESSION=sway \
    DefaultImModule=fcitx5 \
    GBM_BACKEND=nvidia-drm \
    GDK_BACKEND=wayland \
    GTK_IM_MODULE=fcitx5 \
    KITTY_ENABLE_WAYLAND=1 \
    LIBSEAT_BACKEND=logind \
    LIBVA_DRIVER_NAME=nvidia \
    MOZ_ENABLE_WAYLAND=1 \
    MOZ_USE_XINPUT2=1 \
    QT_AUTO_SCREEN_SCALE_FACTOR=1 \
    QT_IM_MODULE=fcitx5 \
    QT_QPA_PLATFORM="wayland-egl;xcb" \
    QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
    SDL_IM_MODULE=fcitx5 \
    SDL_VIDEODRIVER=wayland \
    VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json" \
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
    XWAYLAND_NO_GLAMOR=1 \
    __EGL_VENDOR_LIBRARY_DIRS="/usr/share/glvnd/egl_vendor.d/" \
    __GLX_VENDOR_LIBRARY_NAME=nvidia \
    __GL_GSYNC_ALLOWED=0 \
    __GL_VRR_ALLOWED=0 \
    exec sway --unsupported-gpu "$@"
fi
