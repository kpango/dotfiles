{ config, pkgs, lib, settings, ... }:

let
  hasNvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
in
lib.mkIf hasNvidia {
  boot.kernelModules = [ "nvidia_uvm" ];
  boot.extraModprobeConfig = settings.system.kernel.extraModprobeConfig;

  # Unload NVIDIA kernel modules cleanly before reboot/halt/poweroff.
  # Prevents GPU memory corruption and stale DRM state across reboots.
  systemd.services.nvidia-unload = {
    description = "Unload NVIDIA kernel modules before shutdown";
    defaultDependencies = false;
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
}
