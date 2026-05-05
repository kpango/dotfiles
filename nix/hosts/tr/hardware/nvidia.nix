{ config, pkgs, lib, settings, ... }:

{
  # ────────────────────────────────────────────────
  # NVIDIA proprietary driver — desktop Threadripper
  # No Prime offload, no power management (always on)
  # ────────────────────────────────────────────────

  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    powerManagement.enable = false;
    powerManagement.finegrained = false;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
  };

  hardware.nvidia-container-toolkit.enable = true;

  virtualisation.vmVariant = {
    hardware.nvidia-container-toolkit.enable = lib.mkForce false;
  };

  systemd.services.nvidia-unload = {
    description = "Unload NVIDIA kernel modules before shutdown";
    unitConfig.DefaultDependencies = false;
    before = [ "reboot.target" "halt.target" "poweroff.target" ];
    after = [ "graphical.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = pkgs.writeShellScript "nvidia-unload" ''
        modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia 2>/dev/null || true
      '';
    };
  };

  boot.blacklistedKernelModules = lib.mkAfter [ "nouveau" ];

  # nvidia_drm.modeset=1 also set via kernelParams; kept here for completeness
  boot.extraModprobeConfig = settings.system.kernel.extraModprobeConfig + ''
    blacklist nouveau
    options nouveau modeset=0
  '';

  environment.systemPackages = with pkgs; [
    cudaPackages.cudatoolkit
    nvtopPackages.nvidia
  ];

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      egl-wayland
      libvdpau-va-gl
    ];
  };
}
