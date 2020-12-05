#!/bin/sh
sed -i -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -T 0 -c -z -)/g" /etc/makepkg.conf
sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j9\"/g" /etc/makepkg.conf
sed -i -e "s/#BUILDDIR/BUILDDIR/g" /etc/makepkg.conf
sed -i -e "s/#Color/Color\nILoveCandy/g" /etc/pacman.conf
cat <<EOF >>/etc/pacman.conf

[multilib]
Include = /etc/pacman.d/mirrorlist
EOF
echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf

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
fallocate -l 72G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile     	none    	swap    	defaults,noatime    	0 0" | tee -a /etc/fstab
SWAP_PHYS_OFFSET=`filefrag -v /swapfile | grep "0:" | head -1 | awk '{print $4}' | sed "s/\.\.//g"`

sed -i -e "s/#DNS=/DNS=1.1.1.1 9.9.9.10 8.8.8.8 8.8.4.4/g" /etc/systemd/resolved.conf
sed -i -e "s/#FallbackDNS=/FallbackDNS/g" /etc/systemd/resolved.conf

LOGIN_USER=kpango

groupadd ${LOGIN_USER}
groupadd sshd
groupadd autologin
groupadd input
groupadd uinput
groupadd pulse
groupadd pulse-access
groupadd bumblebee

useradd -m -g users -G wheel,users,${LOGIN_USER},docker,sshd,storage,power,autologin,audio,pulse,pulse-access,input,bumblebee,uinput -s /usr/bin/zsh ${LOGIN_USER}
passwd ${LOGIN_USER}
sed -e '/%wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers | EDITOR=tee visudo >/dev/null
sed -e '/%wheel ALL=(ALL) NOPASSWORD: ALL/s/^# %wheel/kpango/' /etc/sudoers | EDITOR=tee visudo >/dev/null
passwd

mkdir -p /home/${LOGIN_USER}/.zplug
mkdir -p /home/${LOGIN_USER}/.config

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
systemctl enable tlp

sed -i -e "s/MODULES=()/MODULES=(battery lz4 lz4_compress i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /etc/mkinitcpio.conf
sed -i -e "s/BINARIES=()/BINARIES=(\"\/usr\/bin\/mdmon\")/g" /etc/mkinitcpio.conf
sed -i -e "s/block filesystems/block resume mdadm_udev filesystems/g" /etc/mkinitcpio.conf

mkinitcpio -p linux

mkdir -p /boot/efi/EFI
DEVICE_ID=`blkid -o export /dev/md0p1 | grep '^PARTUUID' | sed -e "s/PARTUUID=//g"`
echo ${DEVICE_ID}
bootctl --path=/boot install
cat <<EOF >/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=${DEVICE_ID} rw acpi_osi=! acpi_osi="Windows 2009" acpi_backlight=native acpi.ec_no_wakeup=1 i915.enable_execlists=0 iommu=force,merge,nopanic,nopt intel_iommu=on nvidia-drm.modeset=1 amd_iommu=on swiotlb=noforce resume=/dev/md0p1 quiet loglevel=1 rd.systemd.show_status=auto rd.udev.log_priority=3 resume_offset=${SWAP_PHYS_OFFSET} zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4 i8042.reset=1 i8042.nomux=1 psmouse.synaptics_intertouch=1 psmouse.elantech_smbus=0
EOF
rm -rf /boot/loader/loader.conf
cat <<EOF >/boot/loader/loader.conf
default arch
timeout 0
editor no
EOF
bootctl update
bootctl list

mkdir -p /etc/pacman.d/hooks
ln -sfv /usr/share/doc/fwupdate/esp-as-boot.hook /etc/pacman.d/hooks/fwupdate-efi-copy.hook

sed -i -e "s/#HandleLidSwitch/HandleLidSwitch/g" /etc/systemd/logind.conf
mkdir -p /go/src/github.com/kpango
cd /go/src/github.com/kpango && git clone https://github.com/kpango/dotfiles
ln -sfv /go /home/${LOGIN_USER}/go
chmod -R 755 /home/${LOGIN_USER}
chown -R $LOGIN_USER:wheel /home/${LOGIN_USER}
chmod -R 755 /go
chown -R $LOGIN_USER:wheel /go
