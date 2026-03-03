{ config, pkgs, lib, username, ... }:

let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  # Nix core configuration
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.settings.auto-optimise-store = true;

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
    home = if isDarwin then "/Users/${username}" else "/home/${username}";
    description = "${username}";
    shell = pkgs.zsh;
  };
}
