#!/bin/sh
sudo umount /dev/mmcblk0p1
sudo umount /dev/mmcblk0
sudo wipefs -a /dev/mmcblk0
sudo dd if=/dev/zero of=/dev/mmcblk0 bs=1M count=64 conv=notrunc && sync
sudo lvremove /dev/mmcblk0
sudo pvremove /dev/mmcblk0
sudo parted /dev/mmcblk0 mklable msdos mkpart primary xfs 1MiB 100%
sudo mkfs.xfs /dev/mmcblk0
mount /dev/mmcblk0 /mnt
mkdir /mnt/home
mkdir /mnt/boot
mkdir /mnt/home/kpango
cp ./Xdefaults /mnt/home/kpango/.Xdefaults
cp ./zshrc /mnt/home/kpango/.zshrc
cp ./chroot.sh /mnt
sudo cp ./mirrorlist /etc/pacman.d/mirrorlist
pacstrap -i /mnt base base-devel net-tools wireless_tools wpa_supplicant wpa_actiond dialog cmake clang dmenu rxvt-unicode git neovim zsh tmux grub-bios wlc wayland sway i3status yaourt chromium openssh ntp ranger
genfstab -U -p /mnt >> /mnt/etc/fstab
cp ./mirrorlist /mnt/etc/pacman.d/mirrorlist
cp ./locale.gen /mnt/etc/locale.gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
arch-chroot /mnt
