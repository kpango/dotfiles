#!/bin/sh
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd -
rm -r yay

curl https://raw.githubusercontent.com/kpango/dotfiles/master/raspi/aur.list -o /aur.list
pacman -Rs go
yay -Syu
yay -S ghq
yay -S gopreload-git
yay -S kubeadm-bin
yay -S kubectl
yay -S kubectx
yay -S procs
yay -S reflector
yay -S systemd-boot-pacman-hook
yay -S tzupdate
yay -S yay
