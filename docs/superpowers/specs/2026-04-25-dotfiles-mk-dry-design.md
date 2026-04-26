# Dotfiles Makefile DRY Refactor

## Overview

The `Makefile.d/dotfiles.mk` file currently contains a high degree of repetition, running identical `mkdir -p`, `cp`, `ln -sfv`, and `sudo rm -rf` commands across the exact same list of 20+ dotfiles. This spec outlines a DRY (Don't Repeat Yourself) refactoring using a shell loop and a centralized mapping of source to destination paths.

## Architecture & Data Flow

### 1. Mapping Definition

We will define a multi-line Make variable `DOTFILES_MAP` containing space-separated pairs of source paths (relative to `ROOTDIR`) and destination paths (relative to `HOME`).

```makefile
define DOTFILES_MAP
alias .aliases
arch/ghostty.conf .config/ghostty/config
dockers/config.json .docker/config.json
dockers/daemon.json .docker/daemon.json
editorconfig .editorconfig
gemini/settings.json .gemini/settings.json
gemini/policies/policy.toml .gemini/policies/policy.toml
ghostty.conf .config/ghostty/config
gitattributes .gitattributes
gitconfig .gitconfig
gitignore .gitignore
gpg-agent.conf .gnupg/gpg-agent.conf
helix/config.toml .config/helix/config.toml
helix/languages.toml .config/helix/languages.toml
helix/themes/zed_kpango.toml .config/helix/themes/zed_kpango.toml
sheldon.toml .config/sheldon/plugins.toml
starship.toml .config/starship.toml
tmux.conf .tmux.conf
tmux-kube .tmux-kube
tmux.new-session .tmux.new-session
zshrc .zshrc
endef
export DOTFILES_MAP
```

### 2. Refactored Targets

The targets `copy`, `link`, and `clean` will loop over this map dynamically.

- **`copy` Target**:
  Will read pairs, run `mkdir -p` on the destination directory, and `cp` the file. Global paths (e.g., `/etc/docker`) will remain as individual commands.
- **`link` Target**:
  Will read pairs, run `mkdir -p`, and `ln -sfv` the files.

- **`clean` Target**:
  Will iterate the map and `sudo rm -rf` each mapped destination file from `HOME`. The remaining system-wide `/etc/*` deletions and unrelated `.config` folder deletions will be kept as a separate `sudo rm -rf` block to ensure a complete cleanup.

## Testing Strategy

After making the changes, we will run `make --dry-run copy`, `make --dry-run link`, and `make --dry-run clean` to ensure that the generated commands match the expected logic and paths.
