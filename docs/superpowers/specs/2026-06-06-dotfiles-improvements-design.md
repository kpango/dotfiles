# Dotfiles Improvements Design

## Overview

This document outlines the planned improvements for the dotfiles repository. The improvements focus on configuration accuracy, hygiene, and editor polish.

## Planned Changes

### 1. Accuracy & Configuration Hygiene

- **Documentation Sync**: Update `README.md` to remove mentions of the "Starship prompt" and replace it with details about the highly optimized, inline custom prompt (`prmt`) managed via `sheldon.toml`.
- **Ghostty Cleanliness**: Extract the hardcoded color palette and color settings (background, foreground, cursor, selection) from `ghostty.conf` into a dedicated theme file at `ghostty/themes/zed_kpango`. The main `ghostty.conf` will then reference this theme using `theme = zed_kpango`.

### 2. Editor & Environment Polish

- **Helix Whitespace Management**: Uncomment `trim-trailing-whitespace = true` and `trim-final-newlines = true` in `helix/config.toml` to enforce whitespace hygiene and reduce git noise.
- **Tmux Clipboard Integration**: Add `set -s set-clipboard on` to `tmux.conf.d/options.conf` to ensure seamless OSC52 clipboard integration with terminal emulators.

## Implementation Plan

1. Edit `README.md` to update the prompt description.
2. Create `ghostty/themes/zed_kpango` with the palette variables from `ghostty.conf`.
3. Edit `ghostty.conf` to remove the hardcoded palette and add `theme = zed_kpango`.
4. Edit `helix/config.toml` to enable the whitespace trimming settings.
5. Edit `tmux.conf.d/options.conf` to append `set -s set-clipboard on`.
6. Commit the implementation with an appropriate commit message.
