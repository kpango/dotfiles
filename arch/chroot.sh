#!/bin/sh
reflector --latest 200 --number 10 --sort rate --save /etc/pacman.d/mirrorlist
sed -i -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -T 0 -c -z -)/g" /etc/makepkg.conf
sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j9\"/g" /etc/makepkg.conf
sed -i -e "s/#Color/Color/g" /etc/pacman.conf
echo "blacklist pcspkr" > /etc/modprobe.d/nobeep.conf
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd -
rm -r yay

pacman -Rs go

yay -Syu --noconfirm \
    alsa-utils \
    axel \
    chrome-remote-desktop \
    discord \
    dunst \
    dkms \
    exa \
    feh \
    ghq \
    i3-gaps \
    py3status \
    fwupd \
    kazam \
    lib32-nvidia-utils \
    lightdm \
    lightdm-locker
    lightdm-webkit2-greeter \
    lightdm-webkit-theme-aether \
    lm_sensors \
    nerd-fonts-ricty \
    nodejs \
    pavucontrol \
    pulseaudio \
    bluez \
    bluez-utils \
    pulseaudio-bluetooth
    ripgrep \
    rofi \
    slack-desktop \
    systemd-boot-pacman-hook \
    thefuck \
    ttf-ricty \
    ttf-symbola \
    urxvt-perls \
    urxvt-resize-font-git \
    volumeicon \
    xkeysnail \
    xorg-server \
    xorg-xbacklight \
    xorg-xrandr \
    w3m \
    yarn
# wlroots-git \
# sway-git \
# waybar-git \

fc-cache -f -v

HOST="archpango"
echo archpango >>/etc/hostname
cat <<EOF >/etc/hosts
127.0.0.1 localhost.localdomain localhost.local localhost ${HOST}.localdomain ${HOST}.local ${HOST}
::1 localhost.localdomain localhost ${HOST}.localdomain ${HOST}.local ${HOST}
EOF
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >>/etc/locale.conf

fallocate -l 24G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile     	none    	swap    	defaults,noatime    	0 0" | tee -a /etc/fstab
SWAP_PHYS_OFFSET=`filefrag -v /swapfile | head -n 5 | grep "0:" | awk '{print $4}' | sed "s/\.\.//g"`


sed -i -e "s/#DNS=/DNS=1.1.1.1 9.9.9.10 8.8.8.8 8.8.4.4/g" /etc/systemd/resolved.conf
sed -i -e "s/#FallbackDNS=/FallbackDNS/g" /etc/systemd/resolved.conf

function groupadd() {
    if [ !`getent group $1` ]; then
        groupadd $@
    fi
}

LOGIN_USER=kpango

groupadd ${LOGIN_USER}
groupadd sshd
groupadd autologin
groupadd input
groupadd uinput
groupadd pulse
groupadd pulse-access

useradd -m -g users -G wheel,${LOGIN_USER},docker,sshd,storage,power,autologin,audio,pulse,pulse-access,input,uinput -s /usr/bin/zsh ${LOGIN_USER}
passwd ${LOGIN_USER}
visudo

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

passwd
mkdir -p /go/src/github.com/kpango/
cd /go/src/github.com/kpango/ && git clone https://github.com/kpango/doftiles && cd -
cd /go/src/github.com/kpango/dotfiles && USER=${LOGIN_USER} make arch_link && cd -
ln -sfv /home/${LOGIN_USER}/.config /root/.config

systemctl enable ntpd
systemctl start ntpd
systemctl enable docker
systemctl enable lightdm
systemctl enable NetworkManager
systemctl enable fstrim.timer

mkdir -p /boot/efi/EFI
bootctl --path=/boot install
DEVICE_ID=`lsblk -f | grep p2 | awk '{print $3}'`
echo ${DEVICE_ID}
cat <<EOF >/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /cpu_manufacturer-ucode.img
initrd  /initramfs-linux.img
options root=UUID=${DEVICE_ID} rw resume=/dev/nvme0n1p2 quiet loglevel=1 rd.systemd.show_status=auto rd.udev.log_priority=3 resume_offset=${SWAP_PHYS_OFFSET} zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4 psmouse.synaptics_intertouch=1
EOF
rm -rf /boot/loader/loader.conf
cat <<EOF >/boot/loader/loader.conf
default arch
timeout 0
editor no
EOF
bootctl update
bootctl list
ln -sfv /usr/share/doc/fwupdate/esp-as-boot.hook /etc/pacman.d/hooks/fwupdate-efi-copy.hook

sed -i -e "s/#HandleLidSwitch/HandleLidSwitch/g" /etc/systemd/logind.conf
sed -i -e "s/MODULES=()/MODULES=(lz4 lz4_compress)/g" /etc/mkinitcpio.conf
sed -i -e "s/block filesystems/block resume filesystems/g" /etc/mkinitcpio.conf
mkinitcpio -p linux

