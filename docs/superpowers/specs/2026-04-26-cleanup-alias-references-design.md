# Cleanup Legacy Alias References

## Context

Following the migration of the `alias` file contents into `zsh/20-docker.zsh`, we need to purge all remaining references to `alias` and `~/.aliases` throughout the repository to complete the transition.

## Approach

We will clean up the following locations:

1. `Makefile.d/dotfiles.mk`:
   - Remove `alias .aliases` from the `DOTFILES_MAP`.
   - Update the `run:` target to `source $(ROOTDIR)/zsh/20-docker.zsh && devrun` instead of sourcing `alias`.
   - Remove the `echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc` append operations from the `copy:` and `link:` targets.
2. `nix/modules/home/dotfiles/shared.nix`:
   - Remove the line linking `alias` to `.aliases`.
3. `nix/modules/home/programs/zsh.nix`:
   - Remove `source ~/.aliases` from the `initExtra` block.

This will fully decouple the environment from the legacy alias configuration file.
