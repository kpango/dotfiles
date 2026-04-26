# Makefile Modularization Design

## Overview

The goal of this project is to refactor the root `Makefile` by modularizing it into smaller, domain-specific files within a centralized `make/` directory. This will improve maintainability, readability, and organization of the project's build and setup scripts.

## Directory Structure

- `make/`: New directory at the project root to hold the split Makefile modules.

## Modules Breakdown

1. `make/variables.mk`: Global variable definitions (`ROOTDIR`, `USER`, `GITHUB_*`, `DOCKER_*`, `VERSION`, etc.).
2. `make/dotfiles.mk`: Core dotfiles management targets (`copy`, `link`, `clean`, `perm`, `zsh`, `bash`, `run`, `echo`).
3. `make/docker.mk`: Docker build and registry targets (`build`, `prod_build`, `docker_build`, `init_buildx`, `create_buildx`, etc.).
4. `make/arch.mk`: Arch Linux configuration targets (`arch_link`, `arch_p1_link`, `arch_desk_link`).
5. `make/macos.mk`: macOS configuration targets (`mac_link`).
6. `make/nix.mk`: Nix development environment targets (`nix/setup`).
7. `make/git.mk`: Source control targets (`git_push`, `github_check`).

## Main Makefile

The root `Makefile` will be simplified to:

1. Declare the `.PHONY` targets (by including `.PHONY` declarations from the modules or defining them at the top).
2. Include the modules in the correct order (variables first).

Example:

```makefile
include make/variables.mk
include make/dotfiles.mk
include make/docker.mk
include make/arch.mk
include make/macos.mk
include make/nix.mk
include make/git.mk
```
