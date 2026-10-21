#!/usr/bin/env zsh
# Sway launcher, sourced by zsh from ~/.zprofile (tty1 login only; the gate lives there).
log() { printf '[sway-start] %s\n' "$*" >&2; }

# 1) Environment variable setup
export DESKTOP_SESSION=sway
export XDG_CURRENT_DESKTOP=$DESKTOP_SESSION
export XDG_CURRENT_SESSION=$DESKTOP_SESSION
export XDG_SESSION_DESKTOP=$DESKTOP_SESSION

# 2) GPU detection (file tests only; no forks on the login path)
SWAY_GPU_OPTION=""

# 3) GPU-specific additions
if [[ -d /sys/module/nvidia_drm && ! -d /sys/module/nouveau && -e /dev/nvidiactl ]]; then
	log "NVIDIA GPU detected. Applying NVIDIA-specific environment."
	export LIBVA_DRIVER_NAME=nvidia
	export GBM_BACKEND=nvidia-drm

	if [[ -r "/usr/share/vulkan/icd.d/nvidia_icd.json" ]]; then
		export VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/nvidia_icd.json"
	fi

	# --- Stability Improvement ---
	# Heuristic: Assume dGPU (NVIDIA) is the *last* DRM card (e.g., card1).
	# `head -n1` (original) often incorrectly selects iGPU (e.g., card0).
	# (n) sorts numerically, [-1] picks the last.
	card=(/dev/dri/card*(nN[-1]))

	# Only set WLR_DRM_DEVICES if not already set by the user/environment
	export WLR_DRM_DEVICES="${WLR_DRM_DEVICES:-$card}"

	# Set other NVIDIA-specific variables
	export WLR_DRM_NO_ATOMIC=1
	export WLR_NO_HARDWARE_CURSORS=1
	export XWAYLAND_NO_GLAMOR=1
	export __GLX_VENDOR_LIBRARY_NAME="nvidia"
	export __GL_GSYNC_ALLOWED=0
	export __GL_VRR_ALLOWED=0
	export __GL_THREADED_OPTIMIZATIONS=1
	export __GL_SHADER_DISK_CACHE=1

	# please use vulkan for flicking problems occured
	# export WLR_RENDERER=vulkan

	# Add --unsupported-gpu only for NVIDIA
	SWAY_GPU_OPTION="--unsupported-gpu"

else
	log "Using generic GPU settings."
fi

# 4) Limits (Apply to sway and its children)
# Use `log` on failure instead of `|| true` for better feedback
ulimit -n 500000 || log "Warning: Failed to set ulimit -n 500000 (non-fatal)"

# 5) Start sway
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
	# Prepare arguments safely
	declare -a sway_args=()
	if [[ -n "${SWAY_GPU_OPTION}" ]]; then
		sway_args+=("${SWAY_GPU_OPTION}")
	fi
	sway_args+=("$@") # Append any user-provided arguments

	if [[ "${SWAY_DEBUG_MODE:-0}" == "1" ]]; then
		log "Starting sway (DEBUG MODE)..."
		# Add seconds to timestamp for uniqueness
		env SWAY_DEBUG=1 SWAY_IGNORE_INPUT_GRAB=1 \
			sway --debug --verbose "${sway_args[@]}" \
			>"/tmp/sway.debug.$(date +%Y%m%d%H%M%S).log" 2>&1
	else
		log "Starting sway..."
		sway "${sway_args[@]}"
	fi
	# Not exec'd: if sway fails to start (e.g. missing shared library),
	# fall back to the login shell instead of logging out instantly.
	sway_rc=$?
	if ((sway_rc == 0)); then
		exit 0
	fi
	log "sway exited with status ${sway_rc}; staying in login shell."
else
	log "Existing DISPLAY/WAYLAND_DISPLAY detected. Skipping launch."
fi
unset card sway_rc sway_args SWAY_GPU_OPTION
unfunction log
