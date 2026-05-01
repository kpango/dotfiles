.PHONY: arch_link arch_copy arch_p1_link arch_p1_copy arch_desk_link arch_desk_copy

define ARCH_LINK_MAP
arch/fcitx.classicui.conf .config/fcitx5/conf/classicui.conf
arch/fcitx.conf .config/fcitx5/config
arch/fcitx.profile .config/fcitx5/profile
arch/kanshi.conf .config/kanshi/config
arch/psd.conf .config/psd/psd.conf
arch/ranger .config/ranger
arch/sway.conf .config/sway/config
arch/xdg-desktop-portal.conf .config/xdg-desktop-portal/portals.conf
arch/waybar.css .config/waybar/style.css
arch/waybar.json .config/waybar/config
arch/wofi/style.css .config/wofi/style.css
arch/wofi/wofi.conf .config/wofi/config
arch/workstyle.toml .config/workstyle/config.toml
arch/Xmodmap .Xmodmap
endef
export ARCH_LINK_MAP

define ARCH_SUDO_LINK_MAP
arch/60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules
arch/default.pa /etc/pulse/default.pa
arch/limits.conf /etc/security/limits.conf
arch/makepkg.conf /etc/makepkg.conf
arch/modules-load.d/bbr.conf /etc/modules-load.d/bbr.conf
arch/modules-load.d/nf_conntrack.conf /etc/modules-load.d/nf_conntrack.conf
arch/pacman.conf /etc/pacman.conf
arch/sway.sh /etc/profile.d/sway.sh
arch/thinkfan.conf /etc/thinkfan.conf
arch/tlp /etc/default/tlp
arch/tlp /etc/tlp.conf
dockers/config.json /root/.docker/config.json
dockers/daemon.json /root/.docker/daemon.json
network/dns/dnsmasq.conf /etc/NetworkManager/dnsmasq.d/dnsmasq.conf
network/nm/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
network/dns/resolv.dnsmasq.conf /etc/resolv.dnsmasq.conf
network/dns/resolv.dnsmasq.conf /etc/resolv.pre-tailscale-backup.conf
network/sysctl/sysctl.conf /etc/sysctl.d/99-sysctl.conf
arch/ghostty.desktop /usr/share/applications/com.mitchellh.ghostty.desktop
arch/mkinitcpio.conf /etc/mkinitcpio.conf
arch/mkinitcpio/linux.preset /etc/mkinitcpio.d/linux.preset
arch/mkinitcpio/linux-zen.preset /etc/mkinitcpio.d/linux-zen.preset
arch/systemd/NetworkManager.service.d/capabilities.conf /etc/systemd/system/NetworkManager.service.d/capabilities.conf
endef
export ARCH_SUDO_LINK_MAP

define ARCH_SUDO_CP_MAP
arch/chrony.conf /etc/chrony.conf
arch/suduers /etc/sudoers.d/$(SYS_USER)
arch/environment /etc/environment
network/nm/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
network/nm/nmcli-bond-auto-connect.sh /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
endef
export ARCH_SUDO_CP_MAP

define ARCH_DESK_SUDO_LINK_MAP
arch/loader/entries/arch.conf /boot/loader/entries/arch.conf
arch/modprobe.d/blacklist-nouveau.conf /etc/modprobe.d/blacklist-nouveau.conf
arch/modprobe.d/nowatchdog.conf /etc/modprobe.d/nowatchdog.conf
arch/modprobe.d/thinkfan-desk.conf /etc/modprobe.d/thinkfan.conf
arch/systemd/nvidia-unload.service /etc/systemd/system/nvidia-unload.service
arch/tmpfiles.d/thp.conf /etc/tmpfiles.d/thp.conf
endef
export ARCH_DESK_SUDO_LINK_MAP

define ARCH_PREP
	sudo mkdir -p /etc/systemd/system/NetworkManager.service.d
	mkdir -p $(HOME)/.config/fcitx5/conf
	mkdir -p $(HOME)/.config/kanshi
	mkdir -p $(HOME)/.config/psd
	mkdir -p $(HOME)/.config/sway
	mkdir -p $(HOME)/.config/xdg-desktop-portal
	mkdir -p $(HOME)/.config/waybar
	mkdir -p $(HOME)/.config/wofi
	mkdir -p $(HOME)/.config/workstyle
	sudo mkdir -p /etc/modules-load.d/
	sudo mkdir -p /etc/udev/rules.d
	sudo mkdir -p /root/.docker
endef

define ARCH_POST
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo chown root:root /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
	sudo chown root:root /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
	sudo chown -R 0:0 /etc/sudoers.d
	sudo chmod -R 0440 /etc/sudoers.d
	sudo chown -R 0:0 /etc/sudoers.d/$(SYS_USER)
	sudo chmod -R 0440 /etc/sudoers.d/$(SYS_USER)
	sudo sysctl -e -p /etc/sysctl.d/99-sysctl.conf
	sudo systemctl daemon-reload
endef

define ARCH_P1_POST
	rm -rf $(HOME)/.config/psd
	mkdir $(HOME)/.config/psd
	sudo systemctl daemon-reload
endef

define ARCH_DESK_POST
	sudo mkdir -p /etc/systemd/system/irqbalance.service.d
	sudo rm -rf /etc/systemd/system/irqbalance.service.d/override.conf
	sudo cp $(ROOTDIR)/arch/service/irqbalance.service /etc/systemd/system/irqbalance.service.d/override.conf
	sudo rm -rf /etc/NetworkManager/system-connections
	sudo mkdir -p /etc/NetworkManager/system-connections
	sudo cp $(ROOTDIR)/network/nm/desk/bond0.nmconnection /etc/NetworkManager/system-connections/bond0.nmconnection
	sudo cp $(ROOTDIR)/network/nm/desk/eth0.nmconnection /etc/NetworkManager/system-connections/eth0.nmconnection
	sudo cp $(ROOTDIR)/network/nm/desk/slave0.nmconnection /etc/NetworkManager/system-connections/slave0.nmconnection
	sudo cp $(ROOTDIR)/network/nm/desk/slave1.nmconnection /etc/NetworkManager/system-connections/slave1.nmconnection
	sudo chmod -R 600 /etc/NetworkManager/system-connections
	sudo chown -R root:root /etc/NetworkManager/system-connections
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	sudo nmcli connection reload
	sudo systemctl daemon-reload
	sudo systemctl enable nvidia-unload.service
	sudo systemctl restart NetworkManager
	sudo systemd-tmpfiles --create /etc/tmpfiles.d/thp.conf
endef

arch_link: \
	clean \
	link
	$(ARCH_PREP)
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		ln -sfv "$(ROOTDIR)/$$src" "$(HOME)/$$dest"; \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo ln -sfv "$(ROOTDIR)/$$src" "$$dest"; \
	done
	$(ARCH_POST)

arch_copy: \
	clean \
	copy
	$(ARCH_PREP)
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		cp -r "$(ROOTDIR)/$$src" "$(HOME)/$$dest"; \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
	done
	$(ARCH_POST)

arch_p1_link: \
	arch_link
	rm -rf $(HOME)/.config/waybar/style.css
	ln -sfv $(ROOTDIR)/arch/waybar_p1.css $(HOME)/.config/waybar/style.css
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-tweaks.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	$(ARCH_P1_POST)

arch_p1_copy: \
	arch_copy
	rm -rf $(HOME)/.config/waybar/style.css
	cp $(ROOTDIR)/arch/waybar_p1.css $(HOME)/.config/waybar/style.css
	sudo cp $(ROOTDIR)/nvidia/nvidia-tweaks.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo cp $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo cp $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	$(ARCH_P1_POST)

arch_desk_link: \
	arch_link
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-tweaks.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	sudo ln -sfv $(ROOTDIR)/network/nm/desk/70-persistent-network.rules /etc/udev/rules.d/70-persistent-network.rules
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo ln -sfv "$(ROOTDIR)/$$src" "$$dest"; \
	done
	$(ARCH_DESK_POST)

arch_desk_copy: \
	arch_copy
	sudo cp $(ROOTDIR)/nvidia/nvidia-tweaks.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo cp $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo cp $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	sudo cp $(ROOTDIR)/network/nm/desk/70-persistent-network.rules /etc/udev/rules.d/70-persistent-network.rules
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
	done
	$(ARCH_DESK_POST)