{ ... }:

{
  imports = [
    ./packages
    ./dotfiles/shared.nix
    ./dotfiles/linux.nix
    ./dotfiles/darwin.nix
    ./programs/zsh.nix
    ./programs/git.nix
    ./programs/tmux.nix
    ./programs/helix.nix
    ./services.nix
  ];
}