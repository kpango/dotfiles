{ settings, ... }:

{
  services.fstrim.enable = settings.hardware.maintenance.fstrim;
  services.locate.enable = settings.hardware.maintenance.locate;
}