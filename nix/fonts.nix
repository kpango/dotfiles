{ config, pkgs, ... }:
{
  fonts = {
    fontconfig.enable = true;
    enableCoreFonts = true;
    enableFontDir = true;
    enableGhostscriptFonts = true;
    fonts = with pkgs; [
      ricty
      # corefonts
      # font-awesome-ttf
      # input-fonts
      # noto-fonts-cjk
    ];
  };
}
