#!/bin/sh
reflector --verbose --latest 200 --number 10 --sort rate --save /etc/pacman.d/mirrorlist
sed -i -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -T 0 -c -z -)/g" /etc/makepkg.conf
sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=”-j9\"/g" /etc/makepkg.conf
sed -i -e "s/#Color/Color/g" /etc/pacman.conf
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ../
rm -r yay

pacman -Rs go

yay -S ttf-hackgen \
    wlroots-git \
    sway-git \
    discord \
    slack-desktop \
    urxvt-perls \
    urxvt-resize-font-git \
    rofi \
    waybar-git \
    ripgrep-git \
    exa-git \
    chrome-remote-desktop \
    thefuck \
    systemd-boot-pacman-hook \
    nodejs \
    yarn \
    ghq \
    axel

HOST="archpango"
echo archpango >>/etc/hostname
cat <<EOF >/etc/hosts
127.0.0.1 localhost.localdomain localhost.local localhost ${HOST}.localdomain ${HOST}.local ${HOST}
::1 localhost.localdomain localhost ${HOST}.localdomain ${HOST}.local ${HOST}
EOF
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >>/etc/locale.conf
passwd
systemctl enable ntpd
systemctl start ntpd
systemctl enable docker
systemctl enable NetworkManager
sed -i -e "s/#DNS=/DNS=1.1.1.1 9.9.9.10 8.8.8.8 8.8.4.4/g" /etc/systemd/resolved.conf && \
sed -i -e "s/#FallbackDNS=/FallbackDNS/g" /etc/systemd/resolved.conf && \
useradd -m -g users -G wheel,kpango,docker,sshd,storage,power,autologin,audio -s /usr/bin/zsh kpango
passwd kpango
visudo
mkdir /boot/efi/EFI
bootctl --path=/boot install
DEVICE_ID=$(lsblk -f | grep p2 | awk '{print $3}')
echo ${DEVICE_ID}
cat <<EOF >/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=${DEVICE_ID} rw
EOF
rm -rf /boot/loader/loader.conf
cat <<EOF >/boot/loader/loader.conf
default arch
timeout 1
editor no
EOF
cat <<EOF >>/etc/profile
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
bootctl update
bootctl list
