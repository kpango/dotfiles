#!/bin/sh
DEVICE1=/dev/nvme0n1
DEVICE2=/dev/nvme1n1
RAID1_PART1=${DEVICE1}p1
RAID1_PART2=${DEVICE2}p1
RAID0_PART1=${DEVICE1}p2
RAID0_PART2=${DEVICE2}p2
RAID0=/dev/md0
RAID1=/dev/md1
BOOT_PART=${RAID1}p1
ROOT_PART=${RAID0}p1
ROOT=/mnt
BOOT=${ROOT}/boot
ESP_SIZE=480MiB
FILESYS=xfs

unmount(){
    umount -f ${BOOT} && sync
    umount -f ${ROOT} && sync
    umount -f ${ROOT_PART} && sync
    umount -f ${RAID} && sync
    umount -f ${RAID1_PART1} && sync
    umount -f ${RAID0_PART1} && sync
    umount -f ${RAID0_PART2} && sync
    swapoff ${RAID1_PART2}
    swapoff -a
    rm -f /swapfile
    umount -f ${DEVICE1} && sync
    umount -f ${DEVICE2} && sync
}

unmdadm(){
    mdadm -S ${ROOT_PART} && sync
    mdadm -S ${RAID} && sync
    mdadm -S ${RAID1_PART1} && sync
    mdadm -S ${RAID1_PART2} && sync
    mdadm -S ${RAID0_PART1} && sync
    mdadm -S ${RAID0_PART2} && sync
    mdadm -S ${DEVICE1} && sync
    mdadm -S ${DEVICE2} && sync
    mdadm --misc --zero-superblock ${ROOT_PART} && sync
    mdadm --misc --zero-superblock ${RAID} && sync
    mdadm --misc --zero-superblock ${RAID1_PART1} && sync
    mdadm --misc --zero-superblock ${RAID1_PART2} && sync
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
    parted -s -a optimal ${DEVICE2} -- mklabel gpt mkpart ESP fat32 0% ${ESP_SIZE} set 1 boot on && sync
    parted -s -a optimal ${DEVICE1} -- mkpart primary ${FILESYS} ${ESP_SIZE} 100% set 2 raid on && sync
    parted -s -a optimal ${DEVICE2} -- mkpart primary ${FILESYS} ${ESP_SIZE} 100% set 2 raid on && sync
}

mkraid(){
    mdadm --create ${RAID1} --verbose --level=raid1 --chunk=256 --raid-devices=2 ${RAID1_PART1} ${RAID1_PART2} && sync
    mdadm --create ${RAID0} --verbose --level=raid0 --chunk=512 --raid-devices=2 ${RAID0_PART1} ${RAID0_PART2} && sync
}

partraid(){
    parted -s -a optimal ${RAID1} -- mklabel gpt mkpart ESP fat32 0% 100% set 1 boot on && sync
    parted -s -a optimal ${RAID0} -- mklabel gpt mkpart primary ${FILESYS} 0% 100% set 1 root on && sync
}

ip a
rm -rf ${ROOT}
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

# echo "lvremove"
# lvremove ${DEVICE1} && sync
# lvremove ${DEVICE2} && sync
# echo "lvremoved"
# lsblk
# 
# echo "pvremove"
# pvremove ${DEVICE1} && sync
# pvremove ${DEVICE2} && sync
# echo "pvremoved"
# lsblk

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
sleep 10
cat /proc/mdstat
lsblk

echo "raid partitioning"
partraid
echo "raid partitioned"
sleep 10
lsblk

echo "raid formatting"
mkfs.vfat -cvIF32 ${BOOT_PART} && sync
mkfs.${FILESYS} -f ${ROOT_PART} && sync
echo "raid formatted"
sleep 10
lsblk

echo "raid mount"
mount ${ROOT_PART} ${ROOT} && sync
mkdir -p ${BOOT}
mount ${BOOT_PART} ${BOOT} && sync
echo "raid mounted"
mkdir -p ${ROOT}/home/kpango
df -aT
echo "download deps"
mkdir -p ${ROOT}/home/kpango/go/src/github.com/kpango
echo "mounted"
df -aT
echo "download deps"
rm -rf chroot.sh locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/chroot_desk.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/user-init.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/pkg_desk.list
pacman -Sy --noconfirm
pacman -S --noconfirm archlinux-keyring reflector
reflector --age 24 --latest 200 --number 10 --protocol http --protocol https --sort rate --save /etc/pacman.d/mirrorlist
echo "deps downloaded"
ls -la
echo "start pacstrap"
pacstrap -i ${ROOT} - < pkg_desk.list
echo "pacstrap finished"

genfstab -U -p ${ROOT} >> ${ROOT}/etc/fstab
cp /etc/pacman.d/mirrorlist ${ROOT}/etc/pacman.d/mirrorlist
cp ./locale.gen ${ROOT}/etc/locale.gen
cp ./chroot_desk.sh ${ROOT}/chroot.sh
cp ./user-init.sh ${ROOT}/user-init.sh
echo LANG=en_US.UTF-8 > ${ROOT}/etc/locale.conf
# arch-chroot ${ROOT} sh /chroot.sh
# arch-chroot ${ROOT} sh /user-init.sh
# echo "unmount volumes"
# unmount
# echo "volumes unmounted"
mdadm --detail --scan >> ${ROOT}/etc/mdadm.conf
arch-chroot ${ROOT}
