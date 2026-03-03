{ config, pkgs, lib, username, hostname, ... }:

{
  # Bootloader setup (based on Arch chroot.sh bootctl setup & legacy boot.nix)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel configuration (bringing in custom modules/params from legacy boot.nix)
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelModules = [ "kvm-intel" "xhci_pci" "nvme" ];
  boot.kernelParams = [
    "quiet" "nowatchdog" "acpi.ec_no_wakeup=1" "intel_iommu=on"
    "intel_pstate=no_hwp"
    "psmouse.proto=imps"
    "psmouse.synaptics_intertouch=1"
  ];
  boot.blacklistedKernelModules = [ "pcspkr" "intel_pmc_bxt" "iTCO_vendor_support" "iTCO_wdt" "snd_pcsp" ];

  # High-performance Sysctls (ported from legacy boot.nix)
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

  # Temp filesystem setup (legacy boot.nix)
  boot.tmp.useTmpfs = true;
  boot.tmp.cleanOnBoot = true;

  # Networking (from legacy network.nix and Arch configs)
  networking.hostName = hostname;
  networking.networkmanager.enable = true;
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 80 443 3000 8080 ];

  # Time and Locale
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";

  # Nix features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.auto-optimise-store = true;

  # Zsh at OS level for paths
  programs.zsh.enable = true;

  # Core system tools (from legacy environment.nix and new needs)
  environment.systemPackages = with pkgs; [
    wget curl git tailscale lshw fwupd pciutils usbutils jq
    bat exa ripgrep fd htop bind inetutils
  ];

  # System Services
  services.tailscale.enable = true;
  services.fstrim.enable = true;
  services.chrony.enable = true;

  # Virtualization & Containers (legacy virtual.nix)
  virtualisation = {
    docker = {
      enable = true;
      enableOnBoot = true;
      liveRestore = true;
      autoPrune.enable = true;
      storageDriver = "overlay2";
    };
    lxd.enable = true;
    libvirtd.enable = true;
  };

  # Laptop Specifics (TLP, Thinkfan, custom throttling fix from legacy system.nix)
  services.tlp.enable = if hostname == "laptop" then true else false;
  services.thinkfan.enable = if hostname == "laptop" then true else false;

  # Custom CPU Throttling timer for Thinkpads (from legacy system.nix)
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

  # Security Hardening (from legacy security.nix)
  security.sudo.wheelNeedsPassword = false;
  security.sudo.extraConfig = ''
    Defaults !always_set_home
    Defaults env_keep+="HOME"
  '';
  security.pam.loginLimits = [
    { domain = "*"; type = "soft"; item = "nofile"; value = "65535"; }
    { domain = "*"; type = "hard"; item = "nofile"; value = "65535"; }
  ];

  # User Configuration
  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    description = "${username}";
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" "video" "input" "libvirtd" "lxd" ];
    shell = pkgs.zsh;
  };

  # Polkit required for some Wayland WMs (like Sway)
  security.polkit.enable = true;

  # Graphics / OpenGL
  hardware.opengl.enable = true;

  # Audio (Pipewire setup replacing pulseaudio/alsa from Arch config)
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Fonts
  fonts.packages = with pkgs; [
    hackgen-nf-font
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [ "HackGen Console NF" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # Wayland / Sway OS-level requirement
  programs.sway.enable = true;

  system.stateVersion = "23.11";
}
