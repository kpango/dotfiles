{ config, pkgs, lib, username, hostname, ... }:

{
  imports = [
    ./common.nix
  ];

  # Bootloader setup
  boot.loader = {
    systemd-boot.enable = true;
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot/efi";
    };
  };

  # Kernel configuration (shared)
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelParams = [
    "quiet"
    "nowatchdog"
    "acpi.ec_no_wakeup=1"
    "intel_iommu=on"
    "intel_pstate=no_hwp"
    "psmouse.proto=imps"
    "psmouse.synaptics_intertouch=1"
    "console=ttyS0,19200n8"
  ];
  boot.blacklistedKernelModules = [
    "pcspkr"
    "intel_pmc_bxt"
    "iTCO_vendor_support"
    "iTCO_wdt"
    "snd_pcsp"
  ];

  # High-performance Sysctls
  boot.kernel.sysctl = {
    "fs.aio-max-nr" = 19349474;
    "fs.file-max" = 19349474;
    "fs.epoll.max_user_watches" = 39688724;
    "kernel.threads-max" = 4000000;
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_fastopen" = 3;
    "net.ipv4.tcp_tw_reuse" = 1;
    "vm.max_map_count" = 262144;
    "vm.overcommit_memory" = 2;
    "vm.swappiness" = 1;
  };

  boot.tmp = {
    useTmpfs = true;
    cleanOnBoot = true;
  };
  boot.supportedFilesystems = [
    "xfs"
  ];

  # FileSystems root (assumes generic bootstrap labels)
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/root";
      fsType = "xfs";
      options = [
        "noatime"
        "nodiratime"
        "discard"
      ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
    };
  };

  # Networking
  networking = {
    hostName = hostname;
    networkmanager = {
      enable = true;
      dns = "dnsmasq";
    };
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "8.8.8.8"
      "8.8.4.4"
    ];
    usePredictableInterfaceNames = false;
    firewall = {
      enable = true;
      allowPing = false;
      allowedTCPPorts = [
        22
        80
        443
        3000
        8080
        8000
        8443
        9999
        27036
        27037
      ];
      allowedUDPPorts = [
        27031
        27037
      ];
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
      checkReversePath = false;
      extraCommands = "iptables -I INPUT -p udp -m udp --dport 32768:60999 -j ACCEPT";
    };
    nat = {
      enable = true;
      internalInterfaces = [
        "ve-+"
      ];
      externalInterface = "wlp4s0";
    };
    extraHosts = ''
      127.0.0.1 ${hostname} ${hostname}.local localhost
      127.0.0.2 other-localhost
      10.0.1.1 kpango-router
      10.0.1.2 kpango-switch
      192.168.1.1 kato-router
      192.168.1.2 kato-switch
      ::1 ${hostname} ${hostname}.local localhost
    '';
    bridges.cbr0.interfaces = [ ];
    interfaces.cbr0.ipv4.addresses = [
      {
        address = "10.10.0.1";
        prefixLength = 24;
      }
    ];
  };

  # Time and Locale
  time = {
    timeZone = "Asia/Tokyo";
    hardwareClockInLocalTime = true;
  };
  i18n.defaultLocale = "en_US.UTF-8";

  # Nixpkgs Config
  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = false;
    allowUnfreeRedistributable = true;
    pulseaudio = true;
    chromium = {
      enablePepperFlash = false;
      enablePepperPdf = true;
      enableWideVine = true;
    };
  };
  nixpkgs.overlays = [
    (self: super: {
      neovim = super.neovim.override {
        withPython3 = true;
        withRuby = true;
        vimAlias = true;
      };
    })
  ];

  # OS Level Programs
  programs.zsh = {
    autosuggestions.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
  };
  programs.tmux.enable = true;
  programs.ssh.startAgent = true;
  programs.sway.enable = true;
  programs.light.enable = true;

  # Core System Packages
  environment.systemPackages = with pkgs; [
    atool
    autoconf
    automake
    bat
    binutils
    clang-tools
    coreutils
    cryptsetup
    ctags
    curl
    efibootmgr
    exa
    flameGraph
    fwupd
    gcc
    git
    git-crypt
    hub
    inetutils
    iputils
    jq
    lshw
    neovim
    nix-prefetch-git
    patchelf
    pciutils
    psmisc
    rxvt_unicode
    shellcheck
    tldr
    usbutils
    wget
    xbindkeys
    xclip
    xsel
  ];
  environment.variables = {
    GIT_EDITOR = lib.mkForce "hx";
    EDITOR = lib.mkForce "hx";
  };
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Touchpad touch override]
    MatchUdevType=touchpad
    MatchName=*Magic Trackpad 2
    AttrPressureRange=4:0
  '';

  # System Services
  services.tailscale.enable = true;
  services.fstrim.enable = true;
  services.timesyncd.enable = true;
  services.locate.enable = true;
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
    extraConfig = "StreamLocalBindUnlink yes";
  };
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      cups-bjnp
      gutenprint
      gutenprintBin
      hplip
      hplipWithPlugin
    ];
  };

  # Virtualization & Containers
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      liveRestore = true;
      autoPrune.enable = true;
      storageDriver = "overlay2";
      extraOptions = "--insecure-registry ${hostname}.local:80";
    };
    lxd.enable = true;
    libvirtd.enable = true;
  };

  # Security Hardening
  security.sudo = {
    wheelNeedsPassword = false;
    extraConfig = ''
      Defaults !always_set_home
      Defaults env_keep+="HOME"
    '';
  };
  security.pam.loginLimits = [
    {
      domain = "*";
      type = "soft";
      item = "nofile";
      value = "65535";
    }
    {
      domain = "*";
      type = "hard";
      item = "nofile";
      value = "65535";
    }
  ];

  # User Configuration
  users.mutableUsers = false;
  users.users.${username} = {
    isNormalUser = true;
    uid = 1000;
    createHome = true;
    extraGroups = [
      "audio"
      "disk"
      "docker"
      "input"
      "libvirtd"
      "lxd"
      "mysql"
      "networkmanager"
      "systemd-journal"
      "vboxusers"
      "video"
      "wheel"
      "wireshark"
    ];
  };

  # Audio (Pipewire setup replacing pulseaudio/alsa from Arch config)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa = {
      enable = true;
      support32Bit = true;
    };
    pulse.enable = true;
  };

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [
      "HackGen Console NF"
    ];
    emoji = [
      "Noto Color Emoji"
    ];
  };

  system.stateVersion = "23.11";
}
