{ config, lib, settings, ... }:

{
  services.tlp = {
    settings = {
      START_CHARGE_THRESH_BAT0 = settings.hardware.battery.startCharge;
      STOP_CHARGE_THRESH_BAT0 = settings.hardware.battery.stopCharge;
      RUNTIME_PM_DRIVER_BLACKLIST = settings.hardware.tlp.runtimePmDriverBlacklist;
      RESTORE_THRESHOLDS_ON_BAT = settings.hardware.tlp.restoreThresholdsOnBat;
      WOL_DISABLE = settings.hardware.tlp.wolDisable;
    };
  };

  services.thinkfan = {
    sensors = settings.hardware.thinkfan.sensors;
    levels = settings.hardware.thinkfan.levels;
  };

  environment.etc."fanctl.yml" = lib.mkIf config.services.tlp.enable {
    source = ../../../../arch/fanctl.yml;
  };
}