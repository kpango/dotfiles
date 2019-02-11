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
        gtop
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
        which
        xbindkeys
        xclip
        xsel
      ];
      crypt-packages = [
        git-crypt
        gnupg1
      ];
      development-packages = [
        autoconf
        automake
        cachix
        clang-tools
        ctags
        flameGraph
        gcc
        git
        git-lfs
        gitAndTools.gitFull
        gitAndTools.hub
        global
        gnumake
        linuxPackages.perf
        llvmPackages.clang-unwrapped.python # Needed for run-clang-tidy.py
        perf-tools
        rtags
        shellcheck
        unifdef
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
        aspell
        aspellDicts.en
        aspellDicts.it
        aspellDicts.nb
        borgbackup
        chromium
        evince
        feh
        firefox
        ghostscript
        gimp
        gv
        imagemagick
        inkscape
        libreoffice
        liferea
        meld
        pandoc
        pass
        pdf2svg
        pdftk
        pymol
        shutter
        spotify
        vlc
        wavebox
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
    etc."libinput/local-overrides.quirks".text = ''
      [Touchpad touch override]
      MatchUdevType=touchpad
      MatchName=*Magic Trackpad 2
      AttrPressureRange=4:0
    '';
  };
}
