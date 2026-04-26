{ pkgs, ... }:

{
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    nvidiaSettings = true;
  };

  # Docker GPU support
  hardware.nvidia-container-toolkit.enable = true;

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
  ];
}
