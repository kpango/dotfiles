#!/bin/zsh
DEVICE=/dev/sda
BOOT_PART=${DEVICE}1
ROOT_PART=${DEVICE}2
ROOT=/mnt
BOOT=${ROOT}/boot
BOOT_SIZE=110MiB
FILESYS=xfs

unmount(){
    sudo umount -f ${BOOT} && sync
    sudo umount -f ${ROOT} && sync
    sudo umount -f ${BOOT_PART} && sync
    sudo umount -f ${ROOT_PART} && sync
    sudo umount -f ${DEVICE} && sync
}

rmpart(){
echo "d
3


w" | sudo fdisk $1
echo "dpkg
2


w" | sudo fdisk $1
echo "d
1


w" | sudo fdisk $1
}

partition(){
    sudo parted -s -a optimal ${DEVICE} -- mklabel msdos mkpart primary fat32 0% ${BOOT_SIZE} set 1 boot on && sync
    sudo parted -s -a optimal ${DEVICE} -- mkpart primary ${FILESYS} ${BOOT_SIZE} 100% && sync
}

ip a
sudo rm -rf ${ROOT}/*
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
sudo wipefs -a ${DEVICE} && sync
echo "disks wiped"
# lsblk
# echo "shred ${DEVICE}"
# sudo shred -n 1 -z ${DEVICE} && sync
# echo "${DEVICE} shredded"
lsblk

sleep 10
echo "partition ${DEVICE}"
partition
echo "${DEVICE} partitioned"
lsblk
echo "format $BOOT_PART"
sudo mkfs.vfat -cvIF32 ${BOOT_PART} && sync
echo "$BOOT_PART formatted"
sleep 10
lsblk -a
echo "format $ROOT_PART"
sudo mkfs.${FILESYS} -f ${ROOT_PART} && sync
echo "$ROOT_PART formatted"
sleep 10
lsblk -a
echo "mount"
sudo mount -t ${FILESYS} ${ROOT_PART} ${ROOT} && sync
sudo mkdir -p ${BOOT}
sudo mount -t vfat ${BOOT_PART} ${BOOT} && sync
echo "mounted"

df -aT

cd /tmp

TARPATH=/tmp/arch.tar.gz
axel -a -n 10 -o ${TARPATH} http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-3-latest.tar.gz
sudo bsdtar -xpf ${TARPATH} -C ${ROOT}
sync
sudo rm -rf ${TARPATH}

NODE_NO=1
IP_RANGE="192.168.1"
GATEWAY="${IP_RANGE}.1"

sudo tee "${ROOT}/etc/systemd/network/eth0.network" <<EOF >/dev/null
[Match]
Name=eth0
[Network]
DHCP=false
Address=${IP_RANGE}.$((NODE_NO+2))/24
Gateway=${GATEWAY}
DNS=${GATEWAY}
EOF

sudo cat ${ROOT}/etc/systemd/network/eth0.network 

HOST="k8s-raspberry-pi-1"
echo ${HOST} | sudo tee -a ${ROOT}/etc/hostname > /dev/null

sudo tee ${ROOT}/etc/hosts <<EOF >/dev/null
127.0.0.1 localhost.localdomain localhost.local localhost ${HOST}.localdomain ${HOST}.local ${HOST}
::1 localhost.localdomain localhost ${HOST}.localdomain ${HOST}.local ${HOST}
EOF

echo "LANG=en_US.UTF-8" | sudo tee -a ${ROOT}/etc/locale.conf > /dev/null
sudo sed -i -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -T 0 -c -z -)/g" ${ROOT}/etc/makepkg.conf
sudo sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j9\"/g" ${ROOT}/etc/makepkg.conf
sudo sed -i -e "s/#BUILDDIR/BUILDDIR/g" ${ROOT}/etc/makepkg.conf
sudo sed -i -e "s/MODULES=()/MODULES=(lz4 lz4_compress)/g" ${ROOT}/etc/mkinitcpio.conf
sudo sed -i -e "s/block filesystems/block resume filesystems/g" ${ROOT}/etc/mkinitcpio.conf

sudo cp /etc/pacman.conf ${ROOT}/etc/pacman.conf
sudo cp ./init.sh ${ROOT}/init.sh
sudo cp ./pkg.list ${ROOT}/pkg.list
sudo cp ./aur.list ${ROOT}/aur.list
sudo cp ./user-init.sh ${ROOT}/user-init.sh

echo "blacklist pcspkr" | sudo tee -a ${ROOT}/etc/modprobe.d/nobeep.conf > /dev/null
sudo sed -i -e "s/#DNS=/DNS=1.1.1.1 9.9.9.10 8.8.8.8 8.8.4.4/g" ${ROOT}/etc/systemd/resolved.conf
sudo sed -i -e "s/#FallbackDNS=/FallbackDNS/g" ${ROOT}/etc/systemd/resolved.conf

echo "unmount volumes"
unmount
echo "volumes unmounted"
