#!/usr/bin/env bash
# nix-run.sh — dispatch nix commands to either the native nix binary or a
# NixOS Docker container with a persistent nix store volume.
#
# During the Arch Linux → NixOS transition, nix may not yet be installed on
# the host.  This script transparently falls back to a Docker container so
# that CI / test targets work regardless of whether nix is available.
#
# Usage (called from Makefile targets):
#   nix/scripts/nix-run.sh eval .#nixosConfigurations.tr.config.system.stateVersion
#   nix/scripts/nix-run.sh build .#nixosConfigurations.tr.config.system.build.toplevel --dry-run
#   nix/scripts/nix-run.sh flake check --no-build
#
# Environment variables (can be overridden):
#   DOTFILES_ROOT     — absolute path to the dotfiles repo root
#   NIX_DOCKER_IMAGE  — container image (default: ghcr.io/nixos/nix:latest)
#   NIX_VOLUME_NAME   — Docker named volume for the nix store (default: nix-store-dotfiles)
#   NIX_WRITABLE      — set to 1 to mount the repo read-write (needed for flake update / fmt)

set -euo pipefail

DOTFILES_ROOT="${DOTFILES_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
NIX_DOCKER_IMAGE="${NIX_DOCKER_IMAGE:-ghcr.io/nixos/nix:latest}"
# Named volume avoids host-path ownership issues and lets Docker manage the
# nix store lifecycle (first run initialises it automatically).
NIX_VOLUME_NAME="${NIX_VOLUME_NAME:-nix-store-dotfiles}"
# Set NIX_WRITABLE=1 to allow writing back to the repo (e.g. for flake update).
NIX_WRITABLE="${NIX_WRITABLE:-0}"

# ── Source Determinate-installer nix environment if available ─────────────
# shellcheck disable=SC1091
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true

# ── Prefer native nix binary ──────────────────────────────────────────────
if command -v nix >/dev/null 2>&1; then
    cd "${DOTFILES_ROOT}/nix"
    exec nix "$@"
fi

# ── Fallback: NixOS Docker container ─────────────────────────────────────
echo "[nix-run] nix not found natively; dispatching to container: ${NIX_DOCKER_IMAGE}" >&2

# Ensure the persistent nix-store volume exists (idempotent).
docker volume inspect "${NIX_VOLUME_NAME}" >/dev/null 2>&1 \
    || docker volume create "${NIX_VOLUME_NAME}" >/dev/null

# The flake at nix/flake.nix references files relative to the repo root, and
# nix flake requires git to discover the tree boundary.  We mount the entire
# repo (read-only by default, or read-write when NIX_WRITABLE=1) and set
# the workdir to the flake subdirectory.
#
# nix single-user mode is used inside the container (no daemon needed).
# The container runs as root; the repo mount is owned by the host user.
# libgit2 (used internally by Nix) refuses to open repos not owned by the
# current user.  Write safe.directory to /etc/gitconfig (system-level) so
# libgit2 picks it up unconditionally — GIT_CONFIG_GLOBAL and GIT_CONFIG_COUNT
# are not supported by the libgit2 version bundled in the nixos/nix image, and
# /root/.gitconfig is a directory in that image so bind-mounting is impossible.
#
# --network host shares the host network stack so the container can reach
# cache.nixos.org and github.com for flake input resolution.
DOTFILES_MOUNT_MODE="ro"
[ "${NIX_WRITABLE}" = "1" ] && DOTFILES_MOUNT_MODE="rw"

# Build NIX_CONFIG, optionally injecting a GitHub access token to avoid the
# 60-req/hr unauthenticated rate limit when resolving flake inputs.
# Nix reads GITHUB_TOKEN from NIX_CONFIG access-tokens, not from env directly.
_NIX_CONFIG="extra-experimental-features = nix-command flakes
trusted-users = root
substituters = https://cache.nixos.org/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
if [ -n "${GITHUB_TOKEN:-}" ]; then
    _NIX_CONFIG="${_NIX_CONFIG}
access-tokens = github.com=${GITHUB_TOKEN}"
fi

exec docker run --rm \
    --name "nix-run-$$" \
    --network host \
    --workdir /dotfiles/nix \
    --volume "${DOTFILES_ROOT}:/dotfiles:${DOTFILES_MOUNT_MODE}" \
    --volume "${NIX_VOLUME_NAME}:/nix" \
    --env "NIX_CONFIG=${_NIX_CONFIG}" \
    "${NIX_DOCKER_IMAGE}" \
    sh -c 'printf "[safe]\n\tdirectory = /dotfiles\n" > /etc/gitconfig && exec nix "$@"' \
    -- "$@"
