{ pkgs, settings, ... }:

{
  services.printing = {
    enable = settings.desktop.printing.enable;
    drivers = with pkgs; [
      cups-bjnp
      gutenprint
      gutenprintBin
      hplip
      hplipWithPlugin
    ];
  };
}
