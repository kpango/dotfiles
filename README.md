# dotfiles

[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fkpango%2Fdotfiles.svg?type=shield)](https://app.fossa.io/projects/git%2Bgithub.com%2Fkpango%2Fdotfiles?ref=badge_shield)

---

kpango's comprehensive cross-platform dotfiles and fullstack development environments in Docker.

## Overview

This repository contains personal system configurations, terminal setups, and containerized development environments. It supports multiple operating systems and orchestrates setup via a modular `Makefile`.

### Core Tools

- **Editor:** [Helix](https://helix-editor.com/) with extensive language support (Go, Rust, Nim, Python, C/C++, Ruby, JS, HTML/CSS) and custom themes.
- **Shell:** `zsh` plugin management via [Sheldon](https://github.com/rossmacarthur/sheldon) with categorized modules (tmux, git, k8s, docker, os-specific).
- **Multiplexer:** `tmux` with customized configurations and K8s integrations.
- **Terminal:** [Ghostty](https://github.com/ghostty-org/ghostty) configurations.
- **Prompt:** Starship prompt.
- **Version Control:** Git (with global gitconfig, gitignore, and gitattributes).

### Operating Systems Supported

- **macOS:** Configurations including Brewfile, launch agents (autoupdate, ulimit), and customized docker settings.
- **Arch Linux:** Full desktop setup including Sway/i3, Waybar, Wofi, Fcitx5, PulseAudio, and specific systemd services/udev rules.
- **NixOS:** Flake-based NixOS configurations (`nix/flake.nix` with core modules and hosts).

### Containerized Development Environments

Fully Dockerized development environments to maintain a clean host system. Managed via `make build`:

- Base development environment (`dev.Dockerfile`)
- Language/Tool-specific environments: Go, Rust, Dart, Nim, Kubernetes (`k8s.Dockerfile`), and Google Cloud (`gcloud.Dockerfile`).
- Multi-architecture Docker builds powered by buildx.

## Requirements

- `ghq`
- `make`
- `docker`
- `bash` / `zsh`

## Installation

It is recommended to use `ghq` to manage the repository location.

```shell
# Configure ghq root
git config --global ghq.root $HOME/go/src

# Get the repository
ghq get kpango/dotfiles
cd $HOME/go/src/github.com/kpango/dotfiles

# Install dotfiles (symlink or copy)
make link # or 'make copy'
```

### OS-Specific Setup

- **macOS:** `make mac_link` or `make mac_copy`
- **Arch Linux:** Check the respective install scripts under `arch/` and Makefile rules.
- **Docker Environments:** `make build` / `make prod`

## Contribution

1. Fork it (http://github.com/kpango/dotfiles/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

[kpango](https://github.com/kpango)

## License

[![FOSSA Status](https://app.fossa.io/api/projects/git%2Bgithub.com%2Fkpango%2Fdotfiles.svg?type=large)](https://app.fossa.io/projects/git%2Bgithub.com%2Fkpango%2Fdotfiles?ref=badge_large)
