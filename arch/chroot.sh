#!/bin/sh
sed -i -e "s/COMPRESSXZ.*/COMPRESSXZ=(xz -T 0 -c -z -)/g" /etc/makepkg.conf
sed -i -e "s/# Color/Color/g" /etc/pacman.conf
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ../
rm -r yay
pacman -Rs go
yay -S ttf-ricty sway-dmenu-desktop
HOST="archpango"
echo archpango >> /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1 localhost.localdomain localhost.local localhost ${HOST}.localdomain ${HOST}.local ${HOST}
::1 localhost.localdomain localhost ${HOST}.localdomain ${HOST}.local ${HOST}
EOF
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >> /etc/locale.conf
passwd
sudo systemctl enable ntpd
sudo systemctl start ntpd
sudo systemctl enable docker
sudo systemctl enable NetworkManager
useradd -m -g users -G wheel -s /usr/bin/zsh kpango
passwd kpango
visudo
mkdir /boot/efi/EFI
bootctl --path=/boot install
DEVICE_ID=$(lsblk -f | grep p2 | awk '{print $3}')
echo ${DEVICE_ID}
cat <<EOF > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=${DEVICE_ID} rw
EOF
rm -rf /boot/loader/loader.conf
cat <<EOF > /boot/loader/loader.conf
default arch
timeout 1
editor no
EOF
cat <<EOF >> /etc/profile
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
EOF
bootctl update
bootctl list
