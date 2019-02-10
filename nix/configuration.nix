# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

{
  imports = [
    <nixos-hardware/lenovo/thinkpad/x1>
    ./hardware-configuration.nix
    ./users.nix
    ./services.nix
    ./fonts.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    blacklistedKernelModules = [ "snd_pcsp" "pcspkr" ];
    kernelPackages = pkgs.linuxPackages_latest;
    plymouth.enable = true;
    supportedFilesystems = [ "xfs" "zfs" ];
    kernel = {
      sysctl = {
        "kernel.perf_event_paranoid" = 0;
      };
    };
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
      grub = {
        enable = true;
        version = 2;
        device = "nodev";
        efiSupport = true;
        gfxmodeEfi = "1024x768";
        zfsSupport = true;
      };
    };
    initrd = {
      kernelModules = [
        "dm_mod"
        "dm-crypt"
        "ext4"
        "ecb"
      ];
      luks.devices = [
        {
          name = "root";
          device = "/dev/nvme0n1p2";
          preLVM = true;
          allowDiscards = true;
        }
      ];
    };
  };

  fileSystems."/".label = "root";
  fileSystems."/boot".label = "boot";

  networking = {
    hostName = "kpango";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 80 443 8080 8000 8443 9999 ];
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
      extraCommands = ''
        iptables -I INPUT -p udp -m udp --dport 32768:60999 -j ACCEPT
      '';
    };
    nat = {
      enable = true;
      internalInterfaces = ["ve-+"];
      externalInterface = "wlp4s0";
    };
  };

  sound.enable = true;

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
    maxJobs = lib.mkDefault 8;
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
  };

  # Set your time zone.
  # Home: "Europe/Amsterdam";
  #time.timeZone = "Europe/Amsterdam";
  # Virginia
  time.timeZone = "Asia/Tokyo";

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
      packageOverrides = pkgs: {
        unstable = import <nixos-unstable> {
          # Pass the nixpkgs config to the unstable alias
          # to ensure `allowUnfree = true;` is propagated:
          config = config.nixpkgs.config;
        };
      };
      pulseaudio = true;
    };
    overlays = [(self: super: {
      bat = super.unstable.bat;
      exa = super.unstable.exa;
      chromium = super.unstable.chromium;
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
      ++ haskell-packages
      ++ lua-packages
      ++ nix-packages
      ++ python-packages
      ++ texlive-packages
      ++ user-packages;

    gnome3.excludePackages = with pkgs.gnome3; [ epiphany evolution totem vino yelp accerciser ];
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

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs = {
    zsh = {
      enable = true;
      autosuggestions.enable = true;
      enableCompletion = true;
      syntaxHighlighting.enable = true;
    };
    #slock.enable = true;
    docker.enable =true
    tmux.enable = true;
    ssh.forwardX11 = false;
    ssh.startAgent = true;
  };

  virtualisation.docker = {
    enable = true;
    enableOnBoot = true;
  };

  security.sudo.enable = true;

  documentation.info.enable = true;
  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system = {
    stateVersion = "18.09"; # Did you read the comment?
    autoUpgrade = {
      enable = true;
      flags = lib.mkForce
        [
          "--fast"
          "--no-build-output"
          "-I" "nixpkgs=/etc/nixos/nixpkgs-channels"
        ];
    };
    services = {
      nixos-upgrade = {
        path = [ pkgs.git  ];
        preStart = ''
            if [ ! -e /etc/nixos/nixpkgs-channels  ]; then
              cd /etc/nixos
              git clone git://github.com/NixOS/nixpkgs-channels.git -b nixos-${nixosVersion}
            fi
            cd /etc/nixos/nixpkgs-channels
            git pull
            if [ -e /etc/nixos/dotfiles  ]; then
              cd /etc/nixos/dotfiles
              git pull
            fi
          '';
      };
    };
  extraConfig = ''
      DefaultCPUAccounting=true
      DefaultBlockIOAccounting=true
      DefaultMemoryAccounting=true
      DefaultTasksAccounting=true
    '';
  };
}
