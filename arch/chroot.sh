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
#yaourt -S slack-desktop ibus mozc python-gobject
useradd -m -g users -G wheel -s /usr/bin/zsh kpango
passwd kpango
bootctl --path=/boot install

