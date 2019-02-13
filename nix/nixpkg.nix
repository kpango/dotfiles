{ config, pkgs, ... }:
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
      #   unstable = import <nixos-unstable> {
      #     # Pass the nixpkgs config to the unstable alias
      #     # to ensure `allowUnfree = true;` is propagated:
      #     config = config.nixpkgs.config;
      #   };
      # };
      pulseaudio = true;
    };
    overlays = [(self: super: {
      # bat = super.unstable.bat;
      # exa = super.unstable.exa;
      # chromium = super.unstable.chromium;
      neovim = super.neovim.override {
        withPython = true;
        withPython3 = true;
        withRuby = true;
        vimAlias = true;
      };
      nix-home = super.callPackage ./pkgs/nix-home {};
      openvpn = super.openvpn.override {
        pkcs11Support = true;
      };
      zathura.useMupdf = true;
    })];
  };
}
