# Migrate Aliases into Zsh Scripts

## Context

The user has an `alias` file in the dotfiles root that is currently lazily loaded in `zsh/20-docker.zsh` (looking for `$HOME/.aliases`). The user wants to migrate these aliases directly into the Zsh scripts.

## Approach

1. Move the contents of the `alias` file directly into `zsh/20-docker.zsh`.
2. Remove the lazy-loading logic for `$HOME/.aliases` from `zsh/20-docker.zsh`.
3. Delete the legacy `alias` file from the repository.

This approach centralizes the Docker/Dev environment aliases and functions (such as `devrun`, `dockerrm`, `devin`) directly into the script responsible for Docker configurations.
