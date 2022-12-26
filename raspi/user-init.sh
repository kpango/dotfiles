#!/bin/sh
git clone --depth 1 https://aur.archlinux.org/paru.git
cd paru
makepkg -si
cd -
rm -r paru

curl https://raw.githubusercontent.com/kpango/dotfiles/main/raspi/aur.list -o /aur.list
pacman -Rs go
paru -Syu --noanswerdiff --noanswerclean --noconfirm
paru -S --noanswerdiff --noanswerclean --noconfirm ghq
paru -S --noanswerdiff --noanswerclean --noconfirm gopreload-git
paru -S --noanswerdiff --noanswerclean --noconfirm kubeadm-bin
paru -S --noanswerdiff --noanswerclean --noconfirm kubectl
paru -S --noanswerdiff --noanswerclean --noconfirm kubectx
paru -S --noanswerdiff --noanswerclean --noconfirm procs
paru -S --noanswerdiff --noanswerclean --noconfirm systemd-boot-pacman-hook
paru -S --noanswerdiff --noanswerclean --noconfirm tzupdate
paru -S --noanswerdiff --noanswerclean --noconfirm paru
