{ config, pkgs, lib, username, hostname, ... }:

{
  # Bootloader setup (merged from boot.nix)
  boot.loader.systemd-boot.enable = true; # Use efi or grub overrides depending on hardware
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # Kernel configuration (merged from boot.nix)
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelModules = [ "kvm-intel" "xhci_pci" "nvme" "psmouse" ];
  boot.kernelParams = [
    "quiet" "nowatchdog" "acpi.ec_no_wakeup=1" "intel_iommu=on"
    "intel_pstate=no_hwp"
    "psmouse.proto=imps"
    "psmouse.synaptics_intertouch=1"
    "console=ttyS0,19200n8"
  ];
  boot.blacklistedKernelModules = [ "pcspkr" "intel_pmc_bxt" "iTCO_vendor_support" "iTCO_wdt" "snd_pcsp" ];

  # High-performance Sysctls (merged from boot.nix)
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

  boot.tmp.useTmpfs = true;
  boot.tmp.cleanOnBoot = true;
  boot.supportedFilesystems = [ "xfs" ];

  # FileSystems (merged from system.nix)
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/root";
      fsType = "xfs";
      options = [ "noatime" "nodiratime" "discard" ];
    };
    "/boot" = {
      device = "/dev/disk/by-label/boot";
      fsType = "vfat";
    };
  };

  # Networking (merged from network.nix)
  networking = {
    hostName = hostname;
    networkmanager = { enable = true; dns = "dnsmasq"; };
    nameservers = [ "1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4" ];
    usePredictableInterfaceNames = false;
    firewall = {
      enable = true;
      allowPing = false;
      allowedTCPPorts = [ 22 80 443 3000 8080 8000 8443 9999 27036 27037 ];
      allowedUDPPorts = [ 27031 27037 ];
      allowedUDPPortRanges = [ { from = 60000; to = 61000; } ];
      checkReversePath = false;
      extraCommands = "iptables -I INPUT -p udp -m udp --dport 32768:60999 -j ACCEPT";
    };
    nat = { enable = true; internalInterfaces = ["ve-+"]; externalInterface = "wlp4s0"; };
    extraHosts = ''
      127.0.0.1 ${hostname} ${hostname}.local localhost
      127.0.0.2 other-localhost
      10.0.1.1 kpango-router
      10.0.1.2 kpango-switch
      192.168.1.1 kato-router
      192.168.1.2 kato-switch
      ::1 ${hostname} ${hostname}.local localhost
    '';
    bridges.cbr0.interfaces = [];
    interfaces.cbr0.ipv4.addresses = [ { address = "10.10.0.1"; prefixLength = 24; } ];
  };

  # Time and Locale (merged from system.nix)
  time.timeZone = "Asia/Tokyo";
  time.hardwareClockInLocalTime = true;
  i18n.defaultLocale = "en_US.UTF-8";

  # Nix configuration and Overlays (merged from nixpkg.nix)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;
  nixpkgs.config = {
    allowUnfree = true;
    allowBroken = false;
    allowUnfreeRedistributable = true;
    pulseaudio = true;
    chromium = { enablePepperFlash = false; enablePepperPdf = true; enableWideVine = true; };
  };
  nixpkgs.overlays = [(self: super: {
    neovim = super.neovim.override { withPython3 = true; withRuby = true; vimAlias = true; };
  })];

  # OS Level Programs (merged from programs.nix)
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;
  };
  programs.tmux.enable = true;
  programs.ssh.startAgent = true;
  programs.sway.enable = true;
  programs.light.enable = true;

  # Core System Packages (merged from environment.nix)
  environment.systemPackages = with pkgs; [
    wget curl git tailscale lshw fwupd pciutils usbutils jq
    atool bat binutils coreutils cryptsetup efibootmgr exa inetutils iputils neovim psmisc tldr xbindkeys xclip xsel rxvt_unicode git-crypt autoconf automake clang-tools ctags flameGraph gcc hub shellcheck nix-prefetch-git patchelf
  ];
  environment.variables = {
    GIT_EDITOR = lib.mkForce "hx";
    EDITOR = lib.mkForce "hx";
  };
  environment.etc."resolv.conf".source = pkgs.writeText "resolv.conf" ''
    1.1.1.1
    1.0.0.1
    8.8.8.8
    8.8.4.4
    options edns0
  '';
  environment.etc."libinput/local-overrides.quirks".text = ''
    [Touchpad touch override]
    MatchUdevType=touchpad
    MatchName=*Magic Trackpad 2
    AttrPressureRange=4:0
  '';

  # System Services (merged from services.nix & system.nix)
  services.tailscale.enable = true;
  services.fstrim.enable = true;
  services.timesyncd.enable = true;
  services.locate.enable = true;
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "no";
    extraConfig = "StreamLocalBindUnlink yes";
  };
  services.tlp.enable = if hostname == "laptop" then true else false;
  services.thinkfan.enable = if hostname == "laptop" then true else false;
  services.printing = {
    enable = true;
    drivers = with pkgs; [ gutenprint gutenprintBin hplip hplipWithPlugin cups-bjnp ];
  };

  # Custom CPU Throttling timer for Thinkpads (merged from system.nix)
  systemd.services.cpu-throttling = lib.mkIf (hostname == "laptop") {
    description = "Set CPU temp offset to 3C, new trip point 97C";
    path = [ pkgs.msr-tools ];
    script = "wrmsr -a 0x1a2 0x3000000";
    serviceConfig.Type = "oneshot";
    wantedBy = [ "timers.target" ];
  };
  systemd.timers.cpu-throttling = lib.mkIf (hostname == "laptop") {
    description = "Run cpu-throttling service on boot and periodically";
    timerConfig = {
      OnActiveSec = 60;
      OnUnitActiveSec = 60;
      Unit = "cpu-throttling.service";
    };
    wantedBy = [ "timers.target" ];
  };

  # Virtualization & Containers (merged from virtual.nix)
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

  # Security Hardening (merged from security.nix)
  security.sudo.wheelNeedsPassword = false;
  security.sudo.extraConfig = ''
    Defaults !always_set_home
    Defaults env_keep+="HOME"
  '';
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65535"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65535"; }
  ];

  # User Configuration (merged from users.nix)
  users.mutableUsers = false;
  users.users.${username} = {
    isNormalUser = true;
    uid = 1000;
    home = "/home/${username}";
    description = "${username}";
    createHome = true;
    extraGroups = [ "wheel" "networkmanager" "vboxusers" "wireshark" "mysql" "docker" "lxd" "libvirtd" "disk" "audio" "video" "input" "systemd-journal" ];
    shell = pkgs.zsh;
  };

  # Audio (Pipewire setup replacing pulseaudio/alsa from Arch config)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Fonts
  fonts.packages = with pkgs; [ hackgen-nf-font noto-fonts-color-emoji ];
  fonts.fontconfig.defaultFonts = { monospace = [ "HackGen Console NF" ]; emoji = [ "Noto Color Emoji" ]; };

  system.stateVersion = "23.11"; # Updated generic state version
}
