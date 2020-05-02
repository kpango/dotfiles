#!/bin/sh

swapoff --all
rm -rf /var/swap
pacman-key --init
pacman-key --populate archlinuxarm
pacman -Sy dropbear chronyd docker

ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >>/etc/locale.conf
timedatectl set-timezone Asia/Tokyo

LOGIN_USER=kpango

groupadd ${LOGIN_USER}
groupadd sshd
groupadd autologin
groupadd input
groupadd uinput
groupadd pulse
groupadd pulse-access

useradd -m -g users -G wheel,users,${LOGIN_USER},docker,sshd,storage,power,autologin,audio,pulse,pulse-access,input,uinput -s /usr/bin/zsh ${LOGIN_USER}
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
