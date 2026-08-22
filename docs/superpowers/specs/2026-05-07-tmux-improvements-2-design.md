# tmux Improvements (Round 2) Design

**Date:** 2026-05-07
**Scope:** `tmux.conf`, `tmux-status-left` (new), `nix/modules/home/programs/tmux.nix`, `nix/modules/home/dotfiles/shared.nix`, `Makefile.d/install.mk`

## Context

Follow-up to the first tmux improvement pass. Four focused changes: one cleanup, one performance improvement, one new feature, one UX toggle.

## Changes

### A1 — Remove duplicate `set -g status-keys vi`

`set -g status-keys vi` appears on both line 25 and line 33 of `tmux.conf`. Remove line 33.

### A2 — Merge status-left into one subprocess

**Problem:** `status-left` makes two `#(...)` shell calls every `status-interval` (5s):

1. `~/.tmux-short-path #{pane_current_path}` — abbreviated path
2. `cd #{pane_current_path}; git rev-parse --abbrev-ref HEAD` — git branch

**Solution:** New script `tmux-status-left` that:

- Takes `#{pane_current_path}` as its sole argument
- Inlines the path-shortening logic (same `case`-based HOME substitution + loop as `tmux-short-path`, no subprocess fork)
- Gets the git branch with `git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null`
- Outputs a single pre-formatted tmux colour string combining both pieces

`status-left` becomes:

```
set -g status-left "#[fg=green,bg=#303030][#S:#I.#P]#[fg=#303030]#(~/.tmux-status-left #{pane_current_path})"
```

`tmux-short-path` is kept as a standalone utility (used independently, tested, deployed). `tmux-status-left` does not call it — logic is inlined to avoid the extra fork.

Deployment: symlink `~/.tmux-status-left`, add to `nix/modules/home/dotfiles/shared.nix`, add to `Makefile.d/install.mk` DOTFILES_MAP.

### A3 — Session persistence with resurrect + continuum

**tmux.conf** additions (for TPM / Docker path):

```
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
```

**tmux.nix** additions:

```nix
plugins = with pkgs.tmuxPlugins; [
  cpu
  resurrect
  {
    plugin = continuum;
    extraConfig = ''
      set -g @continuum-restore 'on'
      set -g @continuum-save-interval '15'
    '';
  }
];
```

The `stripTPM` function in `tmux.nix` is extended to strip the four new `@plugin` / `@continuum-*` lines from the Nix-built `extraConfig` (Nix handles them via `plugins` + `extraConfig`).

Keybinds (built into tmux-resurrect): `prefix + Ctrl-s` (save), `prefix + Ctrl-r` (restore).

### A4 — Enable pane-border-status

```
set -g pane-border-status "off"  →  set -g pane-border-status "bottom"
```

The format string is already defined:

```
set -g pane-border-format "[#[fg=white]#{?pane_active,#[bold],} :#P: #T #[fg=default,nobold]]"
```

## Files Changed

| File                                   | Action                                                                                    |
| -------------------------------------- | ----------------------------------------------------------------------------------------- |
| `tmux.conf`                            | Modify: remove duplicate, add resurrect/continuum, pane-border-status, update status-left |
| `tmux-status-left`                     | Create: combined path+branch status script                                                |
| `nix/modules/home/programs/tmux.nix`   | Modify: add resurrect/continuum plugins, extend stripTPM                                  |
| `nix/modules/home/dotfiles/shared.nix` | Modify: add `.tmux-status-left` entry                                                     |
| `Makefile.d/install.mk`                | Modify: add `tmux-status-left` to DOTFILES_MAP                                            |

## What Is Not Changed

- `tmux-short-path` kept as-is (standalone utility)
- All keybindings unchanged
- Status bar content and colours unchanged (only the script call changes)
- `tmux-kube` unchanged
