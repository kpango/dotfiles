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
    umount -f ${BOOT_PART} && sync
    umount -f ${ROOT_PART} && sync
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

echo "partition ${DEVICE}"
parted -s -a optimal ${DEVICE} -- mklabel gpt mkpart ESP fat32 0% 300MiB set 1 boot on
parted -s -a optimal ${DEVICE} -- mkpart primary xfs 300MiB 100%
echo "${DEVICE} partitioned"
lsblk
echo "format $BOOT_PART"
mkfs.vfat -cvIF32 ${BOOT_PART} && sync
echo "$BOOT_PART formatted"
lsblk -a
echo "format $ROOT_PART"
mkfs.${FILESYS} -f ${ROOT_PART} && sync
echo "$ROOT_PART formatted"
lsblk -a
echo "mount"
mount ${ROOT_PART} ${ROOT} && sync
mkdir -p ${BOOT}
mount ${BOOT_PART} ${BOOT} && sync
mkdir -p ${ROOT}/home/kpango/go/src/github.com/kpango
echo "mounted"
df -aT
echo "download deps"
rm -rf chroot.sh locale.gen mirrorlist
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/chroot.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/mirrorlist
pacman -S archlinux-keyring reflector
reflector - verbose - latest 200 - number 5 - sort rate - save /etc/pacman.d/mirrorlist
echo "deps downloaded"
ls -la
echo "start pacstrap"
pacstrap -i ${ROOT} \
    base \
    base-devel \
    archlinux-keyring \
    intel-ucode \
    rxvt-unicode \
    xsel \
    xclip \
    git \
    neovim \
    zsh \
    tmux \
    ntp \
    docker \
    compton \
    ranger \
    dialog \
    networkmanager \
    network-manager-applet \
    fcitx \
    fcitx-im \
    fcitx-configtool \
    fcitx-mozc \
    chromium \
    openssh \
    avr-gcc \
    avrdude \
    avr-gdb \
    avr-binutils \
    kubectl \
    kubectx \
    lsof \
    pciutils \
    lshw \
    pacman-contrib \
    reflector \
    tlp \
    nvidia
    # wlc \
    # wayland \
    # nvidia \
    # steam \

echo "pacstrap finished"

genfstab -U -p ${ROOT} >> ${ROOT}/etc/fstab
cp ./mirrorlist ${ROOT}/etc/pacman.d/mirrorlist
cp ./locale.gen ${ROOT}/etc/locale.gen
cp ./chroot.sh ${ROOT}/chroot.sh
echo LANG=en_US.UTF-8 > ${ROOT}/etc/locale.conf
arch-chroot ${ROOT} sh /chroot.sh
echo "unmount volumes"
unmount
echo "volumes unmounted"
