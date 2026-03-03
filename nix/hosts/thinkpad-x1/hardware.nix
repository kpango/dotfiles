{ config, lib, pkgs, ... }:

{
  # Intel X1 Gen 6 optimizations
  boot.kernelModules = [ "kvm-intel" "acpi_call" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ acpi_call ];

  # Graphics & Intel iGPU Configuration
  hardware.opengl = {
    enable = true;
    driSupport = true;
    driSupport32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver # iHD driver
      vaapiIntel         # legacy i965
      vaapiVdpau
      libvdpau-va-gl
    ];
  };

  # Power Management and Thinkpad Features
  services.tlp.enable = true;
  services.thinkfan.enable = true;

  # Custom CPU Throttling timer for ThinkPad X1 Carbon Gen 6 (from legacy system.nix)
  systemd.services.cpu-throttling = {
    description = "Set CPU temp offset to 3C, new trip point 97C";
    path = [ pkgs.msr-tools ];
    script = "wrmsr -a 0x1a2 0x3000000";
    serviceConfig.Type = "oneshot";
    wantedBy = [ "timers.target" ];
  };
  systemd.timers.cpu-throttling = {
    description = "Run cpu-throttling service on boot and periodically";
    timerConfig = {
      OnActiveSec = 60;
      OnUnitActiveSec = 60;
      Unit = "cpu-throttling.service";
    };
    wantedBy = [ "timers.target" ];
  };

  environment.systemPackages = with pkgs; [ acpi ];
}
