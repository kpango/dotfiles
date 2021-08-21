#!/bin/sh
sed -i -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -T 0 -c -z -)/g" /etc/makepkg.conf
sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j8\"/g" /etc/makepkg.conf
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

fallocate -l 24G /swapfile
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

groupmod -g 1000 -o users
useradd -m -o -u 1000 -g users -G wheel,users,${LOGIN_USER},docker,sshd,storage,power,autologin,audio,pulse,pulse-access,input,uinput -s /usr/bin/zsh ${LOGIN_USER}
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

sed -i -e "s/MODULES=()/MODULES=(lz4 lz4_compress zstd)/g" /etc/mkinitcpio.conf
sed -i -e "s/block filesystems/block resume filesystems/g" /etc/mkinitcpio.conf

mkinitcpio -p linux-zen

mkdir -p /boot/efi/EFI
bootctl --path=/boot install
DEVICE_ID=`lsblk -f | grep p2 | awk '{print $3}'`
echo ${DEVICE_ID}
cat <<EOF >/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux-zen
initrd  /intel-ucode.img
initrd  /initramfs-linux-zen.img
options root=UUID=${DEVICE_ID} rw resume=/dev/nvme0n1p2 quiet loglevel=1 rd.systemd.show_status=auto rd.udev.log_priority=3 resume_offset=${SWAP_PHYS_OFFSET} zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4 psmouse.synaptics_intertouch=1 iommu=force,merge,nopanic,nopt intel_iommu=on nowatchdog
EOF
# options root=UUID=${DEVICE_ID} rw resume=/dev/nvme0n1p2 quiet loglevel=1 rd.systemd.show_status=auto rd.udev.log_priority=3 resume_offset=${SWAP_PHYS_OFFSET} zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4 psmouse.synaptics_intertouch=1 iommu=force,merge,nopanic,nopt intel_iommu=on i915.enable_psr=0 i915.enable_fbc=1 i915.fastboot=1 i915.semaphores=1 i915.enable_rc6=0 nowatchdog
# EOF

rm -rf /boot/loader/loader.conf
cat <<EOF >/boot/loader/loader.conf
default arch
timeout 0
editor no
auto-entries 0
auto-firmware 0
console-mode max
EOF
bootctl update
bootctl list

mkdir -p /etc/pacman.d/hooks
ln -sfv /usr/share/doc/fwupdate/esp-as-boot.hook /etc/pacman.d/hooks/fwupdate-efi-copy.hook

sed -i -e "s/#HandleLidSwitch/HandleLidSwitch/g" /etc/systemd/logind.conf
mkdir -p /go/src/github.com/kpango
cd /go/src/github.com/kpango && git clone --depth 1 https://github.com/kpango/dotfiles
ln -sfv /go /home/${LOGIN_USER}/go
chmod -R 755 /home/${LOGIN_USER}
chown -R $LOGIN_USER:wheel /home/${LOGIN_USER}
chmod -R 755 /go
chown -R $LOGIN_USER:wheel /go
