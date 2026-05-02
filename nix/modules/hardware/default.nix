{ config, pkgs, lib, ... }:

{
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

  # Blacklist nouveau; it is also blocked via rd.driver.blacklist above
  boot.blacklistedKernelModules = [
    "nouveau"
    "pcspkr"
  ];

  # Extra modprobe options for NVIDIA
  boot.extraModprobeConfig = ''
    options nvidia NVreg_UsePageAttributeTable=1 NVreg_InitializeSystemMemoryAllocations=0 NVreg_EnableStreamMemOPs=1
    options nvidia_drm modeset=1
    blacklist nouveau
    options nouveau modeset=0
  '';

  # mdadm: enable swraid in initrd; mdadmConf and resumeDevice set in storage.nix
  boot.initrd.services.swraid.enable = true;

  # Supported filesystems
  boot.supportedFilesystems = [ "xfs" "vfat" "ext4" ];

  # tmpfs for /tmp
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
  # I/O scheduler udev rules
  # NVMe → none (noop), rotational SSD → mq-deadline
  # NVMe read_ahead_kb → 0
  # ────────────────────────────────────────────────
  services.udev.extraRules = lib.mkAfter ''
    # NVMe devices: no scheduler (hardware handles queuing), zero read-ahead
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="none"
    ACTION=="add|change", KERNEL=="nvme[0-9]*n[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/read_ahead_kb}="0"

    # SATA/SCSI SSD: mq-deadline
    ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"

    # Rotational HDD: bfq
    ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"

    # Persistent interface names
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="f0:2f:74:d4:37:35", NAME="eth0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="64:9d:99:b1:03:44", NAME="sfp0"
    SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="64:9d:99:b1:03:45", NAME="sfp1"

    # Input devices
    KERNEL=="event*", NAME="input/%k", MODE="0660", GROUP="input"
    KERNEL=="uinput", GROUP="uinput", MODE="0660"
  '';
}
