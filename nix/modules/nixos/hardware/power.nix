{ config, lib, settings, ... }:

{
  # TLP battery charge thresholds and runtime PM settings.
  # Applied only when TLP is enabled (via intel-laptop or thinkpad-laptop profiles).
  services.tlp.settings = lib.mkIf config.services.tlp.enable {
    START_CHARGE_THRESH_BAT0    = settings.hardware.battery.startCharge;
    STOP_CHARGE_THRESH_BAT0     = settings.hardware.battery.stopCharge;
    RUNTIME_PM_DRIVER_BLACKLIST = settings.hardware.tlp.runtimePmDriverBlacklist;
    RESTORE_THRESHOLDS_ON_BAT   = settings.hardware.tlp.restoreThresholdsOnBat;
    WOL_DISABLE                 = settings.hardware.tlp.wolDisable;
  };

  # Thinkfan fan-control sensor/level config.
  # Applied only when thinkfan is enabled (via thinkpad-laptop profile).
  services.thinkfan.sensors = lib.mkIf config.services.thinkfan.enable
    settings.hardware.thinkfan.sensors;
  services.thinkfan.levels  = lib.mkIf config.services.thinkfan.enable
    settings.hardware.thinkfan.levels;

  # fanctl YAML config (GPU+CPU fan controller used on the Threadripper desktop).
  # Deployed only when TLP is active (i.e. on laptops/ThinkPads where TLP runs).
  environment.etc."fanctl.yml" = lib.mkIf config.services.tlp.enable {
    source = ../../../../arch/fanctl.yml;
  };
}
