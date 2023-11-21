#!/bin/sh
DEVICE1=/dev/nvme0n1
DEVICE2=/dev/nvme1n1
# RAID1_PART1=${DEVICE1}p1
# RAID1_PART2=${DEVICE2}p1
RAID0_PART1=${DEVICE1}p2
RAID0_PART2=${DEVICE2}p2
RAID0=/dev/md0
# RAID1=/dev/md1
# BOOT_PART=${RAID1}p1
BOOT_PART=${DEVICE1}p1
SWAP_PART=${DEVICE2}p1
ROOT_PART=${RAID0}p1
ROOT=/mnt
BOOT=${ROOT}/boot
SWAP=${ROOT}/swapfile
ESP_SIZE=64GiB
SWAP_SIZE=${ESP_SIZE}
FILESYS=xfs

unmount(){
    umount -f ${BOOT} && sync
    umount -f ${ROOT} && sync
    umount -f ${ROOT_PART} && sync
    umount -f ${BOOT_PART} && sync
    umount -f ${SWAP_PART} && sync
    umount -f ${RAID0} && sync
    # umount -f ${RAID1} && sync
    # umount -f ${RAID1_PART1} && sync
    # umount -f ${RAID1_PART2} && sync
    umount -f ${RAID0_PART1} && sync
    umount -f ${RAID0_PART2} && sync
    umount -f ${DEVICE1} && sync
    umount -f ${DEVICE2} && sync
}

unmdadm(){
    mdadm -S ${ROOT_PART} && sync
    mdadm -S ${BOOT_PART} && sync
    mdadm -S ${SWAP_PART} && sync
    # mdadm -S ${RAID1} && sync
    # mdadm -S ${RAID1_PART1} && sync
    # mdadm -S ${RAID1_PART2} && sync
    mdadm -S ${RAID0} && sync
    mdadm -S ${RAID0_PART1} && sync
    mdadm -S ${RAID0_PART2} && sync
    mdadm -S ${DEVICE1} && sync
    mdadm -S ${DEVICE2} && sync
    mdadm --misc --zero-superblock ${ROOT_PART} && sync
    mdadm --misc --zero-superblock ${BOOT_PART} && sync
    mdadm --misc --zero-superblock ${SWAP_PART} && sync
    # mdadm --misc --zero-superblock ${RAID1} && sync
    # mdadm --misc --zero-superblock ${RAID1_PART1} && sync
    # mdadm --misc --zero-superblock ${RAID1_PART2} && sync
    mdadm --misc --zero-superblock ${RAID0} && sync
    mdadm --misc --zero-superblock ${RAID0_PART1} && sync
    mdadm --misc --zero-superblock ${RAID0_PART2} && sync
    mdadm --misc --zero-superblock ${DEVICE1} && sync
    mdadm --misc --zero-superblock ${DEVICE2} && sync
}

rmpart(){
echo "d
3


w" | fdisk $1
echo "d
2


w" | fdisk $1
echo "d
1


w" | fdisk $1
}

partition(){
    parted -s -a optimal ${DEVICE1} -- mklabel gpt mkpart ESP fat32 0% ${ESP_SIZE} set 1 boot on && sync
    parted -s -a optimal ${DEVICE2} -- mklabel gpt mkpart primary linux-swap 0% ${SWAP_SIZE} set 1 swap on && sync
    parted -s -a optimal ${DEVICE1} -- mkpart primary ${FILESYS} ${ESP_SIZE} 100% set 2 raid on && sync
    parted -s -a optimal ${DEVICE2} -- mkpart primary ${FILESYS} ${ESP_SIZE} 100% set 2 raid on && sync
}

mkraid(){
    mdadm --create ${RAID0} --verbose --level=raid0 --chunk=512 --raid-devices=2 ${RAID0_PART1} ${RAID0_PART2} && sync
}

partraid(){
    parted -s -a optimal ${RAID0} -- mklabel gpt mkpart primary ${FILESYS} 0% 100% && sync
}

ip a
rm -rf ${ROOT}/*
lsblk

echo "unmount volumes"
unmount
echo "volumes unmounted"
lsblk

echo "mdadm clear"
unmdadm
unmdadm
echo "mdadm cleared"
lsblk

echo "unmount volumes"
unmount
echo "volumes unmounted"
lsblk

echo "remove partition"
rmpart ${DEVICE1}
rmpart ${DEVICE2}
echo "partition removed"
lsblk

echo "wipe disks"
wipefs -a ${DEVICE1} && sync
wipefs -a ${DEVICE2} && sync
echo "disks wiped"
lsblk

echo "shred nvme0n1"
shred -n 1 -z ${DEVICE1} && sync
echo "${DEVICE1} shredded"
lsblk

echo "shred nvme1n1"
shred -n 1 -z ${DEVICE2} && sync
echo "${DEVICE2} shredded"
lsblk

echo "lvremove"
lvremove ${DEVICE1} && sync
lvremove ${DEVICE2} && sync
echo "lvremoved"
lsblk

echo "pvremove"
pvremove ${DEVICE1} && sync
pvremove ${DEVICE2} && sync
echo "pvremoved"
lsblk

echo "mdadm clear"
unmdadm
unmdadm
echo "mdadm cleared"
lsblk

sleep 10
cat /proc/mdstat
lsblk
sleep 10

echo "volume partitioning"
partition
echo "volume partitioned"
lsblk

echo "creating mdadm raid"
mkraid
echo "raid volume created"
sleep 15
cat /proc/mdstat
lsblk

echo "raid partitioning"
partraid
echo "raid partitioned"
sleep 10
lsblk

echo "raid formatting"
mkfs.vfat -cvIF32 ${BOOT_PART} && sync
# mkswap ${SWAP_PART} && sync
mkfs.${FILESYS} -f ${ROOT_PART} && sync
echo "raid formatted"
sleep 10
lsblk

sleep 20
echo "raid mount"
rm -rf ${root}
mkdir ${ROOT}
mount ${ROOT_PART} ${ROOT} && sync
sleep 10
rm -rf ${BOOT}
mkdir -p ${BOOT}
mount ${BOOT_PART} ${BOOT} && sync
echo "raid mounted"
sleep 20

mkdir -p ${ROOT}/home/kpango
df -aT
echo "download deps"
mkdir -p ${ROOT}/home/kpango/go/src/github.com/kpango
echo "mounted"
df -aT
echo "download deps"
rm -rf chroot.sh locale.gen
curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/main/arch/chroot_p1.sh
curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/main/arch/user-init.sh
curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/main/arch/locale.gen
curl -fsSLO https://raw.githubusercontent.com/kpango/dotfiles/main/arch/pkg_p1.list
pacman -Sy --noconfirm
pacman -S --noconfirm archlinux-keyring
echo "deps downloaded"
ls -la
echo "start pacstrap"
pacstrap -i ${ROOT} - < pkg_p1.list
echo "pacstrap finished"

genfstab -U -p ${ROOT} >> ${ROOT}/etc/fstab
cp /etc/pacman.d/mirrorlist ${ROOT}/etc/pacman.d/mirrorlist
cp ./locale.gen ${ROOT}/etc/locale.gen
cp ./chroot_p1.sh ${ROOT}/chroot.sh
cp ./user-init.sh ${ROOT}/user-init.sh
echo LANG=en_US.UTF-8 > ${ROOT}/etc/locale.conf
mdadm --detail --scan >> ${ROOT}/etc/mdadm.conf
arch-chroot ${ROOT}
unmount
echo "volumes unmounted"
