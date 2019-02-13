{ config, pkgs, ... }:
{
  # Use the systemd-boot EFI boot loader.
  boot = {
    blacklistedKernelModules = [ "snd_pcsp" "pcspkr" ];
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = ["psmouse.synaptics_intertouch=0"];
    plymouth.enable = true;
    # supportedFilesystems = [ "xfs" "zfs" ];
    supportedFilesystems = [ "xfs" ];
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
        # zfsSupport = true;
      };
    };
    initrd = {
      kernelModules = [
        "kvm_intel"
        "tp_smapi"
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
}
