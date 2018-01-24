#!/bin/sh
umount /dev/sda
wipefs -a /dev/sda && sync
shred -n 2 -z /dev/sda && sync
lvremove /dev/sda
pvremove /dev/sda
parted /dev/sda \
  -s mklabel gpt \
  -s mkpart ESP fat32 0% 513MiB \
  -s set 1 boot on
  -s mkpart primary xfs 513MiB 100% \
  -s p
mkfs.vfat -cvIF32 /dev/sda1 
mkfs.xfs /dev/sda2
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
mkdir -p /mnt/home/kpango
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/Xdefaults
cp Xdefaults /mnt/home/kpango/.Xdefaults
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/chroot.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/mirrorlist
pacstrap -i /mnt base base-devel archlinux-keyring cmake clang dmenu rxvt-unicode git neovim zsh tmux grub efibootmgr wlc wayland sway i3status chromium openssh ntp ranger
genfstab -U -p /mnt >> /mnt/etc/fstab
cp ./mirrorlist /mnt/etc/pacman.d/mirrorlist
cp ./locale.gen /mnt/etc/locale.gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
arch-chroot /mnt
