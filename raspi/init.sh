#!/bin/sh

swapoff --all
rm -rf /var/swap
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Syu --noconfirm
pacman -Sy --noconfirm archlinux-keyring
pacman -Sy --noconfirm autoconf
pacman -Sy --noconfirm automake
pacman -Sy --noconfirm axel
pacman -Sy --noconfirm base-devel
pacman -Sy --noconfirm chrony
pacman -Sy --noconfirm clang
pacman -Sy --noconfirm cmake
pacman -Sy --noconfirm dnsmasq
pacman -Sy --noconfirm docker
pacman -Sy --noconfirm dosfstools
pacman -Sy --noconfirm dropbear
pacman -Sy --noconfirm exa
pacman -Sy --noconfirm fakeroot
pacman -Sy --noconfirm fd
pacman -Sy --noconfirm fwupd
pacman -Sy --noconfirm git
pacman -Sy --noconfirm gzip
pacman -Sy --noconfirm htop
pacman -Sy --noconfirm inetutils
pacman -Sy --noconfirm less
pacman -Sy --noconfirm linux
pacman -Sy --noconfirm linux-firmware
pacman -Sy --noconfirm lshw
pacman -Sy --noconfirm lsof
pacman -Sy --noconfirm make
pacman -Sy --noconfirm mkinitcpio-netconf
pacman -Sy --noconfirm mkinitcpio-utils
pacman -Sy --noconfirm neovim
pacman -Sy --noconfirm nmap
pacman -Sy --noconfirm pacman-contrib
pacman -Sy --noconfirm parted
pacman -Sy --noconfirm pkgconf
pacman -Sy --noconfirm powertop
pacman -Sy --noconfirm ranger
pacman -Sy --noconfirm ripgrep
pacman -Sy --noconfirm rsync
pacman -Sy --noconfirm sed
pacman -Sy --noconfirm sudo
pacman -Sy --noconfirm sysfsutils
pacman -Sy --noconfirm systemd
pacman -Sy --noconfirm systemd-sysvcompat
pacman -Sy --noconfirm tar
pacman -Sy --noconfirm thefuck
pacman -Sy --noconfirm tig
pacman -Sy --noconfirm tmux
pacman -Sy --noconfirm unzip
pacman -Sy --noconfirm usbutils
pacman -Sy --noconfirm which
pacman -Sy --noconfirm xfsprogs
pacman -Sy --noconfirm zsh

ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >>/etc/locale.conf
timedatectl set-timezone Asia/Tokyo

LOGIN_USER=kpango

groupadd ${LOGIN_USER}
groupadd docker
groupadd sshd
groupadd autologin
groupadd storage
groupadd power
groupadd input
groupadd uinput

useradd -m -g users -G wheel,users,${LOGIN_USER},docker,sshd,storage,power,autologin,input,uinput -s /usr/bin/zsh ${LOGIN_USER}
passwd ${LOGIN_USER}
sed -e '/%wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers | EDITOR=tee visudo >/dev/null
sed -e '/%wheel ALL=(ALL) NOPASSWORD: ALL/s/^# %wheel/kpango/' /etc/sudoers | EDITOR=tee visudo >/dev/null
passwd

mkdir -p /home/${LOGIN_USER}/.zplug
mkdir -p /home/${LOGIN_USER}/.config

systemctl enable dropbear.service
sed -i -e "s%/run/dropbear.pid -R%/run/dropbear.pid -R -w -s%g" /usr/lib/systemd/system/dropbear.service
systemctl daemon-reload


chmod -R 755 /home/${LOGIN_USER}
chown -R $LOGIN_USER:wheel /home/${LOGIN_USER}

systemctl enable chronyd
systemctl start chronyd
systemctl enable docker
systemctl enable fstrim.timer

sed -i -e "s/MODULES=()/MODULES=(lz4 lz4_compress g_cdc usb_f_acm usb_f_ecm smsc95xx g_ether)/g" /etc/mkinitcpio.conf
sed -i -e "s/block filesystems/block sleep netconf dropbear encryptssh resume filesystems/g" /etc/mkinitcpio.conf
sed -i -e "s/#HandleLidSwitch/HandleLidSwitch/g" /etc/systemd/logind.conf
mkinitcpio -P
