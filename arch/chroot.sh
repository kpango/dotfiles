#!/bin/sh
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclocl --systohc --utc
systemctl enable dhcpcd
passwd
yaourt -S sway-dmenu-desktop
sudo systemctl enable ntpd
sudo systemctl start ntpd
#yaourt -S slack-desktop ibus mozc python-gobject
useradd -m -g users -G wheel -s /usr/bin/zsh kpango
passwd kpango
grub-install --target=i386-pc --boot-directory=/boot --recheck /dev/mmcblk0
grub-mkconfig -o /boot/grub/grub.cfg
