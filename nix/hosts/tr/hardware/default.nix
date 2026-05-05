{ config, pkgs, lib, settings, ... }:

{
  imports = [ ../../../modules/nixos/hardware/udev-ioscheduler.nix ];

  # ────────────────────────────────────────────────
  # Boot loader
  # ────────────────────────────────────────────────
  boot.loader = {
    systemd-boot = {
      enable = true;
      consoleMode = "auto";
      editor = false;
    };
    efi = {
      canTouchEfiVariables = true;
      efiSysMountPoint = "/boot";
    };
    timeout = 3;
  };

  # ────────────────────────────────────────────────
  # Kernel
  # ────────────────────────────────────────────────
  boot.kernelPackages = pkgs.linuxPackages_zen;

  # Modules needed in initrd for mdadm RAID0 on NVMe
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "md_mod"
    "raid0"
  ];
  boot.initrd.kernelModules = [
    "nvme"
    "raid0"
  ];

  # Modules loaded post-initrd
  boot.kernelModules = [
    "kvm-amd"
    "tcp_bbr"
    "nvidia"
    "nvidia_modeset"
    "nvidia_uvm"
    "nvidia_drm"
    "i40e"
    "bonding"
  ];

  # Kernel parameters matching the live Arch boot entry
  boot.kernelParams = [
    "amd_iommu=on"
    "iommu=pt"
    "amd_pstate=disable"
    "cgroup_no_v1=all"
    "nvidia_drm.fbdev=1"
    "nvidia_drm.modeset=1"
    "usbcore.autosuspend=-1"
    "vt.global_cursor_default=0"
    "zswap.compressor=zstd"
    "zswap.enabled=1"
    "zswap.max_pool_percent=10"
    "zswap.zpool=zsmalloc"
    "nvme_core.default_ps_max_latency_us=0"
    "rd.driver.blacklist=nouveau"
    "processor.max_cstate=1"
    "nowatchdog"
    "quiet"
    "loglevel=1"
    "reboot=efi"
    "acpi_backlight=none"
  ];

  # nouveau blocked via rd.driver.blacklist kernel param
  boot.blacklistedKernelModules = [ "pcspkr" ];

  boot.supportedFilesystems = [ "xfs" "vfat" "ext4" ];

  boot.tmp = {
    useTmpfs = true;
    tmpfsSize = "32G";
    cleanOnBoot = true;
  };

  # ────────────────────────────────────────────────
  # AMD CPU microcode
  # ────────────────────────────────────────────────
  hardware.cpu.amd.updateMicrocode = true;

  # ────────────────────────────────────────────────
  # Persistent interface names via udev
  # ────────────────────────────────────────────────
  services.udev.extraRules = lib.mkAfter ''
    # Persistent interface names
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.eth0}", NAME="eth0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.sfp0}", NAME="sfp0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="${settings.network.interfaces.sfp1}", NAME="sfp1"

    # Input devices
    KERNEL=="event*", NAME="input/%k", MODE="0660", GROUP="input"
    KERNEL=="uinput", GROUP="uinput", MODE="0660"
  '';

  # ────────────────────────────────────────────────
  # Hardware-diagnostic packages
  # ────────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
    acpi
    dmidecode
    dosfstools
    efibootmgr
    ethtool
    fakeroot
    fwupd
    lm_sensors
    lshw
    mdadm
    nvme-cli
    parted
    patchelf
    pciutils
    powertop
    smartmontools
    sysfsutils
    usbutils
    xfsprogs
  ];
}
