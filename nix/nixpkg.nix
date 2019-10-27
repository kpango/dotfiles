{ config, pkgs, ... }:
let
  unstableTarball = (import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs-channels/archive/nixos-unstable.tar.gz"));
  waylandOverlay = (import (builtins.fetchTarball "https://github.com/colemickens/nixpkgs-wayland/archive/master.tar.gz"));
in
{
  nixpkgs = {
    config = {
      # Allow proprietary packages
      allowUnfree = true;
      allowBroken = false;
      allowUnfreeRedistributable = true;
      # Configure Firefox
      chromium = {
       enableGoogleTalkPlugin = true;
      };
      # Create an alias for the unstable channel
      # packageOverrides = pkgs: {
      #   unstable = import unstableTarball {
      #     config = config.nixpkgs.config;
      #   };
      # };
      packageOverrides = pkgs: {
        unstable = import <nixos-unstable> {
          config = config.nixpkgs.config;
        };
      };
      pulseaudio = true;
    };
    overlays = [
      unstableTarball
      waylandOverlay
    ];
    overlays = [(self: super: {
      #bat = super.unstable.bat;
      #exa = super.unstable.exa;
      #chromium = super.unstable.chromium;
      chromium = {
        enablePepperFlash = false;
        enablePepperPdf = true;
        enableWideVine = true;
      };
      neovim = super.neovim.override {
        withPython = true;
        withPython3 = true;
        withRuby = true;
        vimAlias = true;
      };
      nix-home = super.callPackage ./pkgs/nix-home {};
      # openvpn = super.openvpn.override {
      #   pkcs11Support = true;
      # };
      # zathura.useMupdf = true;
    })];
  };
}
