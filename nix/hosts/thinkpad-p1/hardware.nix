{ config, lib, pkgs, ... }:

{
  # ThinkPad specific kernels/tools
  boot.kernelModules = [ "kvm-intel" "acpi_call" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call ];

  # TLP & Thinkfan for Laptops
  services.tlp.enable = true;
  services.thinkfan.enable = true;

  # NVIDIA Optimus / Prime Configuration for P1
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    # Prime / Offload config replacing Bumblebee from arch config
    prime = {
      offload.enable = true;
      # Note: These Bus IDs must be replaced with the exact ones from `lshw -c display`
      # intelBusId = "PCI:0:2:0";
      # nvidiaBusId = "PCI:1:0:0";
    };
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = true; # Open DKMS module specified in pkg_p1.list
    nvidiaSettings = true;
  };

  # Docker GPU support
  hardware.nvidia-container-toolkit.enable = true;

  # Additional Thinkpad packages
  environment.systemPackages = with pkgs; [
    acpi
    cudaPackages.cudatoolkit
  ];
}
