#!/bin/sh
reflector --verbose --latest 200 --number 10 --sort rate --save /etc/pacman.d/mirrorlist
sed -i -e "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -T 0 -c -z -)/g" /etc/makepkg.conf
sed -i -e "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j9\"/g" /etc/makepkg.conf
sed -i -e "s/#Color/Color/g" /etc/pacman.conf
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
cd ../
rm -r yay

pacman -Rs go

yay -S alsa-utils \
    axel \
    chrome-remote-desktop \
    discord \
    dkms \
    exa-git \
    ghq \
    i3-wm \
    i3status \
    lib32-nvidia-utils \
    lightdm \
    lightdm-webkit2-greeter \
    lm_sensors \
    nerd-fonts-ricty \
    nodejs \
    pavucontrol \
    pulseaudio \
    ripgrep-git \
    rofi \
    slack-desktop \
    systemd-boot-pacman-hook \
    thefuck \
    ttf-hackgen \
    ttf-symbola \
    urxvt-perls \
    urxvt-resize-font-git \
    volumeicon \
    xorg-server \
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
sed -i -e "s/greeter-session.*/greeter-session=lightdm-webkit2-greeter/g" /etc/lightdm/lightdm.conf
ln -sfv /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
locale-gen
hwclock --systohc --localtime
echo LANG=en_US.UTF-8 >>/etc/locale.conf

fallocate -l 16G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
SWAP_UUID=`blkid /swapfile | awk '{print $2}' | sed "s/\"//g"`
echo "${SWAP_UUID}\t/swapfile\tnone\tswap\tdefaults,noatime 0 0" | tee -a /etc/fstab
SWAP_PHYS_OFFSET=`filefrag -v /swapfile | head -n 5 | grep "0:" | awk '{print $4}' | sed "s/\.\.//g"`

passwd
systemctl enable ntpd
systemctl start ntpd
systemctl enable docker
systemctl enable lightdm
systemctl enable NetworkManager
systemctl enable fstrim.timer

LOGIN_USER=kpango
sed -i -e "s/#DNS=/DNS=1.1.1.1 9.9.9.10 8.8.8.8 8.8.4.4/g" /etc/systemd/resolved.conf
sed -i -e "s/#FallbackDNS=/FallbackDNS/g" /etc/systemd/resolved.conf

function groupadd() {
    if [ !`getent group $1` ]; then
        groupadd $@
    fi
}
groupadd kpango
groupadd sshd
groupadd autologin
groupadd pulse
groupadd pulse-access

useradd -m -g users -G wheel,${LOGIN_USER},docker,sshd,storage,power,autologin,audio,pulse,pulse-access -s /usr/bin/zsh ${LOGIN_USER}
passwd ${LOGIN_USER}
visudo
mkdir -p /go/src/github.com/kpango/
cd /go/src/github.com/kpango/ && git clone https://github.com/kpango/doftiles && cd -
cd /go/src/github.com/kpango/dotfiles && USER=kpango make link && make arch_link && cd -

mkdir -p /boot/efi/EFI
bootctl --path=/boot install
DEVICE_ID=`lsblk -f | grep p2 | awk '{print $3}'`
echo ${DEVICE_ID}
cat <<EOF >/boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=UUID=${DEVICE_ID} rw resume=/dev/nvme0n1p2 quiet loglevel=3 rd.systemd.show_status=auto rd.udev.log_priority=3 resume_offset=${SWAP_PHYS_OFFSET} zswap.enabled=1 zswap.max_pool_percent=25 zswap.compressor=lz4
EOF
rm -rf /boot/loader/loader.conf
cat <<EOF >/boot/loader/loader.conf
default arch
timeout 1
editor no
EOF
bootctl update
bootctl list

sed -i -e "s/MODULES=()/MODULES=(lz4 lz4_compress)/g" /etc/mkinitcpio.conf
sed -i -e "s/block filesystems/block resume filesystems/g" /etc/mkinitcpio.conf
mkinitcpio -p linux

