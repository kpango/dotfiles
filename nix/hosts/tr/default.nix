{ pkgs, lib, ... }:

# ──────────────────────────────────────────────────────────────────────────────
# Host: tr (desk-threadripper)
# Hardware: AMD Ryzen Threadripper 3990X (64C/128T), 251 GB RAM
#           Dual Intel X710 10GbE SFP+ bonded 802.3ad (bond0)
#           NVIDIA GPU (proprietary driver)
#           NVMe RAID0 root (mdadm /dev/md0), swap on /dev/nvme1n1p1
# OS target: NixOS on Arch Linux migration
# ──────────────────────────────────────────────────────────────────────────────
{
  imports = [
    ../../modules/hardware/default.nix    # boot, kernel, udev, microcode
    ../../modules/hardware/nvidia.nix     # NVIDIA proprietary driver
    ../../modules/networking/default.nix  # bond0, sysctl, firewall
    ../../modules/networking/x710-tuning.nix  # X710 post-up tuning services
    ../../modules/system/performance.nix  # CPU governor, KSM, THP, journald
    ../../modules/system/storage.nix      # mdadm, filesystems, swap
    ../../modules/virtualization/docker.nix  # Docker daemon + NVIDIA runtime
    ../../modules/programs/default.nix    # shell, editor, packages
  ];

  # ────────────────────────────────────────────────
  # Identity
  # ────────────────────────────────────────────────
  networking.hostName = "desk-threadripper";

  # ────────────────────────────────────────────────
  # Locale & Time
  # ────────────────────────────────────────────────
  time.timeZone = "Asia/Tokyo";
  time.hardwareClockInLocalTime = true;

  i18n = {
    defaultLocale    = "en_US.UTF-8";
    supportedLocales = [ "en_US.UTF-8/UTF-8" "ja_JP.UTF-8/UTF-8" ];
  };

  # ────────────────────────────────────────────────
  # Nixpkgs
  # ────────────────────────────────────────────────
  nixpkgs.config = {
    allowUnfree   = true;   # NVIDIA, CUDA, etc.
    allowBroken   = false;
  };

  # ────────────────────────────────────────────────
  # Nix daemon settings
  # ────────────────────────────────────────────────
  nix = {
    settings = {
      # Use all 128 threads for builds
      cores             = 128;
      max-jobs          = lib.mkDefault 64;
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users     = [ "root" "kpango" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 14d";
    };
  };

  # ────────────────────────────────────────────────
  # Users
  # ────────────────────────────────────────────────
  users.mutableUsers = false;

  users.users.kpango = {
    isNormalUser = true;
    uid          = 1000;
    home         = "/home/kpango";
    createHome   = true;
    shell        = pkgs.zsh;
    extraGroups  = [
      "audio"
      "disk"
      "docker"
      "input"
      "libvirtd"
      "networkmanager"
      "power"
      "systemd-journal"
      "uinput"
      "video"
      "wheel"
      "wireshark"
    ];
    # Set via nixos-install --option with hashedPassword; placeholder below.
    # Generate with: mkpasswd -m sha-512
    hashedPassword = "!";  # Locked — use SSH keys or set at install time.
    # Place your SSH public key(s) in a file and reference it here, e.g.:
    #   openssh.authorizedKeys.keyFiles = [ "/etc/nixos/authorized_keys" ];
    # Or list keys directly:
    #   openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA... kpango@..." ];
    openssh.authorizedKeys.keys = [];
  };

  # ────────────────────────────────────────────────
  # Desktop environment (Wayland/Sway)
  # ────────────────────────────────────────────────
  services.xserver = {
    enable  = true;
    xkb.layout  = "us";
    xkb.options = "ctrl:nocaps";
    displayManager.defaultSession = "sway";
  };

  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --cmd sway";
        user    = "greeter";
      };
    };
  };

  # ────────────────────────────────────────────────
  # Fonts
  # ────────────────────────────────────────────────
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      nerd-fonts.hack
      noto-fonts
      noto-fonts-emoji
    ];
    fontconfig.defaultFonts = {
      monospace = [ "HackGen Console NF" "Noto Color Emoji" ];
      emoji     = [ "Noto Color Emoji" ];
    };
  };

  # ────────────────────────────────────────────────
  # Host-specific kernel overrides
  # Override common defaults to match live Arch system
  # ────────────────────────────────────────────────
  boot.kernelModules = lib.mkAfter [
    "kvm-amd"
    "vfio"
    "vfio_pci"
    "vfio_virqfd"
  ];

  # ────────────────────────────────────────────────
  # SMART / disk monitoring
  # ────────────────────────────────────────────────
  services.smartd = {
    enable = true;
    autodetect = true;
  };

  # ────────────────────────────────────────────────
  # Profile sync daemon (browser profiles → tmpfs)
  # ────────────────────────────────────────────────
  # services.psd.enable = true;  # Not in nixpkgs mainline; use AUR equivalent

  # ────────────────────────────────────────────────
  # NixOS state version
  # Set to the NixOS release this config was written against.
  # Do NOT change after first install.
  # ────────────────────────────────────────────────
  system.stateVersion = "24.11";
}
