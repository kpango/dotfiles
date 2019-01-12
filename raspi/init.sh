# !/bin/sh

# OS install function
function rpwrite(){
	sudo diskutil umount $1 && sudo diskutil unMountDisk /dev/disk2 && sudo diskutil eraseDisk FAT32 RASPBIAN MBRFormat /dev/disk2 && sudo diskutil umount /Volumes/RASPBIAN && sudo dd bs=4m if=$HOME/Downloads/rasbian.img of=/dev/rdisk2 && sync && sleep 3 && touch /Volumes/boot/ssh
}
sudo -s
sudo apt-get purge wolfram-engine
sudo apt-get purge sonic-pi
sudo apt-get purge scrach*
sudo apt-get purge libreoffice*
sudo apt-get clean
sudo apt-get autoremove

sudo swapoff --all
sudo apt-get purge -y --auto-remove dphys-swapfile
sudo rm -rf /var/swap
free -mh

sudo apt-get update
sudo apt-get upgrade


# Update repos
sudo apt update

# Packages to remove
DOCS="man manpages libraspberrypi-doc debian-reference-en debian-reference-common"
GCC="gcc-4.5-base:armhf gcc-4.6-base:armhf gcc-4.7-base:armhf"
DEV=`sudo dpkg --get-selections | grep "\-dev" | grep -v "deinstall" | sed s/install//`
SOUND="omxplayer "`sudo dpkg --get-selections | grep -v "deinstall" | grep sound | sed s/install//`
PYTHON=`sudo dpkg --get-selections | grep -v "deinstall" | grep python | sed s/install//`
JAVA="java-common oracle-java7-jdk oracle-java8-jdk"
LEARNING="scratch squeak-vm squeak-plugins-scratch supercollider sonic-pi wolfram-engine"

# Purge packages
sudo apt purge -y $DOCS $GCC $DEV $SOUND $PYTHON $JAVA $LEARNING
sudo rm -rf /usr/local/games/
sudo rm -rf /usr/games/

# Autoremove
sudo apt autoremove -y
# Upgrade packages and distribution
sudo apt upgrade -y
sudo apt dist-upgrade -y
# Clean archive files
sudo apt clean -y

# Update firmwares
sudo apt install -y rpi-update
sudo rpi-update

# Clear logs
cd /var/log/
sudo rm `find . -type f`
history -c

echo "change root password"
sudo passwd root

echo "add kpango user"
sudo adduser kpango
sudo usermod -aG adm,dialout,cdrom,sudo,audio,video,plugdev,games,users,input,netdev,spi,i2c,gpio kpango


sudo apt install -y chkconfig
sudo chkconfig triggerhappy off
sudo chkconfig alsa-utils off
sudo chkconfig plymouth off
sudo apt install ntp
sudo cat <<EOF > /etc/ntp.conf
# pool 0.debian.pool.ntp.org iburst
# pool 1.debian.pool.ntp.org iburst
# pool 2.debian.pool.ntp.org iburst
# pool 3.debian.pool.ntp.org iburst
pool ntp.jst.mfeed.ad.jp
pool ntp.nict.jp iburst
EOF
sudo service ntp restart
