{ config, pkgs, ... }:
{
  fonts = {
    fontconfig.enable = true;
    enableCoreFonts = true;
    enableFontDir = true;
    enableGhostscriptFonts = true;
    fonts = with pkgs; [
      ricty
    ];
  };
}
