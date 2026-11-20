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

  systemd.services.nvidia-cdi-generate = {
    description = "Regenerate NVIDIA CDI spec for container runtime";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-udev-settle.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "nvidia-cdi-generate" ''
        mkdir -p /etc/cdi
        ${pkgs.nvidia-container-toolkit}/bin/nvidia-ctk cdi generate \
          --output=/etc/cdi/nvidia.yaml
      '';
    };
  };

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
  ];
}
