{ config, pkgs, lib, ... }:
{
  nix = {
    package = pkgs.nixUnstable;
    useSandbox = true;
    extraOptions = ''
      build-cores = 8
      gc-keep-outputs = true
      gc-keep-derivations = true
      auto-optimise-store = true
      require-sigs = false
      trusted-users = root
    '';
    binaryCaches = [
      "https://cache.nixos.org"
      "https://cache.mozilla-releng.net"
    ];
  };
  # Select internationalisation properties.
  i18n = {
    consoleFont = "ricty";
    consoleKeyMap = "us";
    defaultLocale = "en_US.UTF-8";
    inputMethod = {
      enabled = "fcitx";
      fcitx.engines = with pkgs.fcitx-engines; [
        anthy
        mozc
      ];
    };
  };
}
