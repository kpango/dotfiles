# Claude Code Optimization Design

**Date:** 2026-05-22  
**Status:** Implemented

## Overview

Manage Claude Code configuration via Dotfiles so the same experience can be reproduced in any environment.

## Changed Files

| File                            | Change  | Description                                   |
| ------------------------------- | ------- | --------------------------------------------- |
| `claude/settings.json`          | Updated | All settings consolidated, new features added |
| `claude/settings.local.json`    | Updated | Permissions cleaned up                        |
| `claude/installed_plugins.json` | Updated | All plugins defined at user scope             |
| `claude/CLAUDE.md`              | New     | Global AI instructions                        |
| `claude/hooks/notify.sh`        | New     | Notification hook (dunstify support)          |
| `claude/hooks/on-stop.sh`       | New     | Task completion hook                          |
| `CLAUDE.md`                     | New     | AI instructions for dotfiles project          |
| `Makefile.d/install.mk`         | Updated | Added CLAUDE.md symlink and hooks deployment  |

## Key Added Settings

### settings.json New Features

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "language": "ja",
  "effortLevel": "high",
  "alwaysThinkingEnabled": true,
  "showThinkingSummaries": true,
  "tui": "fullscreen",
  "viewMode": "verbose",
  "preferredNotifChannel": "ghostty",
  "autoMemoryEnabled": true,
  "autoMemoryDirectory": "~/.claude/memory",
  "enableAllProjectMcpServers": true,
  "worktree": { "baseRef": "fresh", "bgIsolation": "worktree" },
  "teammateMode": "auto",
  "attribution": { ... },
  "hooks": { "Notification": [...], "Stop": [...] },
  "env": { "CLAUDE_CODE_ENABLE_TELEMETRY": "0" }
}
```

### Plugin Integration

Enabled at **global scope** (`settings.json`):

| Plugin                                   | Capability                                                 |
| ---------------------------------------- | ---------------------------------------------------------- |
| `superpowers@claude-plugins-official`    | TDD, debugging, brainstorming workflows                    |
| `github@claude-plugins-official`         | PR/Issue management                                        |
| `gopls-lsp@claude-plugins-official`      | Go LSP support                                             |
| `clangd-lsp@claude-plugins-official`     | C/C++ LSP support                                          |
| `feature-dev@claude-plugins-official`    | Feature development workflow                               |
| `code-review@claude-plugins-official`    | Multi-agent code review                                    |
| `skill-creator@claude-plugins-official`  | Custom skill creation                                      |
| `plugin-dev@claude-plugins-official`     | Plugin development workflow                                |
| `ecc@ecc`                                | 150+ specialized agents (Go, Rust, Python, security, etc.) |
| `document-skills@anthropic-agent-skills` | PDF/PPTX/DOCX processing                                   |
| `andrej-karpathy-skills@karpathy-skills` | Karpathy coding guidelines                                 |
| `claude-mem@thedotmack`                  | Persistent session memory                                  |

### Permission Cleanup

Consolidated individual entries into generic wildcards:

- e.g. `Bash(sudo pacman *)`, `Bash(systemctl *)`, etc.
- `Read(~/**)` allows reading the entire home directory

### Hooks

| Hook           | Script                       | Behavior                        |
| -------------- | ---------------------------- | ------------------------------- |
| `Notification` | `~/.claude/hooks/notify.sh`  | Notify via dunstify/notify-send |
| `Stop`         | `~/.claude/hooks/on-stop.sh` | Notify on task completion       |

### Multi-Agent Configuration

- `worktree.bgIsolation: "worktree"` — background agents run isolated in git worktrees
- `worktree.baseRef: "fresh"` — branches from the remote default branch
- `teammateMode: "auto"` — uses tmux when available

### Memory Management

- `autoMemoryDirectory: "~/.claude/memory"` — storage location for auto memory
- `~/.claude/CLAUDE.md` — global instructions (symlinked from dotfiles)

## Deployment (New Environment Setup)

```bash
# 1. Clone dotfiles
git clone https://github.com/kpango/dotfiles ~/go/src/github.com/kpango/dotfiles

# 2. Deploy dotfiles + Claude configuration
make claude/install

# 3. Install plugins (after launching Claude Code)
# /plugin install ecc@ecc
# /plugin install document-skills@anthropic-agent-skills
# /plugin install andrej-karpathy-skills@karpathy-skills
# /plugin install claude-mem@thedotmack

# 4. Verify memory directory
mkdir -p ~/.claude/memory
```

## Operations Requiring Manual Execution

Due to self-modification protection in auto mode, the following require manual execution:

```bash
# CLAUDE.md symbolic link (automated by make dotfiles/install)
ln -sfvn ~/go/src/github.com/kpango/dotfiles/claude/CLAUDE.md ~/.claude/CLAUDE.md

# Hook script deployment (automated by make claude/install)
mkdir -p ~/.claude/hooks ~/.claude/memory
install -m 755 ~/go/src/github.com/kpango/dotfiles/claude/hooks/notify.sh ~/.claude/hooks/notify.sh
install -m 755 ~/go/src/github.com/kpango/dotfiles/claude/hooks/on-stop.sh ~/.claude/hooks/on-stop.sh
```
