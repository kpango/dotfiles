{ pkgs, lib, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = true;
  };

  # Docker GPU support
  hardware.nvidia-container-toolkit.enable = true;

  # QEMU VMs have no NVIDIA hardware; qemu-vm.nix replaces videoDrivers with
  # virtio, which breaks the nvidia-container-toolkit driver assertion.
  virtualisation.vmVariant = {
    hardware.nvidia-container-toolkit.enable = lib.mkForce false;
  };

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
  ];
}
