# Pinentry Environment Integration Design

## Overview

This design aligns the configurations across macOS, NixOS, Docker, and the general Makefile compilation to ensure `pinentry-tmux` is properly installed, compiled, or replaced appropriately in all supported environments.

## 1. macOS and NixOS Configuration

**Current State:** Both `Makefile.d/install.mk` (via a `sed` command) and `nix/modules/home/dotfiles/darwin.nix` (via `builtins.replaceStrings`) attempt to configure the macOS environment by replacing `/usr/bin/pinentry-tty` with `/opt/homebrew/bin/pinentry-mac`. However, `gpg-agent.conf` has been updated to point to `/usr/local/bin/pinentry-tmux`, rendering these replacements obsolete.
**Design:** Update the replacement targets in both scripts to look for `/usr/local/bin/pinentry-tmux` and replace it with `/opt/homebrew/bin/pinentry-mac`.

## 2. Makefile Global Compile Target

**Current State:** The `dotfiles/compile` target in `Makefile.d/install.mk` only triggers `tmux/go/install`.
**Design:** Append `pinentry/install` as a dependency to `dotfiles/compile` so that executing `make dotfiles/compile` guarantees both utilities are built.

## 3. Docker Go Tools Integration

**Current State:** Docker environments build tools defined in `dockers/go.tools`, but `pinentry-tmux` is omitted. If triggered inside Docker, `gpg-agent` falls back to `pinentry-tty`.
**Design:** Add `github.com/kpango/dotfiles/pinentry/tmux@latest` to the `dockers/go.tools` file so it is natively available in development containers.

## Spec Self-Review

- **Placeholders:** None.
- **Consistency:** Directly addresses the findings across all 4 environments (Arch via Makefile, macOS via Nix and Make, Docker via go.tools).
- **Scope:** Narrowly focused on specific configuration files; perfect for a single implementation plan.
