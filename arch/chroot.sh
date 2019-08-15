#!/bin/sh
echo archpango >> /etc/hostname
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >> /etc/locale.conf
systemctl enable dhcpcd
passwd
yaourt -S sway-dmenu-desktop
sudo systemctl enable ntpd
sudo systemctl start ntpd
useradd -m -g users -G wheel -s /usr/bin/zsh kpango
passwd kpango
sed -i -e "s/block filesystems/block mdadm_udev filesystems/g" /etc/mkinitcpio.conf
sed -i -e "s%BINARIES=()%BINARIES=(/usr/bin/mdmon)%g" /etc/mkinitcpio.conf
mkinitcpio -p linux
mkdir /boot/efi/EFI
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub --boot-directory=/boot/efi/EFI --recheck --debug
grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg
