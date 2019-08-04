{ config, pkgs, lib, ... }:
{
  nix = {
    autoOptimiseStore = true;
    buildCores = 8;
    gc = {
      automatic = true;
      options = "--delete-older-than 14d";
    };
    daemonNiceLevel = 10;
    daemonIONiceLevel = 4;
    package = pkgs.nixUnstable;
    useChroot = true;
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
      "https://cache.nixos.org/"
      "https://nixcache.reflex-frp.org"
      "http://hydra.qfpl.io"
      "https://snack.cachix.org"
      "https://cache.mozilla-releng.net"
    ];
    trustedBinaryCaches = [ https://hydra.nixos.org ];
    binaryCachePublicKeys = [
      "hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs="
      "ryantrinkle.com-1:JJiAKaRv9mWgpVAz8dwewnZe0AzzEAzPkagE9SP5NWI="
      "qfpl.io:xME0cdnyFcOlMD1nwmn6VrkkGgDNLLpMXoMYl58bz5g="
      "snack.cachix.org-1:yWpdDCWeJzVAQUSM1Ol0E3PCVbG4k2wRAsZ/b5L3huc="
    ];
    trustedUsers = [ "@wheel" ];
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
