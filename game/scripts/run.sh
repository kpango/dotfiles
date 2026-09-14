#!/usr/bin/env bash
set -euo pipefail

# Host runner script for Steam & Ace Combat 7 container
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_NAME="${GAME_DOCKER_IMAGE:-kpango/steam-ac7:latest}"
CONTAINER_NAME="steam-ac7"

# Check docker availability
if ! command -v docker >/dev/null 2>&1; then
    echo "[ERROR] docker command not found" >&2
    exit 1
fi

# Ensure Steam data directory exists
USER_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-game/steam"
STEAM_DATA_DIR="${STEAM_DATA_DIR:-${USER_DATA_DIR}}"
mkdir -p "${STEAM_DATA_DIR}/data" "${STEAM_DATA_DIR}/dot_steam"

DOCKER_RUN_ARGS=(
    "--rm"
    "-it"
    "--name" "${CONTAINER_NAME}"
    "--ipc=host"
    "--net=host"
    "-e" "HOST_UID=$(id -u)"
    "-e" "HOST_GID=$(id -g)"
    "-v" "${STEAM_DATA_DIR}/data:/home/steam/.local/share/Steam"
    "-v" "${STEAM_DATA_DIR}/dot_steam:/home/steam/.steam"
    "-v" "${GAME_DIR}/config/dxvk.conf:/home/steam/.config/dxvk.conf:ro"
)

# 1. GPU Passthrough
if command -v nvidia-smi >/dev/null 2>&1 || docker info 2>/dev/null | grep -qi "nvidia"; then
    DOCKER_RUN_ARGS+=(
        "--gpus" "all"
        "-e" "NVIDIA_VISIBLE_DEVICES=all"
        "-e" "NVIDIA_DRIVER_CAPABILITIES=all"
    )
elif [[ -d "/dev/dri" ]]; then
    DOCKER_RUN_ARGS+=(
        "--device" "/dev/dri"
    )
fi

# 2. Display Integration (X11 & Wayland)
if command -v xhost >/dev/null 2>&1; then
    xhost +local:root >/dev/null 2>&1 || true
    xhost +local:"$(whoami)" >/dev/null 2>&1 || true
fi

DISPLAY_VAL="${DISPLAY:-:0}"
DOCKER_RUN_ARGS+=(
    "-v" "/tmp/.X11-unix:/tmp/.X11-unix:ro"
    "-e" "DISPLAY=${DISPLAY_VAL}"
)

# Wayland socket if available
if [[ -n "${WAYLAND_DISPLAY:-}" ]] && [[ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY}" ]]; then
    DOCKER_RUN_ARGS+=(
        "-v" "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}:/tmp/xdg/${WAYLAND_DISPLAY}:ro"
        "-e" "WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
        "-e" "XDG_RUNTIME_DIR=/tmp/xdg"
    )
fi

# 3. Audio Integration (PulseAudio / PipeWire)
USER_ID="$(id -u)"
PULSE_SOCK="/run/user/${USER_ID}/pulse/native"
PIPEWIRE_SOCK="/run/user/${USER_ID}/pipewire-0"

if [[ -S "${PULSE_SOCK}" ]]; then
    DOCKER_RUN_ARGS+=(
        "-v" "${PULSE_SOCK}:/tmp/pulse-socket:ro"
        "-e" "PULSE_SERVER=unix:/tmp/pulse-socket"
    )
elif [[ -S "${PIPEWIRE_SOCK}" ]]; then
    DOCKER_RUN_ARGS+=(
        "-v" "${PIPEWIRE_SOCK}:/tmp/pipewire-0:ro"
        "-e" "PIPEWIRE_RUNTIME_DIR=/tmp"
    )
fi

# 4. Input Devices (Joysticks, HOTAS, Gamepads)
if [[ -d "/dev/input" ]]; then
    DOCKER_RUN_ARGS+=(
        "--device" "/dev/input"
    )
fi
if [[ -e "/dev/uinput" ]]; then
    DOCKER_RUN_ARGS+=(
        "--device" "/dev/uinput"
    )
fi

# 5. Target Command
CMD=("$@")
if [[ $# -eq 0 ]]; then
    CMD=("steam")
elif [[ "$1" == "--ac7" ]] || [[ "$1" == "ac7" ]]; then
    echo "[INFO] Launching ACE COMBAT 7: SKIES UNKNOWN (AppID: 502500)..."
    CMD=("steam" "steam://rungameid/502500")
fi

echo "[INFO] Running Steam container with GPU, Display, Audio, and Input passthrough..."
exec docker run "${DOCKER_RUN_ARGS[@]}" "${IMAGE_NAME}" "${CMD[@]}"
