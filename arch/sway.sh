#!/usr/bin/env zsh
# Sway launcher, sourced by zsh from ~/.zprofile (tty1 login only; the gate lives there).
# POSIX-parseable guard: a stale /etc/profile.d/sway.sh link (bash/sh/emulate sh) must be a no-op.
[ -n "${_SWAY_LAUNCH-}" ] || return 0
_sway_log() { printf '[sway-start] %s\n' "$*" >&2; }
# Only place sway.sh forks systemctl (after sway returns): with linger the user manager outlives
# sway, and kanshi (Restart=always, ConditionEnvironment=WAYLAND_DISPLAY) would crash-loop on stale vars.
_sway_teardown() {
	systemctl --user unset-environment WAYLAND_DISPLAY SWAYSOCK DISPLAY >/dev/null 2>&1 ||
		_sway_log "Warning: systemctl --user unset-environment failed"
	# --no-block: don't delay logout/fallback shell on unit stop
	systemctl --user stop --no-block sway-session.target >/dev/null 2>&1 ||
		_sway_log "Warning: systemctl --user stop sway-session.target failed"
}

# 1) Environment variable setup
export DESKTOP_SESSION=sway
export XDG_CURRENT_DESKTOP=$DESKTOP_SESSION
export XDG_CURRENT_SESSION=$DESKTOP_SESSION
export XDG_SESSION_DESKTOP=$DESKTOP_SESSION

# 2) GPU detection (the detection block below uses file tests only; no forks)
SWAY_GPU_OPTION=""

# 3) GPU-specific additions
if [[ -d /sys/module/nvidia_drm && ! -d /sys/module/nouveau && -e /dev/nvidiactl ]]; then
	_sway_log "NVIDIA GPU detected. Applying NVIDIA-specific environment."
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
	(( $#card )) && export WLR_DRM_DEVICES="${WLR_DRM_DEVICES:-$card}"

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
	_sway_log "Using generic GPU settings."
fi

# 4) Limits (Apply to sway and its children)
# Use `_sway_log` on failure instead of `|| true` for better feedback
ulimit -n 500000 || _sway_log "Warning: Failed to set ulimit -n 500000 (non-fatal)"

# 5) Start sway
if [[ -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
	# Prepare arguments safely
	declare -a sway_args=()
	if [[ -n "${SWAY_GPU_OPTION}" ]]; then
		sway_args+=("${SWAY_GPU_OPTION}")
	fi

	if [[ "${SWAY_DEBUG_MODE:-0}" == "1" ]]; then
		_sway_log "Starting sway (DEBUG MODE)..."
		# Add seconds to timestamp for uniqueness
		env SWAY_DEBUG=1 SWAY_IGNORE_INPUT_GRAB=1 \
			sway --debug --verbose "${sway_args[@]}" \
			>"/tmp/sway.debug.$(date +%Y%m%d%H%M%S).log" 2>&1
	else
		_sway_log "Starting sway..."
		sway "${sway_args[@]}"
	fi
	# Not exec'd: if sway fails to start (e.g. missing shared library),
	# fall back to the login shell instead of logging out instantly.
	sway_rc=$?
	_sway_teardown
	if ((sway_rc == 0)); then
		exit 0
	fi
	_sway_log "sway exited with status ${sway_rc}; staying in login shell."
else
	_sway_log "Existing DISPLAY/WAYLAND_DISPLAY detected. Skipping launch."
fi
unset card sway_rc sway_args SWAY_GPU_OPTION
unfunction _sway_log _sway_teardown
