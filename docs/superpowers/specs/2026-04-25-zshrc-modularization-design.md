# Zshrc Modularization Design

## Overview

The root `zshrc` file is quite monolithic (~1800 lines) and difficult to navigate. This design breaks the monolithic `zshrc` into modular, domain-specific scripts stored in a new `zsh/` directory.

## Architecture

### 1. Directory Structure

Create a new `zsh/` directory in the dotfiles repository.

### 2. Modules

Files will be prefixed with numbers to guarantee load order where it matters (like tmux checking before other things run).

- **`zsh/00-tmux.zsh`**: Tmux entrypoint logic. This checks if tmux is installed, handles auto-attaching, sets socket paths, handles plugin manager installation, and exits the script if an attach happens (to prevent double-loading inside tmux).
- **`zsh/01-core.zsh`**: Base settings. Things like `stty`, `LANG`, `fastfetch`/`neofetch`, Sheldon loading, compinit (`zstyle` definitions), history config (`setopt`), global aliases (`L`, `f`, `rm`, `cp`, `mv`), bindkeys (`^R`, `^S`), directory navigation aliases (`mkcd`, `..`).
- **`zsh/10-editor.zsh`**: Everything related to `$EDITOR`, `VIM`, `NVIM_HOME`, `VIMRUNTIME`, `TERMCMD`, and nvim aliases (`vedit`, `vake`, `nvup`, `nvinit`).
- **`zsh/20-git.zsh`**: Git environment (`GIT_USER`) and complex Git aliases/functions (`gfr`, `gfrs`, `gcp`, `gcpf`, `grs`, `grsp`, `grf`).
- **`zsh/20-docker.zsh`**: Docker aliases (`dls`, `dsh`), `$DOCKER_BUILDKIT` setting.
- **`zsh/20-k8s.zsh`**: Kubernetes ecosystem. `kubectl`, `kind`, `k3d`, `helm`, `skaffold`, `linkerd`, `kustomize` lazy-loading completion functions and aliases.
- **`zsh/20-dev.zsh`**: Language environments (`Go`, `Rust`, `Python`, `Clang`, `PHP`), `$PATH` modifications, and Vald-specific developer functions (`valdup`, `valddep`, `valdmanifest`).
- **`zsh/20-os.zsh`**: OS updaters and package manager wrappers. Contains `brewup`, `aptup`, `archup`, `kacman`, `kacclean`, and mirror list updating scripts. Also includes hardware switch aliases (`discrete`, `integrated`).
- **`zsh/20-network.zsh`**: Network management. `nmcli` wrapper functions (`nmcliwifi`, `nmclr`), `tailscaleup`, `wakeonlan` aliases, `checkcountry` (whois/traceroute).
- **`zsh/20-ssh-gpg.zsh`**: `ssh-keygen` wrappers (`rsagen`, `edgen`), SSH config helpers, and GPG backup/restore scripts.

### 3. Main Zshrc

The monolithic `zshrc` will be stripped down to locate the `DOTFILES_DIR` and source all scripts inside the `zsh/` folder in alphabetical order. Wait, the `DOTFILES_DIR` must be computed before loading `00-tmux.zsh` or perhaps `00-tmux.zsh` doesn't strictly need it, but `01-core.zsh` does.

```zsh
#!/usr/bin/env zsh

# Determine DOTFILES_DIR
export GIT_USER=kpango
DOTFILE_URL="github.com/$GIT_USER/dotfiles"
if type ghq >/dev/null 2>&1; then
    export DOTFILES_DIR="$(ghq root)/$DOTFILE_URL"
elif [ -d "$HOME/go/src/$DOTFILE_URL" ]; then
    export DOTFILES_DIR="$HOME/go/src/$DOTFILE_URL"
else
    export DOTFILES_DIR="$HOME/dotfiles"
fi

for config_file in "$DOTFILES_DIR/zsh"/*.zsh; do
    source "$config_file"
done
```

## Testing Strategy

After splitting the file, verify that launching a new shell triggers the correct behavior. Test `make zsh` to verify it links correctly if any paths are needed. Use `zsh -n zshrc` to check for syntax errors.
