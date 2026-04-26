{ pkgs, settings, ... }:

{
  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [
      settings.fonts.monospace
    ];
    emoji = [
      settings.fonts.emoji
    ];
  };
}