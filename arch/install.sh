#!/bin/sh
DEVICE=/dev/nvme0n1
BOOT_PART=${DEVICE}p1
ROOT_PART=${DEVICE}p2
ROOT=/mnt
BOOT=${ROOT}/boot
ESP_SIZE=300MiB
FILESYS=xfs

unmount(){
    umount -f ${BOOT} && sync
    umount -f ${ROOT} && sync
    umount -f ${ROOT_PART} && sync
    umount -f ${BOOT_PART} && sync
    umount -f ${DEVICE} && sync
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
    parted -s -a optimal ${DEVICE} -- mklabel gpt mkpart ESP fat32 0% ${ESP_SIZE} set 1 boot on && sync
    parted -s -a optimal ${DEVICE} -- mkpart primary ${FILESYS} ${ESP_SIZE} 100% set 2 root on && sync
}

ip a
rm -rf ${ROOT}/*
lsblk

echo "unmount volumes"
unmount
echo "volumes unmounted"
lsblk
echo "unmount volumes"
unmount
echo "volumes unmounted"
lsblk

echo "remove partition"
rmpart ${DEVICE}
echo "partition removed"
lsblk
echo "wipe disks"
wipefs -a ${DEVICE} && sync
echo "disks wiped"
lsblk
echo "shred ${DEVICE}"
shred -n 1 -z ${DEVICE} && sync
echo "${DEVICE} shredded"
lsblk
echo "lvremove"
lvremove ${DEVICE} && sync
echo "lvremoved"
lsblk
echo "pvremove"
pvremove ${DEVICE} && sync
echo "pvremoved"
lsblk

sleep 10
echo "partition ${DEVICE}"
partition
echo "${DEVICE} partitioned"
lsblk
echo "format $BOOT_PART"
mkfs.vfat -cvIF32 ${BOOT_PART} && sync
echo "$BOOT_PART formatted"
sleep 10
lsblk -a
echo "format $ROOT_PART"
mkfs.${FILESYS} -f ${ROOT_PART} && sync
echo "$ROOT_PART formatted"
sleep 10
lsblk -a
echo "mount"
rm -rf ${ROOT}
mkdir -p ${ROOT}
mount ${ROOT_PART} ${ROOT} && sync
rm -rf ${BOOT}
mkdir -p ${BOOT}
mount ${BOOT_PART} ${BOOT} && sync
mkdir -p ${ROOT}/home/kpango/go/src/github.com/kpango
echo "mounted"
df -aT
echo "download deps"
rm -rf chroot.sh locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/main/arch/chroot.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/main/arch/user-init.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/main/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/main/arch/pkg.list
pacman -Sy --noconfirm
pacman -S --noconfirm archlinux-keyring
echo "deps downloaded"
ls -la
echo "start pacstrap"
pacstrap -i ${ROOT} - < pkg.list
echo "pacstrap finished"

genfstab -U -p ${ROOT} >> ${ROOT}/etc/fstab
cp /etc/pacman.d/mirrorlist ${ROOT}/etc/pacman.d/mirrorlist
cp ./locale.gen ${ROOT}/etc/locale.gen
cp ./chroot.sh ${ROOT}/chroot.sh
cp ./user-init.sh ${ROOT}/user-init.sh
echo LANG=en_US.UTF-8 > ${ROOT}/etc/locale.conf
# arch-chroot ${ROOT} sh /chroot.sh
# arch-chroot ${ROOT} sh /user-init.sh
# echo "unmount volumes"
# unmount
# echo "volumes unmounted"
