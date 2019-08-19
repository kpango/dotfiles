#!/bin/sh
echo archpango >> /etc/hostname
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >> /etc/locale.conf
systemctl enable dhcpcd
passwd
sudo systemctl enable ntpd
sudo systemctl start ntpd
sudo systemctl enable docker
useradd -m -g users -G wheel -s /usr/bin/zsh kpango
passwd kpango
mkdir /boot/efi/EFI
# grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub --boot-directory=/boot/efi/EFI --recheck --debug
# grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg
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

bootctl update
