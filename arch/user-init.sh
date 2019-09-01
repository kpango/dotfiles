#!/bin/sh

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd -
rm -r yay

pacman -Rs go
yay -Syyua --noconfirm
yay -Syu --noconfirm \
    chrome-remote-desktop \
    ghq \
    kazam \
    lib32-nvidia-utils \
    lightdm-webkit-theme-aether \
    nerd-fonts-ricty \
    slack-desktop \
    systemd-boot-pacman-hook \
    ttf-ricty \
    ttf-symbola \
    urxvt-resize-font-git \
    xkeysnail
# wlroots-git \
# sway-git \
# waybar-git \

fc-cache -f -v

mkdir -p /go/src/github.com/kpango/
cd /go/src/github.com/kpango/ && git clone https://github.com/kpango/doftiles && cd -
cd /go/src/github.com/kpango/dotfiles && USER=${LOGIN_USER} make arch_link && cd -
