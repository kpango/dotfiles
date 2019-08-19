#!/bin/sh
ip a
rm -rf /mnt
lsblk
echo "unmount volumes"
umount -f /mnt/boot
umount -f /mnt
umount -f /dev/md0p1 && sync
umount -f /dev/md0p2 && sync
umount -f /dev/nvme1n1p1 && sync
umount -f /dev/nvme0n1p1 && sync
umount -f /dev/md0 && sync
umount -f /dev/nvme0n1 && sync
umount -f /dev/nvme1n1 && sync
echo "volumes unmounted"
lsblk
echo "mdadm clear"
mdadm -S /dev/md0p1 && sync
mdadm -S /dev/md0p2 && sync
mdadm -S /dev/nvme1n1p1 && sync
mdadm -S /dev/nvme0n1p1 && sync
mdadm -S /dev/md0 && sync
mdadm -S /dev/nvme0n1 && sync
mdadm -S /dev/nvme1n1 && sync
mdadm --misc --zero-superblock /dev/md0p1 && sync
mdadm --misc --zero-superblock /dev/md0p2 && sync
mdadm --misc --zero-superblock /dev/nvme1n1p1 && sync
mdadm --misc --zero-superblock /dev/nvme0n1p1 && sync
mdadm --misc --zero-superblock /dev/md0 && sync
mdadm --misc --zero-superblock /dev/nvme0n1 && sync
mdadm --misc --zero-superblock /dev/nvme1n1 && sync
mdadm -S /dev/md0p1 && sync
mdadm -S /dev/md0p2 && sync
mdadm -S /dev/nvme1n1p1 && sync
mdadm -S /dev/nvme0n1p1 && sync
mdadm -S /dev/md0 && sync
mdadm -S /dev/nvme0n1 && sync
mdadm -S /dev/nvme1n1 && sync
mdadm --misc --zero-superblock /dev/md0p1 && sync
mdadm --misc --zero-superblock /dev/md0p2 && sync
mdadm --misc --zero-superblock /dev/nvme1n1p1 && sync
mdadm --misc --zero-superblock /dev/nvme0n1p1 && sync
mdadm --misc --zero-superblock /dev/md0 && sync
mdadm --misc --zero-superblock /dev/nvme0n1 && sync
mdadm --misc --zero-superblock /dev/nvme1n1 && sync
echo "mdadm cleared"
lsblk
echo "unmount volumes"
umount -f /mnt/boot
umount -f /mnt
umount -f /dev/md0p1 && sync
umount -f /dev/md0p2 && sync
umount -f /dev/nvme1n1p1 && sync
umount -f /dev/nvme0n1p1 && sync
umount -f /dev/md0 && sync
umount -f /dev/nvme0n1 && sync
umount -f /dev/nvme1n1 && sync
swapoff /dev/nvme1n1p1
echo "volumes unmounted"
lsblk
echo "remove partiion"
echo "d
3


w" | fdisk /dev/nvme0n1
echo "d
2


w" | fdisk /dev/nvme0n1
echo "d
1


w" | fdisk /dev/nvme0n1
echo "d
3


w" | fdisk /dev/nvme1n1
echo "d
2


w" | fdisk /dev/nvme1n1
echo "d
1


w" | fdisk /dev/nvme1n1
lsblk
echo "wipe disks"
wipefs -a /dev/nvme0n1 && sync
wipefs -a /dev/nvme1n1 && sync
echo "disks wiped"
lsblk
echo "shred nvme0n1"
shred -n 1 -z /dev/nvme0n1 && sync
echo "nvme0n1 shredded"
lsblk
echo "shred nvme1n1"
shred -n 1 -z /dev/nvme1n1 && sync
echo "nvme1n1 shredded"
lsblk
echo "lvremove"
lvremove /dev/nvme0n1 && sync
lvremove /dev/nvme1n1 && sync
echo "lvremoved"
lsblk
echo "pvremove"
pvremove /dev/nvme0n1 && sync
pvremove /dev/nvme1n1 && sync
echo "pvremoved"
lsblk
echo "mdadm clear"
mdadm -S /dev/md0p1 && sync
mdadm -S /dev/md0p2 && sync
mdadm -S /dev/nvme1n1p1 && sync
mdadm -S /dev/nvme0n1p1 && sync
mdadm -S /dev/md0 && sync
mdadm -S /dev/nvme0n1 && sync
mdadm -S /dev/nvme1n1 && sync
mdadm --misc --zero-superblock /dev/md0p1 && sync
mdadm --misc --zero-superblock /dev/md0p2 && sync
mdadm --misc --zero-superblock /dev/nvme1n1p1 && sync
mdadm --misc --zero-superblock /dev/nvme0n1p1 && sync
mdadm --misc --zero-superblock /dev/md0 && sync
mdadm --misc --zero-superblock /dev/nvme0n1 && sync
mdadm --misc --zero-superblock /dev/nvme1n1 && sync
mdadm -S /dev/md0p1 && sync
mdadm -S /dev/md0p2 && sync
mdadm -S /dev/nvme1n1p1 && sync
mdadm -S /dev/nvme0n1p1 && sync
mdadm -S /dev/md0 && sync
mdadm -S /dev/nvme0n1 && sync
mdadm -S /dev/nvme1n1 && sync
mdadm --misc --zero-superblock /dev/md0p1 && sync
mdadm --misc --zero-superblock /dev/md0p2 && sync
mdadm --misc --zero-superblock /dev/nvme1n1p1 && sync
mdadm --misc --zero-superblock /dev/nvme0n1p1 && sync
mdadm --misc --zero-superblock /dev/md0 && sync
mdadm --misc --zero-superblock /dev/nvme0n1 && sync
mdadm --misc --zero-superblock /dev/nvme1n1 && sync
echo "mdadm cleared"
cat /proc/mdstat
lsblk
echo "volume partitioning"
parted -s -a optimal /dev/nvme0n1 -- mklabel gpt mkpart ESP fat32 0% 300MiB set 1 boot on && sync
parted -s -a optimal /dev/nvme0n1 -- mkpart primary xfs 300MiB 100% set 2 raid on && sync
parted -s -a optimal /dev/nvme1n1 -- mklabel gpt mkpart primary linux-swap 0% 300MiB set 1 swap on && sync
parted -s -a optimal /dev/nvme1n1 -- mkpart primary xfs 300MiB 100% set 2 raid on && sync
echo "volume partitioned"
lsblk
echo "creating mdadm raid0"
mdadm --create /dev/md0 --verbose --level=raid0 --chunk=256 --raid-devices=2 /dev/nvme0n1p2 /dev/nvme1n1p2 && sync
echo "raid0 volume created"
cat /proc/mdstat
lsblk
echo "raid partitioning"
parted -s -a optimal /dev/md0 -- mklabel gpt mkpart primary xfs 0% 100% set 1 root on && sync
echo "raid partitioned"
lsblk
echo "raid formatting"
mkswap /dev/nvme1n1p1 && sync
swapon /dev/nvme1n1p1 && sync
mkfs.vfat -f -cvIF32 /dev/nvme0n1p1 && sync
mkfs.xfs -f /dev/md0p1 && sync
echo "raid formatted"
lsblk
echo "raid mount"
mount /dev/md0p1 /mnt && sync
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot && sync
mkdir -p /mnt/home/kpango
echo "raid mounted"
df -aT
echo "download deps"
rm -rf Xdefaults chroot.sh locale.gen mirrorlist
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/Xdefaults
cp Xdefaults /mnt/home/kpango/.Xdefaults
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/chroot.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/mirrorlist
pacman -S archlinux-keyring mdadm
echo "deps downloaded"
ls -la
echo "start pacstrap"
pacstrap -i /mnt base base-devel archlinux-keyring intel-ucode dmenu rxvt-unicode git neovim zsh tmux wlc wayland sway i3status ntp docker ranger dosfstools grub efibootmgr mdadm
# pacstrap -i /mnt base base-devel archlinux-keyring intel-ucode dosfstools grub efibootmgr mdadm
genfstab -U -p /mnt >> /mnt/etc/fstab
cp ./mirrorlist /mnt/etc/pacman.d/mirrorlist
cp ./locale.gen /mnt/etc/locale.gen
cp ./chroot.sh /mnt/chroot.sh
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
mdadm --detail --scan >> /mnt/etc/mdadm.conf
# arch-chroot /mnt
arch-chroot /mnt sh /chroot.sh
