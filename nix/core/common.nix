{ pkgs, inputs, username, settings, homeDirectory, ... }:

{
  # Nix core configuration
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.auto-optimise-store = true;

  # Make `nix run nixpkgs#...` use the same nixpkgs as the flake
  nix.registry.nixpkgs.flake = inputs.nixpkgs;

  # Make legacy nix commands (like `nix-shell -p ...`) use the same nixpkgs
  nix.nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];

  # OS Level Programs
  programs.zsh.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    hackgen-nf-font
  ];

  # Core System Packages for both Linux and macOS
  environment.systemPackages = with pkgs; [
    tailscale
  ];

  # User Configuration
  users.users.${username} = {
    name = "${username}";
    home = homeDirectory;
    description = "${username}";
    shell = pkgs.zsh;
  };
}
