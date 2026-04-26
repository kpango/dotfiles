# Arch and macOS Makefiles DRY Refactor

## Overview

The `Makefile.d/arch.mk` and `Makefile.d/macos.mk` files contain a high degree of repetition, running identical link and copy commands across hardcoded lists of files. This spec outlines a DRY refactoring using shell loops and centralized mappings of source to destination paths, similar to what was done for `Makefile.d/dotfiles.mk`.

## Architecture & Data Flow

### 1. `Makefile.d/arch.mk` Refactoring

We will define three multi-line Make variables containing space-separated pairs of source paths and destination paths.

- **`ARCH_LINK_MAP`**: Files linked to the user's home directory (e.g., `fcitx.conf`, `sway.conf`, `waybar.css`).
- **`ARCH_SUDO_LINK_MAP`**: Files linked system-wide using `sudo` (e.g., `60-ioschedulers.rules`, `limits.conf`).
- **`ARCH_SUDO_CP_MAP`**: Files copied system-wide using `sudo` (e.g., `chrony.conf`, `environment`).

The `arch_link` target will then use `while read -r src dest; do ... done` loops for these three blocks, replacing dozens of individual `ln -sfv` and `cp` commands.

### 2. `Makefile.d/macos.mk` Refactoring

The `mac_link` target repetitively processes `.plist` files for `launchd` (`localhost.homebrew-autoupdate.plist` and `ulimit.plist`). Each file undergoes five identical `sudo` operations (`ln`, `chmod`, `chown`, `plutil`, `launchctl`).

We will define a list of these agents:

```makefile
MACOS_LAUNCH_AGENTS = localhost.homebrew-autoupdate.plist ulimit.plist
```

We will then use a shell `for agent in $$MACOS_LAUNCH_AGENTS; do ... done` loop to process each agent dynamically, cutting the repetition significantly.

## Testing Strategy

After making the changes, we will run `make --dry-run arch_link` and `make --dry-run mac_link` to ensure that the generated commands match the expected logic and paths.
