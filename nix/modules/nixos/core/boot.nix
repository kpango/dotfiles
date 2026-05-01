{ config, pkgs, settings, ... }:

{
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
  boot.kernelModules = [ "tcp_bbr" "nf_conntrack" "acpi_call" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.acpi_call ];
  boot.kernelParams = settings.system.kernel.params;
  boot.blacklistedKernelModules = settings.system.kernel.blacklistedModules;

  # High-performance Sysctls
  boot.kernel.sysctl = settings.system.kernel.sysctl;

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
      device = "/dev/disk/by-label/${settings.system.disks.rootLabel}";
      fsType = "xfs";
      options = settings.system.disks.rootOptions;
    };
    "/boot" = {
      device = "/dev/disk/by-label/${settings.system.disks.bootLabel}";
      fsType = "vfat";
      options = settings.system.disks.bootOptions;
    };
  };
}