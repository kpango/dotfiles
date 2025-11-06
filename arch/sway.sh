#!/usr/bin/env bash
# /usr/local/bin/sway-start — system-wide sway launcher
# (Improved Version)

# 1) Strict mode and helpers
IFS=$'\n\t'
log() { printf '[sway-start] %s\n' "$*" >&2; }

# 2) Environment variable setup
export DESKTOP_SESSION=sway
export XDG_CURRENT_DESKTOP=sway
export XDG_CURRENT_SESSION=sway
export XDG_SESSION_DESKTOP=sway

# --- Environment variable keys to import into systemd/D-Bus ---
# We use an associative array to deduplicate keys
declare -A seen_keys=()
SYSTEMD_ENV_KEYS=()

# Helper to add a key to the list for systemd/dbus import
add_key() {
  local key="$1"
  [[ -n "$key" ]] || return 0 # Skip empty keys
  if [[ -z "${seen_keys[$key]+x}" ]]; then
    seen_keys[$key]=1
    SYSTEMD_ENV_KEYS+=("$key")
  fi
}

# Add static keys
add_key "DESKTOP_SESSION"
add_key "XDG_CURRENT_DESKTOP"
add_key "XDG_SESSION_DESKTOP"
add_key "XDG_CURRENT_SESSION"

# 3) GPU detection
export GPU_VENDOR="$(
  bash -c 'if hash nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1 \
    && hash lsmod >/dev/null 2>&1 \
    && lsmod | grep -q "^nvidia" && ! lsmod | grep -q "^nouveau" \
    && { [ -e /dev/nvidiactl ] || [ -e /dev/nvidia0 ]; } \
    && hash lspci >/dev/null 2>&1 \
    && lspci | grep -Ei "VGA|3D|Display" | grep -qi nvidia; then
      printf nvidia
    else
      printf other
    fi'
)"
SWAY_GPU_OPTION=""

echo $GPU_VENDOR

# 4) GPU-specific additions
if [[ "${GPU_VENDOR}" == "nvidia" ]]; then
  log "NVIDIA GPU detected. Applying NVIDIA-specific environment."
  export LIBVA_DRIVER_NAME=nvidia
  export GBM_BACKEND=nvidia-drm
  add_key "LIBVA_DRIVER_NAME"
  add_key "GBM_BACKEND"

  if [[ -r "/usr/share/vulkan/icd.d/nvidia_icd.json" ]]; then
    export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json"
    add_key "VK_ICD_FILENAMES"
  fi

  # --- Stability Improvement ---
  # Heuristic: Assume dGPU (NVIDIA) is the *last* DRM card (e.g., card1).
  # `head -n1` (original) often incorrectly selects iGPU (e.g., card0).
  # We use `ls -1v` for natural sort.
  card=$(ls -1v /dev/dri/card* | tail -n1)

  # Only set WLR_DRM_DEVICES if not already set by the user/environment
  export WLR_DRM_DEVICES="${WLR_DRM_DEVICES:-$card}"
  add_key "WLR_DRM_DEVICES"

  # Set other NVIDIA-specific variables
  export WLR_DRM_NO_ATOMIC=1
  export WLR_NO_HARDWARE_CURSORS=1
  export XWAYLAND_NO_GLAMOR=1
  export __GLX_VENDOR_LIBRARY_NAME="nvidia"

  # Add them to the import list
  add_key "WLR_DRM_NO_ATOMIC"
  add_key "WLR_NO_HARDWARE_CURSORS"
  add_key "XWAYLAND_NO_GLAMOR"
  add_key "__GLX_VENDOR_LIBRARY_NAME"

  # Add --unsupported-gpu only for NVIDIA
  SWAY_GPU_OPTION="--unsupported-gpu"

else
  log "Using generic GPU settings."
fi

# 5) ENV_VARS: Read from /etc/environment
if [[ -r /etc/environment ]]; then
  log "Importing keys from /etc/environment"
  while IFS='=' read -r k _; do
    # Robust check for valid env var name (ignores comments, malformed lines)
    [[ "$k" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    add_key "$k"
  done < /etc/environment
fi

# 6) Limits (Apply to sway and its children)
# Use `log` on failure instead of `|| true` for better feedback
ulimit -n 500000 || log "Warning: Failed to set ulimit -n 500000 (non-fatal)"

# 7) Import collected env to systemd --user & D-Bus
if (( ${#SYSTEMD_ENV_KEYS[@]} > 0 )); then
  log "Importing ${#SYSTEMD_ENV_KEYS[@]} environment variables into systemd/D-Bus..."
  if hash systemctl &>/dev/null; then
    systemctl --user import-environment "${SYSTEMD_ENV_KEYS[@]}" \
      || log "Warning: systemctl import-environment failed (non-fatal)"
  fi
  if hash dbus-update-activation-environment &>/dev/null; then
    dbus-update-activation-environment --systemd "${SYSTEMD_ENV_KEYS[@]}" \
      || log "Warning: dbus-update-activation-environment failed (non-fatal)"
  fi
else
  log "No environment keys to import."
fi

# 8) Start sway (with multi-launch guard)
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
  if ! pgrep -x sway >/dev/null 2>&1; then

    # Prepare arguments safely
    declare -a sway_args=()
    if [[ -n "${SWAY_GPU_OPTION}" ]]; then
      sway_args+=("${SWAY_GPU_OPTION}")
    fi
    sway_args+=("$@") # Append any user-provided arguments

    if [[ "${SWAY_DEBUG_MODE:-0}" == "1" ]]; then
      log "Starting sway (DEBUG MODE)..."
      # Add seconds to timestamp for uniqueness
      exec env SWAY_DEBUG=1 SWAY_IGNORE_INPUT_GRAB=1 \
        sway --debug --verbose "${sway_args[@]}" \
        >"/tmp/sway.debug.$(date +%Y%m%d%H%M%S).log" 2>&1
    else
      log "Starting sway..."
      # --- Refactoring Improvement ---
      # Use `exec ... "${sway_args[@]}"` to correctly handle empty $SWAY_GPU_OPTION
      # and avoid word-splitting issues.
      exec sway "${sway_args[@]}"
    fi
  else
    log "Sway already running. Skipping launch."
  fi
else
  log "Existing DISPLAY/WAYLAND_DISPLAY detected. Skipping launch."
fi
