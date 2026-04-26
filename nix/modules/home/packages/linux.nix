{ pkgs, lib, isLinux, ... }:

{
  home.packages = lib.mkIf isLinux (with pkgs; [
    alacritty alsa-utils discord docker-buildx ethtool fcitx5-mozc fwupd grim helvum kanshi light lshw mako mdadm noto-fonts-emoji nvme-cli parted pavucontrol slack slurp sway swaybg swayidle sysbench sysfsutils ventoy waybar wdisplays wl-clipboard wofi xfce.thunar zoom-us
  ]);
}