# Nix Configuration

This directory contains the cross-platform Nix configuration for macOS (via `nix-darwin`) and NixOS.

## Directory Structure

- `core/`: Contains core configuration files shared across different OS, including version management.
- `modules/`: Contains specific Nix modules like macOS system defaults.
- `profiles/`: Contains top-level configuration definitions for systems and home-manager.
- `hosts/`: Contains host-specific hardware configurations.
- `flake.nix`: The entry point for the Nix configurations.

## Setup

See the main `Makefile` for setup instructions (`make nix/setup`).
