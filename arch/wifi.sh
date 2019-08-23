nmcli d
nmcli radio wifi
nmcli device wifi list
sudo nmcli c add type wifi ifname $(nmcli d | grep wifi | head -1 | awk '{print $1}') con-name $1 ssid $1
sudo nmcli c mod $1 connection.autoconnect yes
sudo nmcli c mod $1 wifi-sec.key-mgmt wpa-psk
sudo nmcli c mod $1 wifi-sec.psk-flags 0
sudo nmcli c mod $1 wifi-sec.psk $2
nmcli c up $1
