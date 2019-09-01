#!/bin/sh

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd -
rm -r yay

pacman -Rs go
yay -Syyua
yay -Syu \
    chrome-remote-desktop \
    ghq \
    kazam \
    lightdm-webkit-theme-aether \
    nerd-fonts-ricty \
    slack-desktop \
    systemd-boot-pacman-hook \
    ttf-symbola \
    urxvt-resize-font-git \
    xkeysnail
# lib32-nvidia-utils \
# wlroots-git \
# sway-git \
# waybar-git \

fc-cache -f -v
