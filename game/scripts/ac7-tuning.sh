#!/usr/bin/env bash
set -euo pipefail

# Tune and configure ACE COMBAT 7 prefix settings
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GAME_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

USER_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles-game/steam"
STEAM_DATA_DIR="${STEAM_DATA_DIR:-${USER_DATA_DIR}}"

AC7_APPID="502500"
PREFIX_DIR="${STEAM_DATA_DIR}/data/steamapps/compatdata/${AC7_APPID}/pfx"
AC7_CONFIG_DIR="${PREFIX_DIR}/drive_c/users/steamuser/AppData/Local/BANDAI NAMCO Entertainment/ACE COMBAT 7/Config"

echo "[INFO] Looking for ACE COMBAT 7 prefix at: ${PREFIX_DIR}"

if [[ ! -d "${PREFIX_DIR}" ]]; then
    echo "[WARN] Prefix directory not found yet. Launch the game at least once with Proton so Steam creates the prefix."
    echo "[INFO] Expected path: ${PREFIX_DIR}"
    exit 0
fi

mkdir -p "${AC7_CONFIG_DIR}"

# 1. Apply Engine.ini
if [[ -f "${GAME_DIR}/config/ac7/Engine.ini" ]]; then
    echo "[INFO] Applying Engine.ini (Texture streaming & stutter reduction)..."
    cp -v "${GAME_DIR}/config/ac7/Engine.ini" "${AC7_CONFIG_DIR}/Engine.ini"
fi

# 2. Apply Input.ini if specified or not present
if [[ -f "${GAME_DIR}/config/ac7/Input.ini" ]]; then
    if [[ ! -f "${AC7_CONFIG_DIR}/Input.ini" ]] || [[ "${FORCE_INPUT_CONFIG:-0}" == "1" ]]; then
        echo "[INFO] Applying Input.ini (HOTAS/FlightStick mapping)..."
        cp -v "${GAME_DIR}/config/ac7/Input.ini" "${AC7_CONFIG_DIR}/Input.ini"
    else
        echo "[INFO] Input.ini already exists in prefix. Set FORCE_INPUT_CONFIG=1 to overwrite."
    fi
fi

# 3. Apply DXVK config into game directory if game exists
GAME_INSTALL_DIR="${STEAM_DATA_DIR}/data/steamapps/common/ACE COMBAT 7"
if [[ -d "${GAME_INSTALL_DIR}" ]] && [[ -f "${GAME_DIR}/config/dxvk.conf" ]]; then
    echo "[INFO] Copying dxvk.conf into game directory..."
    cp -v "${GAME_DIR}/config/dxvk.conf" "${GAME_INSTALL_DIR}/dxvk.conf"
fi

echo "[SUCCESS] AC7 tuning applied successfully."
