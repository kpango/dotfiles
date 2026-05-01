{ pkgs, ... }:

{
  # IOMMU for VT-d / VFIO passthrough
  boot.kernelParams = [
    "intel_iommu=on"
  ];

  # Intel CPU microcode updates
  hardware.cpu.intel.updateMicrocode = true;

  # Intel media acceleration (VA-API / VDPAU)
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    vaapiVdpau
    libvdpau-va-gl
  ];

  # Intel thermal management daemon
  services.thermald.enable = true;
}
