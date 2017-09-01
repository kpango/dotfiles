#!/bin/bash
umount /dev/mmcblk0p1
umount /dev/mmcblk0
wipefs -a /dev/mmcblk0 && sync
dd if=/dev/zero of=/dev/mmcblk0 bs=1024 && sync
lvremove /dev/mmcblk0
pvremove /dev/mmcblk0
parted -s -a optimal /dev/mmcblk0 -- mklabel msdos
parted -s -a optimal /dev/mmcblk0 -- mkpart primary xfs 1 -1
mkfs.xfs /dev/mmcblk0p1
mount /dev/mmcblk0p1 /mnt
mkdir /mnt/home
mkdir /mnt/boot
mkdir /mnt/home/kpango
cp ./Xdefaults /mnt/home/kpango/.Xdefaults
cp ./zshrc /mnt/home/kpango/.zshrc
cp ./chroot.sh /mnt
sudo cp ./mirrorlist /etc/pacman.d/mirrorlist
pacstrap -i /mnt base base-devel archlinux-keyring net-tools wireless_tools wpa_supplicant wpa_actiond dialog cmake clang dmenu rxvt-unicode git neovim zsh tmux grub-bios wlc wayland sway i3status chromium openssh ntp ranger
genfstab -U -p /mnt >> /mnt/etc/fstab
cp ./mirrorlist /mnt/etc/pacman.d/mirrorlist
cp ./locale.gen /mnt/etc/locale.gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
arch-chroot /mnt
