if (($+commands[compton])); then
	comprestart() {
		sudo pkill compton
		compton --config $HOME/.config/compton/compton.conf --xrender-sync-fence -cb
	}
fi
if (($+commands[bumblebeed])); then
	discrete() {
		killall Xorg
		modprobe nvidia_drm
		modprobe nvidia_modeset
		modprobe nvidia
		tee /proc/acpi/bbswitch <<<ON
		cp /etc/X11/xorg.conf.nvidia /etc/X11/xorg.conf
	}
	integrated() {
		killall Xorg
		rmmod nvidia_drm
		rmmod nvidia_modeset
		rmmod nvidia
		tee /proc/acpi/bbswitch <<<OFF
		cp /etc/X11/xorg.conf.intel /etc/X11/xorg.conf
	}
fi
if (($+commands[systemctl])); then
	alias checkkm="sudo systemctl status systemd-modules-load.service"
fi
if (($+commands[sway])); then
	set_swaysock() {
		export SWAYSOCK=/run/user/$UID/sway-ipc.$UID.$(pgrep -x sway).sock
	}
fi
if (($+commands[chrome])); then
	alias chrome="chrome --audio-buffer-size=4096"
fi
if (($+commands[fwupdtool])); then
	fup() {
		sudo systemctl reload dbus.service
		sudo systemctl restart fwupd.service
		sudo lsusb
		sudo fwupdtool get-devices
		sudo fwupdtool clear-history
		sudo fwupdtool clear-offline
		sudo fwupdtool refresh --force
		sudo fwupdtool get-updates --force
		sudo fwupdtool get-upgrades --force
		sudo fwupdtool update
	}
fi
