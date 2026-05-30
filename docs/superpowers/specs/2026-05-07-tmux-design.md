# tmux.conf Improvement Design

**Date:** 2026-05-07  
**Scope:** `tmux.conf`, `tmux-short-path` (new), `nix/modules/home/programs/tmux.nix`

## Context

- Host: Wayland (Linux, ThreadRipper desktop)
- Also used inside Docker containers (no Wayland/X11)
- NixOS migration in progress; Nix module reads `tmux.conf` via `builtins.readFile`
- Current pain point: `status-left` path grows unboundedly when navigating deep directories

## Changes

### 1. Fish-style Path Shortening

**Problem:** `#{pane_current_path}` in `status-left` shows the full absolute path, which grows too long in deep directory trees.

**Solution:** New script `tmux-short-path` (placed alongside `tmux-kube` in the dotfiles root) abbreviates every path component except the last to its first letter and replaces `$HOME` with `~`.

Examples:

- `/home/kpango/go/src/github.com/kpango/dotfiles` → `~/g/s/g/k/dotfiles`
- `/home/kpango/go/src/github.com/kpango` → `~/g/s/g/kpango`

`status-left` changes from `#{pane_current_path}` to `#(~/.tmux-short-path #{pane_current_path})`. Called at the existing 5-second status interval — no extra overhead.

### 2. Clipboard: Wayland-aware with Docker Fallback

**Problem:** Current clipboard uses `xsel`, which is X11-only and breaks on Wayland host and is unavailable in Docker.

**Solution:** Inline shell commands that detect `wl-copy`/`wl-paste` availability and degrade gracefully:

- **Wayland host:** pipes through `wl-copy` / reads from `wl-paste`
- **Docker / no Wayland:** skips system clipboard silently; tmux retains the selection in its internal buffer, so intra-tmux paste (`prefix + p`) still works

No helper scripts needed — all inline in `tmux.conf`.

### 3. True Color & Terminal Fixes

**Problem 1:** The `if-shell "[[ ${TERM} =~ 256color ... ]]"` line overrides `set -g default-terminal tmux-256color` with the older `screen-256color`, downgrading terminal capabilities. Removed.

**Problem 2:** `set-option -sa terminal-overrides ",${TERM}:RGB"` uses shell variable expansion at config-load time, which is unreliable. Replaced with wildcard patterns:

```
set -as terminal-features ",xterm*:RGB"
set -as terminal-features ",tmux*:RGB"
```

### 4. General Cleanup

- `set -g renumber-windows on` — closes numbering gaps when windows are closed
- `run '~/.tmux/plugins/tpm/tpm'` — remove deprecated `-b` flag (removed in tmux 3.2+)
- Remove dead commented-out bindings (`bind-key -r c/s/v`, macOS `pbcopy` line)

### 5. Nix Plugin Management

**Problem:** `tmux.nix` uses TPM bootstrap. Home-manager supports native plugin management.

**Solution:** Add `plugins = with pkgs.tmuxPlugins; [ cpu ];` to `programs.tmux` in `tmux.nix`. TPM declarations remain in `tmux.conf` for Docker use, but are stripped from the Nix-built config via `builtins.replaceStrings`:

- Strip: `set -g @plugin 'tmux-plugins/tpm'`
- Strip: `set -g @plugin 'tmux-plugins/tmux-cpu'`
- Strip: `run '~/.tmux/plugins/tpm/tpm'`

The `@cpu_interval` option is retained (home-manager passes plugin options through `extraConfig`).

## Files Changed

| File                                 | Action                                                                     |
| ------------------------------------ | -------------------------------------------------------------------------- |
| `tmux.conf`                          | Modify: path display, clipboard, terminal fixes, renumber-windows, cleanup |
| `tmux-short-path`                    | Create: fish-style path abbreviation script                                |
| `nix/modules/home/programs/tmux.nix` | Modify: add plugins, strip TPM from extraConfig                            |

## What Is Not Changed

- Status bar content and layout (kept as-is per user preference)
- Keybindings (all kept as-is)
- `tmux-kube` script (kept as-is)
- `tmux.new-session` (kept as-is)
- `set -g @cpu_interval 5` (kept — used by tmux-cpu plugin on both TPM and Nix paths)
