#!/bin/sh
sudo pacman -Syu
sudo chmod -R 777 /tmp
git clone --depth 1 https://aur.archlinux.org/paru.git
cd paru
makepkg -si
cd -
rm -r paru

family_name=$(cat /sys/devices/virtual/dmi/id/product_family)
echo $family_name
if [[ $family_name =~ "P1" ]]; then
    curl https://raw.githubusercontent.com/kpango/dotfiles/main/arch/aur_p1.list -o aur.list
elif [[ $family_name =~ "X1" ]]; then
    curl https://raw.githubusercontent.com/kpango/dotfiles/main/arch/aur.list -o aur.list
else
    curl https://raw.githubusercontent.com/kpango/dotfiles/main/arch/aur_desk.list -o aur.list
fi
sudo pacman -Rsucnd --noconfirm go
paru -Syu --noanswerdiff --noanswerclean --noconfirm - < aur.list
sudo cp /usr/bin/google-chrome-stable /usr/bin/chrome
fc-cache -f -v
if [[ $family_name =~ "P1" ]]; then
    systemctl --user enable psd.service
fi
