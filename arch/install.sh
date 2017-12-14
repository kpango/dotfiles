#!/bin/bash
umount $1
umount $1
wipefs -a $1 && sync
dd if=/dev/zero of=$1 bs=1024 && sync
lvremove $1
pvremove $1
parted -s -a optimal $1 -- mklabel msdos
parted -s -a optimal $1 -- mkpart primary xfs 1 -1
mkfs.xfs $1p1
mount $1p1 /mnt
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
