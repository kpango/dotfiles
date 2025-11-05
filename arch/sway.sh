# /etc/profile
# Remove unnecessary cache files (avoid removing /tmp/* to prevent data loss)
sudo rm -rf $HOME/.ccache

# Detect GPU type
export GPU_VENDOR="$(
  bash -c 'if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 \
    && lsmod | grep -q "^nvidia" && ! lsmod | grep -q "^nouveau" \
    && { [ -e /dev/nvidiactl ] || [ -e /dev/nvidia0 ]; } \
    && command -v lspci >/dev/null 2>&1 \
    && lspci | grep -Ei "VGA|3D|Display" | grep -qi nvidia; then
      printf nvidia
    else
      printf other
    fi'
)"

# Set environment variables for Wayland and GPU-specific settings
export CLUTTER_BACKEND=wayland
export DESKTOP_SESSION=sway
export DefaultImModule=fcitx5
export GDK_BACKEND=wayland
export GDK_DISABLE=gles-api,vulkan
export GTK_IM_MODULE=fcitx5
export GSK_RENDERER=gl
export KITTY_ENABLE_WAYLAND=1
export LIBSEAT_BACKEND=logind
export MOZ_ENABLE_WAYLAND=1
export MOZ_USE_XINPUT2=1
export QT_AUTO_SCREEN_SCALE_FACTOR=1
export QT_IM_MODULE=fcitx5
export QT_QPA_PLATFORM=wayland
export SDL_IM_MODULE=fcitx5
export SDL_VIDEODRIVER=wayland
export XDG_CURRENT_DESKTOP=sway
export XDG_CURRENT_SESSION=sway
export XDG_SESSION_DESKTOP=sway
export XDG_SESSION_TYPE=wayland
export XKB_DEFAULT_LAYOUT=us
export XKB_DEFAULT_OPTIONS=ctrl:nocaps
export XMODIFIERS="@im=fcitx5"
export ALACRITTY_LOG="debug"

# GPU-specific settings
if [ "$GPU_VENDOR" = "nvidia" ]; then
    export LIBVA_DRIVER_NAME=nvidia
    export GBM_BACKEND=nvidia-drm
    export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json"
    card=$(ls /dev/dri/card* | head -n1)
    export WLR_DRM_DEVICES="$card"
    export WLR_DRM_NO_ATOMIC=1
    export WLR_NO_HARDWARE_CURSORS=1
    export XWAYLAND_NO_GLAMOR=1
    # Uncomment the following lines if additional NVIDIA-specific settings are needed
    # export __EGL_VENDOR_LIBRARY_DIRS="/usr/share/glvnd/egl_vendor.d/"
    # export __GLX_SYNC_TO_VBLANK=1
    export __GLX_VENDOR_LIBRARY_NAME="nvidia"
    # export __GL_GSYNC_ALLOWED=0
    # export __GL_THREADED_OPTIMIZATIONS=1
    # export __GL_VRR_ALLOWED=1
    # export __GL_YIELD="USLEEP"

    # Add --unsupported-gpu only for NVIDIA
    export SWAY_GPU_OPTION="--unsupported-gpu"
else
    # Add settings for non-NVIDIA GPUs if needed
    unset LIBVA_DRIVER_NAME
    unset GBM_BACKEND
    unset VK_ICD_FILENAMES
    unset WLR_DRM_DEVICES
    unset WLR_DRM_NO_ATOMIC
    unset WLR_NO_HARDWARE_CURSORS
    unset XWAYLAND_NO_GLAMOR

    # No additional GPU option for non-NVIDIA
    export SWAY_GPU_OPTION=""
fi

# Map Ctrl key to Caps Lock
setxkbmap -option ctrl:nocaps

# Increase the file descriptor limit
ulimit -n 500000

# Start sway if no display server is running and the terminal is tty1
if [[ -z $DISPLAY ]]; then
    #exec sway $SWAY_GPU_OPTION "$@"
    SWAY_DEBUG=1 SWAY_IGNORE_INPUT_GRAB=1 sway --debug --verbose $SWAY_GPU_OPTION "$@" > "/tmp/sway.debug.$(date +%Y%m%d%H%M).log" 2>&1
fi
