{ pkgs, lib, inputs, username, homeDirectory, ... }:

{
  # Nix core configuration
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
    # Allow the primary user to use trusted nix features (nix copy, custom substituters, etc.)
    trusted-users = [ "root" username ];
  };

  # Automatic GC: discard generations older than 14 days.
  # Schedule is platform-specific: NixOS uses nix.gc.dates (systemd timer);
  # nix-darwin uses nix.gc.interval (launchd, defaults to weekly).
  nix.gc = {
    automatic = true;
    options = lib.mkDefault "--delete-older-than 14d";
  };

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

  # User Configuration
  users.users.${username} = {
    name = "${username}";
    home = homeDirectory;
    description = "${username}";
    shell = lib.mkDefault pkgs.zsh;
  };
}
