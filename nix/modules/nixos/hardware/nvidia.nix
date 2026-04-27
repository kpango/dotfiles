{ config, pkgs, lib, settings, ... }:

let
  hasNvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
in
lib.mkIf hasNvidia {
  boot.kernelModules = [ "nvidia_uvm" ];
  boot.extraModprobeConfig = settings.system.kernel.extraModprobeConfig;

  systemd.services.nvidia-disable-resume = {
    description = "Disable NVIDIA card at system resume";
    after = [ "sleep.target" "suspend.target" "suspend-then-hibernate.target" "hibernate.target" ];
    wantedBy = [ "sleep.target" "suspend.target" "suspend-then-hibernate.target" "hibernate.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/sh -c 'cat ${settings.hardware.gpuStatePath} > /proc/acpi/bbswitch || echo OFF > /proc/acpi/bbswitch'";
    };
  };

  systemd.services.nvidia-enable-power-off = {
    description = "Enable NVIDIA card at shutdown";
    wantedBy = [ "shutdown.target" "reboot.target" "hibernate.target" "suspend-then-hibernate.target" "sleep.target" "suspend.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/sh -c \"awk '{print \\$2}' /proc/acpi/bbswitch > ${settings.hardware.gpuStatePath} && echo ON > /proc/acpi/bbswitch\"";
    };
  };
}