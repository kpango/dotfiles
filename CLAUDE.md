# Dotfiles Project — Claude Code Instructions

## Project Overview

This is kpango's personal dotfiles repository for Arch Linux (zen kernel) + Sway/Wayland environment. It manages configuration for: Zsh, Tmux, Ghostty, Helix, Sway, Waybar, Kanshi, Docker, systemd user services, Go environment, Nix, and Claude Code itself.

## Repository Structure

```
dotfiles/
├── Makefile              # Top-level; delegates to Makefile.d/
├── Makefile.d/           # Modular make targets
│   └── install.mk        # Primary install/link/copy logic
├── claude/               # Claude Code config (-> ~/.claude/)
│   ├── settings.json     # Global settings (symlinked)
│   ├── settings.local.json  # Global permissions (symlinked)
│   ├── installed_plugins.json  # Plugin manifest (envsubst -> ~/.claude/plugins/)
│   └── CLAUDE.md         # Global AI instructions (symlinked)
├── .claude/              # Project-level Claude config (NOT symlinked)
│   ├── settings.json     # Project plugin enablement
│   └── settings.local.json  # Project-specific permissions
├── sway/                 # Sway WM config
├── ghostty.conf          # Ghostty terminal config
├── tmux.conf             # Tmux config
├── zsh/                  # Zsh config files
├── zshrc / zshenv        # Zsh entry points
├── helix/                # Helix editor config
├── systemd/              # systemd user services
└── arch/                 # Arch-specific configs (waybar, etc.)
```

## Key Makefile Targets

- `make dotfiles/install` — symlink/copy all dotfiles to $HOME
- `make claude/install` — deploy Claude Code config (runs after dotfiles/install)
- `make arch/install` — full Arch Linux setup (runs dotfiles/install + AUR packages)
- `make dotfiles/clean` — remove all symlinks

## Claude Config Deployment

`settings.json` and `settings.local.json` in `claude/` are **symlinked** to `~/.claude/`.
`installed_plugins.json` is processed via `envsubst` and copied to `~/.claude/plugins/`.
`CLAUDE.md` in `claude/` is **symlinked** to `~/.claude/CLAUDE.md`.

The dotfiles root `CLAUDE.md` (this file) applies only when Claude Code is run from this directory.

## Working in This Repo

- Always use `make` targets for installation, never manual symlinks
- Test symlinks with `ls -la ~/<target>` before committing
- JSON files must be valid — check with `python3 -m json.tool`
- Zsh config changes: source files are in `zsh/` directory
- systemd services: use `systemctl --user` for user services
- Packages: prefer `pacman` over AUR when available; use `paru` for AUR

## Common Tasks

**Add new dotfile mapping:**

1. Add entry to `DOTFILES_MAP` in `Makefile.d/install.mk`
2. Run `make dotfiles/install`

**Update Claude settings:**

1. Edit `claude/settings.json` or `claude/settings.local.json`
2. Changes take effect immediately (hot-reload)

**Add new plugin:**

1. Add to `enabledPlugins` in `claude/settings.json`
2. Add marketplace to `extraKnownMarketplaces` if new source
3. Update `claude/installed_plugins.json` template

**Update systemd service:**

1. Edit file in `systemd/user/`
2. Run `systemctl --user daemon-reload && systemctl --user restart <service>`

## Style Notes

- No trailing whitespace in config files
- JSON: 2-space indentation
- Shell scripts: set -euo pipefail header
- Makefile: tabs for recipe lines, spaces for variable assignments

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
