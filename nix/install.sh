#!/bin/sh
SSID=$1
PASSWORD=$2

ip a
umount /dev/nvme0n1
wipefs -a /dev/nvme0n1 && sync
shred -n 2 -z /dev/nvme0n1 && sync
lvremove /dev/nvme0n1
pvremove /dev/nvme0n1
parted -s -a optimal /dev/nvme0n1 -- mklabel gpt mkpart ESP fat32 1 513MiB set 1 boot on
parted -s -a optimal /dev/nvme0n1 -- mkpart primary xfs 513MiB 100%

cryptsetup luksFormat /dev/nvme0n1p2
cryptsetup luksOpen /dev/nvme0n1p2 enc-pv

pvcreate /dev/mapper/enc-pv
vgcreate vg /dev/mapper/enc-pv
lvcreate -L 8G -n swap vg
lvcreate -l '100%FREE' -n root vg

mkfs.vfat -cvIF32 /dev/nvme0n1p1
mkfs.xfs -L root /dev/vg/root
mkswap -L swap /dev/vg/swap

mount /dev/vg/root /mnt
mkdir /mnt/boot
mount /dev/sda1 /mnt/boot
swapon /dev/vg/swap

wpa_passphrase ${SSID} ${PASSWORD} >/etc/wpa_supplicant.conf
systemctl start wpa_supplicant

nixos-generate-config --root /mnt

mv /mnt/etc/nixos/configuration.nix /mnt/etc/nixos/configuration.nix.back
cp ./*.nix /mnt/etc/nixos/
cp -r ./pkgs /mnt/etc/nixos/

nixos-install

reboot
