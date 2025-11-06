#!/bin/bash
set -e
if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ] && ! pgrep -x sway >/dev/null; then
  # Set ulimit
  ulimit -n 500000
  # Set environment variables from /etc/environment
  if [ -f /etc/environment ]; then
    set -a
    source /etc/environment
    set +a
  fi
  # NVIDIA detection
  if lspci | grep -i "vga compatible controller: nvidia corporation" > /dev/null; then
    export GBM_BACKEND=nvidia-drm
    export LIBVA_DRIVER_NAME=nvidia
    export XWAYLAND_NO_GLAMOR=1
    export WLR_NO_HARDWARE_CURSORS=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    if [ -f /usr/share/vulkan/icd.d/nvidia_icd.json ]; then
        export VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/nvidia_icd.json
    fi
    SWAY_CMD="sway --unsupported-gpu"
  else
    SWAY_CMD="sway"
  fi
  # Import environment into systemd and D-Bus
  systemctl --user import-environment
  dbus-update-activation-environment --systemd --all
  # Start sway
  if [ "$SWAY_DEBUG_MODE" = "1" ]; then
    exec $SWAY_CMD --debug "$@" > /tmp/sway.debug.$(date +%s) 2>&1
  else
    exec $SWAY_CMD "$@"
  fi
fi
