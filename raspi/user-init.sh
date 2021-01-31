#!/bin/sh
git clone --depth 1 https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd -
rm -r yay

curl https://raw.githubusercontent.com/kpango/dotfiles/master/raspi/aur.list -o /aur.list
pacman -Rs go
yay -Syu --noanswerdiff --noanswerclean --noconfirm
yay -S --noanswerdiff --noanswerclean --noconfirm ghq
yay -S --noanswerdiff --noanswerclean --noconfirm gopreload-git
yay -S --noanswerdiff --noanswerclean --noconfirm kubeadm-bin
yay -S --noanswerdiff --noanswerclean --noconfirm kubectl
yay -S --noanswerdiff --noanswerclean --noconfirm kubectx
yay -S --noanswerdiff --noanswerclean --noconfirm procs
yay -S --noanswerdiff --noanswerclean --noconfirm reflector
yay -S --noanswerdiff --noanswerclean --noconfirm systemd-boot-pacman-hook
yay -S --noanswerdiff --noanswerclean --noconfirm tzupdate
yay -S --noanswerdiff --noanswerclean --noconfirm yay
