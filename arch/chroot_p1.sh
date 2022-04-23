#!/bin/sh
DEVICE1=/dev/nvme0n1
DEVICE2=/dev/nvme1n1
RAID1_PART1=${DEVICE1}p1
RAID1_PART2=${DEVICE2}p1
RAID0_PART1=${DEVICE1}p2
RAID0_PART2=${DEVICE2}p2
RAID0=/dev/md0
RAID1=/dev/md1
# BOOT_PART=${RAID1}p1
BOOT_PART=${DEVICE1}p1
SWAP_PART=${DEVICE2}p1
ROOT_PART=${RAID0}p1
ROOT=/
BOOT=${ROOT}boot
ESP_SIZE=64GiB
SWAP_SIZE=${ESP_SIZE}
FILESYS=xfs

sed -i -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -T 0 -c -z -)/g" /etc/makepkg.conf
sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j9\"/g" /etc/makepkg.conf
sed -i -e "s/#BUILDDIR/BUILDDIR/g" /etc/makepkg.conf
sed -i -e "s/#Color/Color\nILoveCandy/g" /etc/pacman.conf
cat <<EOF >>/etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
echo "blacklist iTCO_wdt" > /etc/modprobe.d/nowatchdog.conf

HOST="archpango"
echo ${HOST} >>/etc/hostname
cat <<EOF >/etc/hosts
127.0.0.1 localhost.localdomain localhost.local localhost ${HOST}.localdomain ${HOST}.local ${HOST}
::1 localhost.localdomain localhost ${HOST}.localdomain ${HOST}.local ${HOST}
EOF
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >>/etc/locale.conf
timedatectl set-timezone Asia/Tokyo

# https://itsfoss.com/swap-size/
# fallocate -l 72G /swapfile
# chmod 600 /swapfile
mkswap ${SWAP_PART} && sync
swapon ${SWAP_PART} && sync
echo "${SWAP_PART}     	none    	swap    	defaults,noatime    	0 0" | tee -a /etc/fstab

sed -i -e "s/#DNS=/DNS=1.1.1.1 8.8.8.8 9.9.9.10 8.8.4.4/g" /etc/systemd/resolved.conf
sed -i -e "s/#FallbackDNS=/FallbackDNS/g" /etc/systemd/resolved.conf

LOGIN_USER=kpango
HOME=/home/${LOGIN_USER}

groupadd ${LOGIN_USER}
groupadd sshd
groupadd autologin
groupadd input
groupadd uinput
groupadd pulse
groupadd pulse-access
groupadd bumblebee


groupmod -g 1000 -o users
useradd -m -o -u 1000 -g users -G wheel,users,${LOGIN_USER},docker,sshd,storage,power,autologin,audio,pulse,pulse-access,input,bumblebee,uinput -s /usr/bin/zsh ${LOGIN_USER}
passwd ${LOGIN_USER}
sed -e '/%wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers | EDITOR=tee visudo >/dev/null
sed -e '/%wheel ALL=(ALL) NOPASSWORD: ALL/s/^# %wheel/kpango/' /etc/sudoers | EDITOR=tee visudo >/dev/null
passwd

mkdir -p ${HOME}/.zplug
mkdir -p ${HOME}/.config
mkdir -p ${HOME}/.cache

echo "tmpfs /tmp tmpfs nodiratime,noatime,nosuid,nodev,size=1g 0 0" | tee -a /etc/fstab
echo "tmpfs /var/tmp tmpfs nodiratime,noatime,nosuid,nodev,size=64m 0 0" | tee -a /etc/fstab
echo "tmpfs /var/cache tmpfs nodiratime,noatime,nosuid,nodev,size=64m 0 0" | tee -a /etc/fstab
echo "tmpfs /home/kpango/.cache/fontconfig tmpfs nodiratime,noatime,nosuid,nodev,size=10m 0 0" | tee -a /etc/fstab
echo "tmpfs /home/kpango/.cache/mesa_shader_cache tmpfs nodiratime,noatime,nosuid,nodev,size=10m 0 0" | tee -a /etc/fstab
echo "tmpfs /home/kpango/.cache/google-chrome-beta tmpfs nodiratime,noatime,nosuid,nodev,size=2g 0 0" | tee -a /etc/fstab


cat <<EOF >/etc/udev/rules.d/input.rules
KERNEL=="event*", NAME="input/%k", MODE="660", GROUP="input"
EOF
cat <<EOF >/etc/udev/rules.d/uinput.rules
KERNEL=="uinput", GROUP="uinput"
EOF

cat <<EOF >/etc/udev/hwdb.d/90-thinkpad-keyboard.hwdb
evdev:name:ThinkPad Extra Buttons:dmi:bvn*:bvr*:bd*:svnLENOVO*:pn*
 KEYBOARD_KEY_45=prog1
 KEYBOARD_KEY_49=prog2
EOF

systemctl enable chronyd
systemctl start chronyd
systemctl enable docker
systemctl enable tlp
systemctl enable tlp-sleep
systemctl enable NetworkManager
systemctl enable fstrim.timer

sed -i -e "s/MODULES=()/MODULES=(battery lz4 lz4_compress i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /etc/mkinitcpio.conf
sed -i -e "s/BINARIES=()/BINARIES=(\"\/sbin\/mdmon\")/g" /etc/mkinitcpio.conf
sed -i -e "s/FILES=()/FILES=(\"\/etc\/mdadm.conf\")/g" /etc/mkinitcpio.conf
sed -i -e "s/block filesystems/block mdadm mdadm_udev resume filesystems/g" /etc/mkinitcpio.conf

mkinitcpio -p linux-zen

rm -rf ${BOOT}/efi ${BOOT}/loader
mkdir -p ${BOOT}/efi/EFI
mkdir -p ${BOOT}/loader/entries
bootctl --esp-path=${BOOT}/efi --path=${BOOT} install
DEVICE_ID=`blkid -o export ${ROOT_PART} | grep '^PARTUUID' | sed -e "s/PARTUUID=//g"`
echo ${DEVICE_ID}
cat <<EOF >${BOOT}/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen.img
options root=PARTUUID=${DEVICE_ID} rw acpi_osi=! acpi_osi="Windows 2009" acpi_backlight=native acpi.ec_no_wakeup=1 iommu=force,merge,nopanic,nopt intel_iommu=on nvidia-drm.modeset=1 amd_iommu=on swiotlb=noforce resume=${SWAP_PART} quiet loglevel=1 rd.systemd.show_status=auto rd.udev.log_priority=3 zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4 i8042.reset=1 i8042.nomux=1 psmouse.synaptics_intertouch=1 psmouse.elantech_smbus=0 nowatchdog
EOF

rm -rf ${BOOT}/loader/loader.conf
cat <<EOF >${BOOT}/loader/loader.conf
default arch
timeout 0
editor no
auto-entries 0
auto-firmware 0
console-mode max
EOF
bootctl update
bootctl list

# mkdir -p /etc/pacman.d/hooks
# ln -sfv /usr/share/doc/fwupdate/esp-as-boot.hook /etc/pacman.d/hooks/fwupdate-efi-copy.hook

sed -i -e "s/#HandleLidSwitch/HandleLidSwitch/g" /etc/systemd/logind.conf
mkdir -p /go/src/github.com/kpango
cd /go/src/github.com/kpango && git clone --depth 1 https://github.com/kpango/dotfiles
ln -sfv /go ${HOME}/go
chmod -R 755 ${HOME}
chown -R $LOGIN_USER:wheel ${HOME}
chmod -R 755 /go
chown -R $LOGIN_USER:wheel /go
