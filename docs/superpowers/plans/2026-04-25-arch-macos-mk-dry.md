# Arch and macOS Makefiles DRY Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `Makefile.d/arch.mk` and `Makefile.d/macos.mk` to remove repetitious shell commands using Make maps and bash loops.

**Architecture:**

- In `arch.mk`, define `ARCH_LINK_MAP`, `ARCH_SUDO_LINK_MAP`, and `ARCH_SUDO_CP_MAP`. Update the `arch_link` target to loop over these.
- In `macos.mk`, define `MACOS_LAUNCH_AGENTS` and update `mac_link` to loop through them for `sudo` commands.

**Tech Stack:** GNU Make, Bash.

---

### Task 1: Add Maps and Update `arch_link` Target

**Files:**

- Modify: `Makefile.d/arch.mk`

- [ ] **Step 1: Replace arch.mk content**

Overwrite `Makefile.d/arch.mk` with the following content:

```makefile
define ARCH_LINK_MAP
arch/fcitx.classicui.conf .config/fcitx5/conf/classicui.conf
arch/fcitx.conf .config/fcitx5/config
arch/fcitx.profile .config/fcitx5/profile
arch/kanshi.conf .config/kanshi/config
arch/psd.conf .config/psd/psd.conf
arch/ranger .config/ranger
arch/sway.conf .config/sway/config
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
arch/pacman.conf /etc/pacman.conf
arch/sway.sh /etc/profile.d/sway.sh
arch/thinkfan.conf /etc/thinkfan.conf
arch/tlp /etc/default/tlp
arch/tlp /etc/tlp.conf
dockers/config.json /root/.docker/config.json
dockers/daemon.json /root/.docker/daemon.json
network/dnsmasq.conf /etc/NetworkManager/dnsmasq.d/dnsmasq.conf
network/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
network/resolv.dnsmasq.conf /etc/resolv.dnsmasq.conf
network/resolv.dnsmasq.conf /etc/resolv.pre-tailscale-backup.conf
network/sysctl.conf /etc/sysctl.d/99-sysctl.conf
arch/ghostty.desktop /usr/share/applications/com.mitchellh.ghostty.desktop
endef
export ARCH_SUDO_LINK_MAP

define ARCH_SUDO_CP_MAP
arch/chrony.conf /etc/chrony.conf
arch/suduers /etc/sudoers.d/$(SYS_USER)
arch/environment /etc/environment
network/NetworkManager-dispatcher.service /etc/systemd/system/NetworkManager-dispatcher.service
network/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
network/nmcli-bond-auto-connect.sh /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
endef
export ARCH_SUDO_CP_MAP

arch_link: \
	clean \
	link
	mkdir -p $(HOME)/.config/fcitx5/conf
	mkdir -p $(HOME)/.config/kanshi
	mkdir -p $(HOME)/.config/psd
	mkdir -p $(HOME)/.config/sway
	mkdir -p $(HOME)/.config/waybar
	mkdir -p $(HOME)/.config/wofi
	mkdir -p $(HOME)/.config/workstyle
	sudo mkdir -p /etc/modules-load.d/
	sudo mkdir -p /etc/udev/rules.d
	sudo mkdir -p /root/.docker
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
	sudo echo "options thinkpad_acpi fan_control=1" | sudo tee /etc/modprobe.d/thinkfan.conf
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

arch_p1_link: \
	arch_link
	rm -rf $(HOME)/.config/waybar/style.css
	ln -sfv $(ROOTDIR)/arch/waybar_p1.css $(HOME)/.config/waybar/style.css
	rm -rf $(HOME)/.config/psd
	mkdir $(HOME)/.config/psd
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-tweaks.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	sudo systemctl daemon-reload

arch_desk_link: \
	arch_link
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-tweaks.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	sudo ln -sfv $(ROOTDIR)/network/desk/70-persistent-network.rules /etc/udev/rules.d/70-persistent-network.rules
	sudo mkdir -p /etc/systemd/system/irqbalance.service.d
	sudo rm -rf /etc/systemd/system/irqbalance.service.d/override.conf
	sudo ln -sfv $(ROOTDIR)/arch/service/irqbalance.service /etc/systemd/system/irqbalance.service.d/override.conf
	sudo rm -rf /etc/NetworkManager/system-connections
	sudo mkdir -p /etc/NetworkManager/system-connections
	sudo cp $(ROOTDIR)/network/desk/bond0.nmconnection /etc/NetworkManager/system-connections/bond0.nmconnection
	sudo cp $(ROOTDIR)/network/desk/eth0.nmconnection /etc/NetworkManager/system-connections/eth0.nmconnection
	sudo cp $(ROOTDIR)/network/desk/slave0.nmconnection /etc/NetworkManager/system-connections/slave0.nmconnection
	sudo cp $(ROOTDIR)/network/desk/slave1.nmconnection /etc/NetworkManager/system-connections/slave1.nmconnection
	sudo chmod -R 600 /etc/NetworkManager/system-connections
	sudo chown -R root:root /etc/NetworkManager/system-connections
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	sudo nmcli connection reload
	sudo systemctl daemon-reload
	sudo systemctl restart NetworkManager
```

- [ ] **Step 2: Verify `make arch_link`**

Run: `make --dry-run arch_link`
Expected: Parses successfully without syntax errors.

- [ ] **Step 3: Commit**

```bash
git add Makefile.d/arch.mk
git commit -m "refactor: apply DRY map loop to Makefile.d/arch.mk"
```

---

### Task 2: Update `mac_link` Target in macos.mk

**Files:**

- Modify: `Makefile.d/macos.mk`

- [ ] **Step 1: Replace macos.mk content**

Overwrite `Makefile.d/macos.mk` with the following content:

```makefile
MACOS_LAUNCH_AGENTS = localhost.homebrew-autoupdate.plist ulimit.plist

mac_link: \
	link
	sudo rm -rf \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
		$(HOME)/.docker/config.json \
		$(HOME)/.docker/daemon.json \
		$(HOME)/.gnupg/gpg-agent.conf \
		$(HOME)/.tmux.conf \
		$(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist \
		$(HOME)/Library/LaunchAgents/ulimit.plist
	cp $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	cp $(ROOTDIR)/gpg-agent.conf $(HOME)/.gnupg/gpg-agent.conf
	sed -i.bak '/^#.*set-environment -g PATH/s/^#//' $(HOME)/.tmux.conf
	sed -i.bak 's|/usr/bin/pinentry-tty|/opt/homebrew/bin/pinentry-mac|g' $(HOME)/.gnupg/gpg-agent.conf
	ln -sfv $(ROOTDIR)/macos/docker_config.json $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	sudo ln -sfv $(ROOTDIR)/macos/docker_config.json /etc/docker/config.json
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		sudo ln -sfv "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chown root:wheel "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua
```

- [ ] **Step 2: Verify `make mac_link`**

Run: `make --dry-run mac_link`
Expected: Parses successfully without syntax errors.

- [ ] **Step 3: Commit**

```bash
git add Makefile.d/macos.mk
git commit -m "refactor: apply DRY loop to Makefile.d/macos.mk"
```
