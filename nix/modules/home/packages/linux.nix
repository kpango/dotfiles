{ pkgs, lib, isLinux, ... }:

{
  home.packages = lib.mkIf isLinux (with pkgs; [
    alacritty
    alsa-utils
    brightnessctl
    discord
    ghostty
    crosspipe
    pavucontrol
    slack
    sysbench
    workstyle
    thunar
    zoom-us
  ]);
}
