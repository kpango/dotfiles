#!/bin/bash
# Rebuild AUR helpers (paru) after pacman/libalpm upgrade.
# Runs as root via pacman hook; delegates build to the regular user.
set -euo pipefail

AUR_USER="${SUDO_USER:-kpango}"
CACHE_DIR="/var/cache/aur-src/paru"

# If paru still works, nothing to do.
if sudo -u "$AUR_USER" paru --version &>/dev/null 2>&1; then
    exit 0
fi

echo "[rebuild-aur-helpers] paru is broken, rebuilding..."

# Ensure cached PKGBUILD source exists.
if [[ ! -d "$CACHE_DIR/.git" ]]; then
    echo "[rebuild-aur-helpers] Cloning paru PKGBUILD..."
    mkdir -p "$(dirname "$CACHE_DIR")"
    git clone https://aur.archlinux.org/paru.git "$CACHE_DIR"
    chown -R "$AUR_USER:$AUR_USER" "$CACHE_DIR"
else
    echo "[rebuild-aur-helpers] Updating cached paru PKGBUILD..."
    sudo -u "$AUR_USER" git -C "$CACHE_DIR" pull --ff-only || true
fi

echo "[rebuild-aur-helpers] Building paru as $AUR_USER..."
sudo -u "$AUR_USER" bash -c "
    set -euo pipefail
    cd '$CACHE_DIR'
    makepkg -si --noconfirm --needed
"

echo "[rebuild-aur-helpers] paru rebuild complete."
