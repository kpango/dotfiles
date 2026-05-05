{ pkgs, lib, username, settings, versions, ... }:

# Host: tr (desk-threadripper)
# Hardware: AMD Ryzen Threadripper 3990X (64C/128T), 251 GB RAM
#           Dual Intel X710 10GbE SFP+ bonded 802.3ad (bond0)
#           NVIDIA GPU (proprietary driver)
#           NVMe RAID0 root (mdadm /dev/md0), swap on /dev/nvme1n1p1
{
  imports = [
    # ── Shared cross-host modules ─────────────────────────────────────────
    ../../core/common.nix
    ../../modules/nixos/core/security.nix
    ../../modules/nixos/core/programs.nix
    ../../modules/nixos/network/ssh.nix
    ../../modules/nixos/hardware/time.nix
    ../../modules/nixos/desktop/audio.nix
    ../../modules/nixos/desktop/fonts.nix
    ../../modules/nixos/desktop/input.nix
    ../../modules/nixos/desktop/wayland.nix

    # ── Threadripper-specific modules ─────────────────────────────────────
    ./hardware/default.nix
    ./hardware/nvidia.nix
    ./networking/default.nix
    ./networking/x710-tuning.nix
    ./system/performance.nix
    ./system/storage.nix
    ./virtualization/docker.nix
  ];

  networking.hostName = "desk-threadripper";

  time.timeZone = settings.timeZone;
  time.hardwareClockInLocalTime = settings.nix.hardwareClockInLocalTime;

  i18n = {
    defaultLocale = settings.locale;
    supportedLocales = [ "en_US.UTF-8/UTF-8" "ja_JP.UTF-8/UTF-8" ];
  };

  # High-parallelism nix settings for 64-core Threadripper.
  # nix.gc.automatic and options come from core/common.nix; dates is NixOS-only.
  nix.gc.dates = "weekly";
  nix.settings = {
    cores = 128;
    max-jobs = lib.mkDefault 64;
  };

  # Disable password login; account shape comes from modules/nixos/core/security.nix
  users.users.${username}.hashedPassword = "!";

  services.xserver = {
    enable = true;
    xkb.layout = settings.desktop.keyboard.layout;
    xkb.options = settings.desktop.keyboard.options;
  };
  services.displayManager.defaultSession = "sway";

  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.tuigreet}/bin/tuigreet --cmd sway";
      user = "greeter";
    };
  };

  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      nerd-fonts.hack
      noto-fonts
    ];
  };

  boot.kernelModules = lib.mkAfter [
    "vfio"
    "vfio_pci"
  ];

  boot.kernelParams = lib.mkAfter [
    "rcu_nocbs=1-127"
    "rcu_nocb_poll"
  ];

  services.smartd = {
    enable = true;
    autodetect = true;
  };

  system.stateVersion = versions.nixos;
}
