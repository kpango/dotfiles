#!/bin/sh
pacman -Syu
git clone --depth 1 https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd -
rm -r yay

curl https://raw.githubusercontent.com/kpango/dotfiles/master/arch/aur.list -o aur.list
pacman -Rs go
yay -Syu - < aur.list
HACKGEN_VERSION="$(curl --silent https://github.com/yuru7/HackGen/releases/latest | sed 's#.*tag/\(.*\)\".*#\1#' | sed 's/v//g')"
HACKGEN_FILENAME=HackGenNerd_v${HACKGEN_VERSION}
axel "https://github.com/yuru7/HackGen/releases/download/v${HACKGEN_VERSION}/${HACKGEN_FILENAME}.zip"
unzip ${HACKGEN_FILENAME}.zip
sudo mv ${HACKGEN_FILENAME}/* /usr/share/fonts/TTF/
sudo cp /usr/bin/google-chrome-stable /usr/bin/chrome
rm -rg HackGen*
fc-cache -f -v
