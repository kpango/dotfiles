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
    slack-desktop-dark \
    systemd-boot-pacman-hook \
    ttf-symbola \
    urxvt-resize-font-git
# lib32-nvidia-utils \
# wlroots-git \
# sway-git \
# waybar-git \
HACKGEN_VERSION="1.2.1"
axel "https://github.com/yuru7/HackGen/releases/download/v${HACKGEN_VERSION}/HackGen_v${HACKGEN_VERSION}.zip"
unzip HackGen_v${HACKGEN_VERSION}.zip
sudo mv HackGen_v${HACKGEN_VERSION}/* /usr/share/fonts/TTF/

fc-cache -f -v
