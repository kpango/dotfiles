{ pkgs, settings, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = settings.desktop.imModule;
    fcitx5.addons = with pkgs; [
      fcitx5-mozc
      fcitx5-gtk
    ];
  };
}
