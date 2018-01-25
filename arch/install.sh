#!/bin/sh
ip a
umount /dev/sda
wipefs -a /dev/sda && sync
shred -n 2 -z /dev/sda && sync
lvremove /dev/sda
pvremove /dev/sda
partes -s -a optimal /dev/sda -- mklabel gpt mkpart ESP fat32 1MiB 513MiB set 1 boot on
partes -s -a optimal /dev/sda -- mkpart primary xfs 513MiB 100%
mkfs.vfat -cvIF32 /dev/sda1 
mkfs.xfs /dev/sda2
mount /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
mkdir -p /mnt/home/kpango
rm -rf Xdefaults chroot.sh locale.gen mirrorlist
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/Xdefaults
cp Xdefaults /mnt/home/kpango/.Xdefaults
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/chroot.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/mirrorlist
pacstrap -i /mnt base base-devel archlinux-keyring cmake ccache clang dmenu rxvt-unicode git neovim zsh tmux wlc wayland sway i3status chromium openssh ntp ranger grub dosfstools efibootmgr
genfstab -U -p /mnt >> /mnt/etc/fstab
cp ./mirrorlist /mnt/etc/pacman.d/mirrorlist
cp ./locale.gen /mnt/etc/locale.gen
cp ./chroot.sh /mnt/chroot.sh
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
arch-chroot /mnt
