{ config, pkgs, lib, ... }:
{
  # List packages installed in system profile.
  environment = {
    systemPackages = with pkgs;
    let
      core-packages = [
        axel
        acpi
        atool
        bat
        binutils
        coreutils
        cryptsetup
        curl
        dmidecode
        efibootmgr
        exa
        iputils
        neovim
        networkmanager
        pciutils
        psmisc
        rsync
        tldr
        usbutils
        wayland
        sway
        dmenu
        which
        xbindkeys
        xclip
        xsel
        ranger
        rxvt_unicode
        # zathura
      ];
      crypt-packages = [
        git-crypt
      ];
      development-packages = [
        autoconf
        automake
        clang-tools
        ctags
        flameGraph
        gcc
        git
        git-lfs
        gitAndTools.gitFull
        gitAndTools.hub
        shellcheck
      ];
      nix-packages = [
        nix-home
        nix-prefetch-git
        nixos-container
        nixpkgs-lint
        nox
        patchelf
      ];
      user-packages = [
        chromium
        ghostscript
      ];
    in
      core-packages
      ++ crypt-packages
      ++ development-packages
      ++ nix-packages
      ++ user-packages;

    variables = {
      NIX_PATH = lib.mkForce "nixpkgs=/etc/nixos/nixpkgs-channels:nixos-config=/etc/nixos/configuration.nix";
      GIT_EDITOR = lib.mkForce "nvim";
      EDITOR = lib.mkForce "nvim";
    };
    etc = {
      "resolv.conf" = with lib; with pkgs; {
        source = writeText "resolv.conf" ''
          ${concatStringsSep "\n" (map (ns: "nameserver ${ns}") config.networking.nameservers)}
          options edns0
        '';
      };
      "libinput/local-overrides.quirks".text = ''
        [Touchpad touch override]
        MatchUdevType=touchpad
        MatchName=*Magic Trackpad 2
        AttrPressureRange=4:0
      '';
    };
  };
}
