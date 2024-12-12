# /etc/profile
# Remove unnecessary cache files (avoid removing /tmp/* to prevent data loss)
sudo rm -rf $HOME/.ccache

# Set environment variables for Wayland and NVIDIA GPU
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
# export __EGL_VENDOR_LIBRARY_DIRS="/usr/share/glvnd/egl_vendor.d/"
# export __GLX_SYNC_TO_VBLANK=1
# export __GLX_VENDOR_LIBRARY_NAME="nvidia"
# export __GL_GSYNC_ALLOWED=0
# export __GL_THREADED_OPTIMIZATIONS=1
# export __GL_VRR_ALLOWED=1
# export __GL_YIELD="USLEEP"
export ALACRITTY_LOG="debug"

# Map Ctrl key to Caps Lock
setxkbmap -option ctrl:nocaps

# Increase the file descriptor limit
ulimit -n 500000

# Start sway if no display server is running and the terminal is tty1
if [[ -z $DISPLAY ]] && [[ $TTY = /dev/tty1 ]]; then
    exec sway --unsupported-gpu "$@"
fi
