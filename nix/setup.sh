#!/usr/bin/env bash

set -e

# Define user and system variables
USER_NAME=$(whoami)
HOST_NAME="macbook" # Set your desired hostname here

echo "=========================================================="
echo " Starting Nix macOS Development Environment Setup"
echo " User: $USER_NAME, Hostname: $HOST_NAME"
echo "=========================================================="

# 1. Install Nix via Determinate Systems installer (if not installed)
if ! command -v nix &> /dev/null; then
    echo "=> Installing Nix (Determinate Systems)..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

    # Source the Nix profile to use it immediately in the script
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
else
    echo "=> Nix is already installed."
fi

# 2. Install Apple Container via PKG installer directly
echo "=> Installing Apple Container..."
curl -LO https://github.com/apple/container/releases/download/0.4.1/container-0.4.1-installer-signed.pkg
sudo installer -pkg container-0.4.1-installer-signed.pkg -target /
rm -f container-0.4.1-installer-signed.pkg
echo "=> Apple Container installed successfully."

# 3. Extract macOS GUI settings (defaults) using defaults2nix
echo "=> Extracting macOS defaults to all-defaults.nix..."
sudo nix run github:joshryandavis/defaults2nix -- -all -filter dates,state,uuids -o ./all-defaults.nix
# Fix ownership of extracted file since sudo created it as root
sudo chown $USER_NAME ./all-defaults.nix || true

# Check if defaults extraction worked; if not, create an empty one to avoid breaking the build
if [ ! -s ./all-defaults.nix ]; then
    echo "Warning: defaults2nix failed or returned empty. Creating an empty fallback."
    echo "{}" > ./all-defaults.nix
fi

# 4. Initialize Git repository if not already one (required by Flakes)
echo "=> Initializing Git repository (Flakes require files to be tracked by Git)..."
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    git init
fi

# Add the extracted defaults and current nix files to Git so Flake can see them
git add .
git commit -m "Initial commit for Nix configuration" || true

# 5. Execute initial nix-darwin build
echo "=> Running initial nix-darwin build for host: $HOST_NAME..."
nix run nix-darwin -- switch --flake .#$HOST_NAME

echo "=========================================================="
echo " Setup complete! Please open a new terminal or run 'exec zsh'"
echo "=========================================================="
