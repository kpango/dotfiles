# Pinentry Environment Integration Design

## Overview

This design aligns the configurations across macOS, NixOS, Docker, and the general Makefile compilation to ensure `pinentry-tmux` is properly installed, compiled, or replaced appropriately in all supported environments.

## 1. macOS and NixOS Configuration

**Current State:** Both `Makefile.d/install.mk` (via a `sed` command) and `nix/modules/home/dotfiles/darwin.nix` (via `builtins.replaceStrings`) attempt to configure the macOS environment by replacing `/usr/bin/pinentry-tty` with `/opt/homebrew/bin/pinentry-mac`. However, `gpg-agent.conf` has been updated to point to `/usr/local/bin/pinentry-tmux`, rendering these replacements obsolete.
**Design:** Update the replacement targets in both scripts to look for `/usr/local/bin/pinentry-tmux` and replace it with `/opt/homebrew/bin/pinentry-mac`.

**UPDATE (2026-08-04):** Homebrew is disabled on macOS entirely (`homebrew.enable = false` in
`nix/core/settings.nix` — GUI apps and CLI tools are provisioned through nixpkgs instead, see
`nix/modules/darwin/applications.nix`). `nix/modules/home/dotfiles/darwin.nix` now replaces
`/usr/local/bin/pinentry-tmux` with `${lib.getExe pkgs.pinentry_mac}` (a nix store path, not
`/opt/homebrew/bin/pinentry-mac`), and installs `pkgs.pinentry_mac` as a package. This is the same design
intent carried forward onto nix rather than Homebrew — the split this section documents (macOS: native
GUI/Keychain pinentry; Linux/tmux: the custom Go `pinentry-tmux` binary) is unchanged.

**CORRECTION (2026-08-22):** The line above calling `mac/install` "now-superseded" was wrong — it is
still the documented bootstrap entry point (via the `m1/install`/`m1air/install`/`m3/install` aliases)
and its `MAC_PREP` step runs on every fresh/re-run setup. Because that premise was wrong, `MAC_PREP`'s
`sed` (rewriting `gpg-agent.conf`'s pinentry path to `/opt/homebrew/bin/pinentry-mac`) was left in place
after Homebrew was disabled, and that path stopped existing — breaking `gpg --clearsign`/commit signing
the next time `mac/install` was (re-)run. The `sed` has been removed; `gpg-agent.conf` is now left
pointing at the template's `/usr/local/bin/pinentry-tmux`, with nix-darwin's home-manager activation
(triggered by `nix/setup`, the last step of `mac/install`) owning the final `pinentry-program` value.

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
