#!/bin/sh
DEVICE=/dev/nvme0n1
PART1=${DEVICE}p1
PART2=${DEVICE}p2
ip a
rm -rf /mnt/*
lsblk
umount -f ${DEVICE}
echo "remove partition"
echo "d
3


w" | fdisk ${DEVICE}
echo "d
2


w" | fdisk ${DEVICE}
echo "d
1


w" | fdisk ${DEVICE}
echo "partition removed"
lsblk
echo "wipe disks"
wipefs -a ${DEVICE} && sync
echo "disks wiped"
lsblk
echo "shred ${DEVICE}"
shred -n 2 -z ${DEVICE} && sync
echo "${DEVICE} shredded"
lsblk
echo "lvremove ${DEVICE}"
lvremove ${DEVICE}
echo "${DEVICE} lvremoved"
lsblk
echo "pvremove ${DEVICE}"
pvremove ${DEVICE}
echo "${DEVICE} pvremoved"
lsblk
echo "partition ${DEVICE}"
parted -s -a optimal ${DEVICE} -- mklabel gpt mkpart ESP fat32 0% 300MiB set 1 boot on
parted -s -a optimal ${DEVICE} -- mkpart primary xfs 300MiB 100%
echo "${DEVICE} partitioned"
lsblk
echo "format $PART1"
mkfs.vfat -f -cvIF32 ${PART1} 
echo "$PART1 formatted"
lsblk -a
echo "format $PART2"
mkfs.xfs -f ${PART2}
echo "$PART2 formatted"
lsblk -a
echo "mount"
mount ${PART2} /mnt
mkdir -p /mnt/boot
mount ${PART1} /mnt/boot
mkdir -p /mnt/home/kpango
echo "mounted"
df -aT
echo "download deps"
rm -rf Xdefaults chroot.sh locale.gen mirrorlist
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/Xdefaults
cp Xdefaults /mnt/home/kpango/.Xdefaults
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/chroot.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/mirrorlist
pacman -S archlinux-keyring
echo "deps downloaded"
ls -la
echo "start pacstrap"
pacstrap -i /mnt base base-devel archlinux-keyring intel-ucode dmenu rxvt-unicode git neovim zsh tmux wlc wayland sway i3status ntp docker ranger
# pacstrap -i /mnt base base-devel archlinux-keyring intel-ucode dosfstools grub efibootmgr
genfstab -U -p /mnt >> /mnt/etc/fstab
cp ./mirrorlist /mnt/etc/pacman.d/mirrorlist
cp ./locale.gen /mnt/etc/locale.gen
cp ./chroot.sh /mnt/chroot.sh
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
# arch-chroot /mnt
arch-chroot /mnt sh /chroot.sh
