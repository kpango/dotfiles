#!/bin/sh

SSD=/dev/nvme0n1
PP=/dev/nvme0n1p1
RP=/dev/nvme0n1p2
EPN=enc-pv
EP=/dev/mapper/$EPN
EFI=/mnt/boot/efi
KEY_FILE=hdd.key
INITRD_KEY=/mnt/boot/initrd.keys.gz

ip a
umount $SSD
wipefs -a $SSD && sync
shred -n 2 -z $SSD && sync
lvremove $SSD
pvremove $SSD
parted -s -a optimal $SSD -- mklabel gpt mkpart ESP fat32 1 513MiB set 1 boot on
parted -s -a optimal $SSD -- mkpart primary xfs 513MiB 100%

dd if=/dev/urandom of=$KEY_FILE bs=4096 count=4
cryptsetup luksFormat -c aes-xts-plain64 -s 256 -h sha512 $RP
cryptsetup luksAddKey $RP $KEY_FILE
cryptsetup luksOpen $RP $EPN

pvcreate $EP
vgcreate vg $EP
lvcreate -L 8G -n swap vg
lvcreate -l '100%FREE' -n root vg

mkfs.vfat -cvIF32 $PP
mkfs.xfs -L root /dev/vg/root
mkswap -L swap /dev/vg/swap

mount /dev/vg/root /mnt
mkdir -p $EFI
mount $PP $EFI
swapon /dev/vg/swap

find $KEY_FILE -print0 | sort -z | cpio -o -H newc -R +0:+0 --reproducible --null | gzip -9 > $INITRD_KEY
chmod 000 $INITRD_KEY

UUID=blkid | awk '{print $2}' | sed -e 's/^.*"\(.*\)"/\1/'
sed -e "s/UUID/$UUID/g" ./boot.nix > ./boot.nix

nixos-generate-config --root /mnt

mv /mnt/etc/nixos/configuration.nix /mnt/etc/nixos/configuration.nix.back
cp ./*.nix /mnt/etc/nixos/
cp -r ./pkgs /mnt/etc/nixos/
cp $KEY_FILE /mnt/

nixos-install
