#!/usr/bin/env bash
set -euo pipefail

# Container internal entrypoint script
# Sets up non-root user matching host UID/GID and launches Steam/Game

USER_NAME="steam"
USER_UID="${HOST_UID:-1000}"
USER_GID="${HOST_GID:-1000}"

# Create group if not exists
if ! getent group "${USER_NAME}" >/dev/null 2>&1; then
    groupadd -g "${USER_GID}" "${USER_NAME}"
fi

# Create user if not exists
if ! id -u "${USER_NAME}" >/dev/null 2>&1; then
    useradd -m -u "${USER_UID}" -g "${USER_GID}" -s /bin/bash "${USER_NAME}"
fi

# Add user to standard audio/video/input groups if available
for grp in audio video render input; do
    if getent group "${grp}" >/dev/null 2>&1; then
        usermod -aG "${grp}" "${USER_NAME}"
    fi
done

# Ensure home and subdirectories permissions
mkdir -p /home/steam/.local/share/Steam /home/steam/.steam /tmp/xdg
chown -R "${USER_NAME}:${USER_NAME}" /home/steam /tmp/xdg

# Configure PulseAudio / PipeWire runtime path if socket is mounted
if [[ -S "/tmp/pulse-socket" ]]; then
    export PULSE_SERVER="unix:/tmp/pulse-socket"
fi

# Apply DXVK config if exists
if [[ -f "/home/steam/.config/dxvk.conf" ]]; then
    export DXVK_CONFIG_FILE="/home/steam/.config/dxvk.conf"
fi

# Execute command as non-root user
exec gosu "${USER_NAME}" "$@"
