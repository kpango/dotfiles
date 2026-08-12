{
  pkgs,
  lib,
  inputs,
  username,
  homeDirectory,
  isDarwin,
  ...
}:

{
  # Nix daemon configuration.
  #
  # Only applied on NixOS. On Darwin, Nix is installed and managed by
  # Determinate Nix, which forces `nix.enable = false` (see
  # modules/darwin/system.nix); every option below would be silently ignored
  # there, so it is scoped out rather than left as dead config. Determinate
  # already enables flakes and trusts the installing user by default.
  nix = lib.mkIf (!isDarwin) {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Allow the primary user to use trusted nix features (nix copy, custom substituters, etc.)
      trusted-users = [
        "root"
        username
      ];
    };

    # Store deduplication. Uses the optimise timer rather than
    # settings.auto-optimise-store, which upstream flags as store-corrupting.
    optimise.automatic = true;

    # Automatic GC: discard generations older than 14 days, on the NixOS
    # systemd timer (nix.gc.dates). On Darwin, GC is Determinate's business.
    gc = {
      automatic = true;
      options = lib.mkDefault "--delete-older-than 14d";
    };

    # Make `nix run nixpkgs#...` use the same nixpkgs as the flake
    registry.nixpkgs.flake = inputs.nixpkgs;

    # Make legacy nix commands (like `nix-shell -p ...`) use the same nixpkgs
    nixPath = [ "nixpkgs=${inputs.nixpkgs}" ];
  };

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
