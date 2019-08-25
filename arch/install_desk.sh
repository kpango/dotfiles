#!/bin/sh
DEVICE1=/dev/nvme0n1
DEVICE2=/dev/nvme1n1
BOOT_PART=${DEVICE1}p1
SWAP=${DEVICE2}p1
RAID_PART1=${DEVICE1}p2
RAID_PART2=${DEVICE2}p2
RAID=/dev/md0
ROOT_PART=${RAID}p1
ROOT=/mnt
BOOT=${ROOT}/boot
ESP_SIZE=300MiB
FILESYS=xfs

unmount(){
    umount -f ${BOOT} && sync
    umount -f ${ROOT} && sync
    umount -f ${ROOT_PART} && sync
    umount -f ${RAID} && sync
    umount -f ${BOOT_PART} && sync
    umount -f ${RAID_PART1} && sync
    umount -f ${RAID_PART2} && sync
    swapoff ${SWAP}
    swapoff -a
    rm -f /swapfile
    umount -f ${DEVICE1} && sync
    umount -f ${DEVICE2} && sync
}

unmdadm(){
    mdadm -S ${ROOT_PART} && sync
    mdadm -S ${RAID} && sync
    mdadm -S ${BOOT_PART} && sync
    mdadm -S ${SWAP} && sync
    mdadm -S ${RAID_PART1} && sync
    mdadm -S ${RAID_PART2} && sync
    mdadm -S ${DEVICE1} && sync
    mdadm -S ${DEVICE2} && sync
    mdadm --misc --zero-superblock ${ROOT_PART} && sync
    mdadm --misc --zero-superblock ${RAID} && sync
    mdadm --misc --zero-superblock ${BOOT_PART} && sync
    mdadm --misc --zero-superblock ${SWAP} && sync
    mdadm --misc --zero-superblock ${RAID_PART1} && sync
    mdadm --misc --zero-superblock ${RAID_PART2} && sync
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
    parted -s -a optimal ${DEVICE1} -- mkpart primary ${FILESYS} ${ESP_SIZE} 100% set 2 raid on && sync
    parted -s -a optimal ${DEVICE2} -- mklabel gpt mkpart primary linux-swap 0% ${ESP_SIZE} set 1 swap on && sync
    parted -s -a optimal ${DEVICE2} -- mkpart primary ${FILESYS} ${ESP_SIZE} 100% set 2 raid on && sync
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
echo "nvme0n1 shredded"
lsblk
echo "shred nvme1n1"
shred -n 1 -z ${DEVICE2} && sync
echo "nvme1n1 shredded"
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
cat /proc/mdstat
lsblk
echo "volume partitioning"
partition
echo "volume partitioned"
lsblk
echo "creating mdadm raid0"
mdadm --create ${RAID} --verbose --level=raid0 --chunk=256 --raid-devices=2 ${RAID_PART1} ${RAID_PART2} && sync
echo "raid0 volume created"
cat /proc/mdstat
lsblk
echo "raid partitioning"
parted -s -a optimal ${RAID} -- mklabel gpt mkpart primary ${FILESYS} 0% 100% set 1 root on && sync
echo "raid partitioned"
lsblk
echo "raid formatting"
mkswap ${SWAP} && sync
swapon ${SWAP} && sync
mkfs.vfat -cvIF32 ${BOOT_PART} && sync
mkfs.${FILESYS} -f ${ROOT_PART} && sync
echo "raid formatted"
lsblk
echo "raid mount"
mount ${ROOT_PART} ${ROOT} && sync
mkdir -p ${BOOT}
mount ${BOOT_PART} ${BOOT} && sync
mkdir -p ${ROOT}/home/kpango
echo "raid mounted"
df -aT
echo "download deps"
rm -rf Xdefaults chroot.sh locale.gen mirrorlist
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/Xdefaults
cp Xdefaults ${ROOT}/home/kpango/.Xdefaults
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/chroot.sh
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/locale.gen
wget https://raw.githubusercontent.com/kpango/dotfiles/master/arch/mirrorlist
wget https://raw.githubusercontent.com/kpango/dotfiles/master/network/sysctl.conf
pacman -S archlinux-keyring mdadm
echo "deps downloaded"
ls -la
echo "start pacstrap"
pacstrap -i ${ROOT} \
    base \
    base-devel \
    archlinux-keyring \
    intel-ucode \
    dmenu \
    rxvt-unicode \
    git \
    neovim \
    zsh \
    tmux \
    wlc \
    wayland \
    sway \
    i3status \
    ntp \
    docker \
    ranger \
    dialog \
    networkmanager \
    network-manager-applet \
    fcitx-im \
    fcitx-configtool \
    fcitx-mozc \
    chromium \
    alsa-utils \
    apulse \
    mdadm \
    discord \
    slack-desktop

pacstrap -i ${ROOT} \
    nvidia \
    steam \
    lib32-nvidia-utils 

echo "pacstrap finished"
genfstab -U -p ${ROOT} >> ${ROOT}/etc/fstab
cp ./mirrorlist ${ROOT}/etc/pacman.d/mirrorlist
cp ./locale.gen ${ROOT}/etc/locale.gen
cp ./chroot.sh ${ROOT}/chroot.sh
cp ./sysctl.conf ${ROOT}/etc/sysctl.conf
echo LANG=en_US.UTF-8 > ${ROOT}/etc/locale.conf
mdadm --detail --scan >> ${ROOT}/etc/mdadm.conf
arch-chroot ${ROOT} sh /chroot_desk.sh
arch-chroot ${ROOT} sed -i -e "s/block filesystems/mdadm_udev block filesystems/g" /etc/mkinitcpio.conf
arch-chroot ${ROOT} mkinitcpio -p linux
mkinitcpio -p linux
