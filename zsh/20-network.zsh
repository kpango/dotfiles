if (($+commands[nmcli])); then
	_nmcli_refresh() {
		nmcli d
		nmcli r wifi
		nmcli d wifi list
	}

	_get_wifi_ifname() {
		nmcli d | grep wifi | head -1 | awk '{print $1}'
	}

	nmcliwifie() {
		if [ $# -eq 3 ]; then
			sudo nmcli c delete $1
			_nmcli_refresh
			sudo nmcli c add type wifi ifname "$(_get_wifi_ifname)" con-name $1 ssid $1 -- \
				connection.autoconnect yes \
				ipv4.method auto \
				802-11-wireless.ssid $1 \
				802-11-wireless-security.key-mgmt wpa-eap \
				802-1x.eap peap \
				802-1x.anonymous-identity $2 \
				802-1x.identity $2 \
				802-1x.password $3 \
				802-1x.phase2-auth mschapv2
			sudo nmcli c up $1
		else
			echo "invalid argument, SSID and PSK is required"
		fi
	}
	nmcliwifi() {
		if [ $# -eq 2 ]; then
			SSID=$1
			PSK=$2

			SECURITY=$(nmcli -f SSID,SECURITY dev wifi | grep "$SSID" | awk '{print $2}')
			KEY_MGMT="wpa-psk"
			if [[ "$SECURITY" == *"WPA3"* ]]; then
				KEY_MGMT="sae"
			elif [[ "$SECURITY" == *"WPA2"* ]]; then
				KEY_MGMT="wpa-psk"
			fi
			sudo nmcli c delete "$SSID"
			_nmcli_refresh
			sudo nmcli c add type wifi ifname "$(_get_wifi_ifname)" con-name "$SSID" ssid "$SSID" -- \
				connection.autoconnect yes \
				ipv4.method auto \
				802-11-wireless.ssid "$SSID" \
				802-11-wireless-security.key-mgmt "$KEY_MGMT" \
				802-11-wireless-security.psk-flags 0 \
				802-11-wireless-security.psk "$PSK"
			sudo nmcli c up "$SSID"
		else
			echo "invalid argument, SSID and PSK is required"
		fi
	}
	nmclr() {
		if [ $# -eq 1 ]; then
			_nmcli_refresh
			nmcli c show
			sudo nmcli c down $1
			sudo nmcli r wifi off
			sudo nmcli r wifi on
			sudo nmcli c up $1
		else
			echo "invalid argument, SSID and PSK is required"
		fi
	}
fi
if (($+commands[osascript])); then
	ciscovpn() {
		osascript $DOTFILES_DIR/macos/AnyConnect.scpt
	}
fi
if (($+commands[whois])); then
	TRACECMD="traceroute"
	TRACE_ARGS=""
	if (($+commands[mtr])); then
		TRACECMD="mtr"
		TRACE_ARGS="-wbc 4"
	fi
	checkcountry() {
		if [ $# -eq 1 ]; then
			echo "$TRACECMD $TRACE_ARGS $1"
			sudo $TRACECMD $TRACE_ARGS $1 |
				rg -wo -e '[0-9]+(\.[0-9]+){3}' |
				xargs -I {} whois {} |
				rg -i country |
				awk '{print $(NF)}' |
				sort | uniq
		else
			echo "invalid argument, Domain or IP is required"
		fi
	}
	alias ccnt=checkcountry
fi
if (($+commands[wakeonlan])); then
	alias p1up="wakeonlan -p 9 -i 10.0.0.255 48:2a:e3:8c:80:90"
	alias trup="wakeonlan -p 9 -i 10.0.0.255 f0:2f:74:d4:37:35"
fi
if (($+commands[tailscale])); then
	tailscaleup() {
		local tailscale="$commands[tailscale]"
		sudo "$tailscale" "down"
		sudo "$tailscale" "up" "$@"
	}
	if (($+commands[ubnt-systool])); then
		export PATH=/usr/lib/unifi/bin:/usr/share/sensible-utils/bin:/usr/share/ubios-udapi-server/ips/bin:/usr/share/ubios-udapi-server/utm/bin:/usr/share/unifi-core/bin:$PATH
		alias tailup="tailscaleup --ssh --reset --advertise-exit-node --advertise-routes=10.0.0.0/24,10.0.1.0/29 --stateful-filtering"
	else
		case ${OSTYPE} in
		darwin*)
			alias tailup="tailscaleup --reset --accept-routes"
			;;
		linux*)
			alias tailup="tailscaleup --ssh --reset --accept-routes --stateful-filtering"
			;;
		esac
	fi
fi

if (($+commands[rg])); then
	if (($+commands[curl])); then
		listdomains() {
			if [ $# -eq 1 ]; then
				curl --retry 3 --retry-all-errors --retry-delay 3 -fs $1 |
					rg -Po '.*?//\K.*?(?=/)' |
					rg -v "@" |
					rg -v "\+" |
					sort | uniq
			else
				echo "invalid argument, Domain or url is required"
			fi
		}
		alias lsdomain=listdomains
	fi
fi

if (($+commands[axel])); then
	alias wget='axel -a -n 10'
else
	alias wget='wget --no-cookies --no-check-certificate --no-dns-cache -4'
fi

if (($+commands[trans])); then
	alias gtrans='trans -b -e google'
fi
