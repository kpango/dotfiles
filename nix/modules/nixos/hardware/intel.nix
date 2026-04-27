{ pkgs, ... }:

{
  boot.kernelParams = [
    "intel_iommu=on"
  ];

  hardware.opengl = {
    extraPackages = with pkgs; [
      intel-media-driver
      vaapiIntel
      vaapiVdpau
      libvdpau-va-gl
    ];
  };
}