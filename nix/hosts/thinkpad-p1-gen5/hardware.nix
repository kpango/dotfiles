{ ... }:

{
  imports = [
    ../../modules/nixos/hardware/profiles/thinkpad-laptop.nix
    ../../modules/nixos/hardware/profiles/nvidia-workstation.nix
  ];

  # ThinkPad P1 Specific Kernel Params
  boot.kernelParams = [
    "acpi_osi=!"
    "acpi_osi=\"Windows 2013\""
    "acpi.ec_no_wakeup=1"
    "acpi_backlight=native"
    "video.use_native_backlight=1"
    "iommu=force,merge,nopanic,nopt"
    "mitigations=off"
    "swiotlb=noforce"
    "sysrq_always_enabled=1"
    "nvidia-drm.modeset=1"
    "mem_sleep_default=deep"
    "intel_pstate=active"
    # P1 has 16–64 GB RAM; limit zswap pool to 25 % to avoid excessive RAM use
    "zswap.max_pool_percent=25"
  ];

  # Intel Wi-Fi performance tweaks
  boot.extraModprobeConfig = ''
    options iwlwifi 11n_disable=1 swcrypto=0 bt_coex_active=0 power_save=0 uapsd_disable=1 d0i3_disable=1 lar_disable=1
    options iwlmvm power_scheme=1 bt_coex_active=0
  '';

  hardware.nvidia = {
    prime = {
      offload.enable = true;
      # REQUIRED: Set these to the actual PCI Bus IDs from your machine.
      # Run: sudo lshw -c display  (look for "bus info: pci@0000:XX:YY.Z")
      # Intel is typically "PCI:0:2:0", NVIDIA varies (check with `lspci | grep -i vga`)
      # Until these are set, NVIDIA offload will NOT work and may cause boot issues.
      # intelBusId  = "PCI:0:2:0";
      # nvidiaBusId = "PCI:1:0:0";
    };
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = true; # Open DKMS module
  };
}