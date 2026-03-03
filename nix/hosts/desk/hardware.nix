{ config, lib, pkgs, ... }:

{
  # High-performance desktop optimizations
  boot.kernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" ];

  # Graphics & NVIDIA Configuration for Desktop
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    open = true; # Open source module if applicable (based on pkg_p1.list references)
    nvidiaSettings = true;
  };

  # Extra desktop packages (cuda, vulkan, etc from pkg_desk.list)
  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    vulkan-tools
    vulkan-loader
    vulkan-validation-layers
  ];

  # Docker GPU support
  hardware.nvidia-container-toolkit.enable = true;
}
