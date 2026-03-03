{ config, pkgs, lib, username, hostname, ... }:

{
  # Bootloader setup (based on Arch chroot.sh bootctl setup)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Kernel configuration
  boot.kernelPackages = pkgs.linuxPackages_zen;
  boot.kernelParams = [ "quiet" "nowatchdog" "acpi.ec_no_wakeup=1" "intel_iommu=on" ];
  boot.blacklistedKernelModules = [ "pcspkr" "intel_pmc_bxt" "iTCO_vendor_support" "iTCO_wdt" ];

  # Networking
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  # Time and Locale (Asia/Tokyo and en_US.UTF-8 as per Arch chroot.sh)
  time.timeZone = "Asia/Tokyo";
  i18n.defaultLocale = "en_US.UTF-8";

  # Nix features
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Zsh at OS level for paths
  programs.zsh.enable = true;

  # Core system tools
  environment.systemPackages = with pkgs; [
    wget
    curl
    git
    tailscale
    lshw
    fwupd
    pciutils
    usbutils
    jq
  ];

  # System Services
  services.tailscale.enable = true;
  services.fstrim.enable = true;
  services.chrony.enable = true;

  # Docker
  virtualisation.docker.enable = true;

  # Laptop Specifics (TLP, Thinkfan, etc. for the 'laptop' host)
  services.tlp.enable = if hostname == "laptop" then true else false;
  services.thinkfan.enable = if hostname == "laptop" then true else false;

  # User Configuration
  users.users.${username} = {
    isNormalUser = true;
    home = "/home/${username}";
    description = "${username}";
    extraGroups = [ "wheel" "networkmanager" "docker" "audio" "video" "input" ];
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

  # Fonts (HackGen NF and Noto Color Emoji)
  fonts.packages = with pkgs; [
    hackgen-nf-font
    noto-fonts-color-emoji
  ];

  # Fonts configs
  fonts.fontconfig.defaultFonts = {
    monospace = [ "HackGen Console NF" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # Wayland / Sway OS-level requirement (Sway configuration is in home-manager)
  programs.sway.enable = true;

  system.stateVersion = "23.11"; # Did not change from standard NixOS
}
