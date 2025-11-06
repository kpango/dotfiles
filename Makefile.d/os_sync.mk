.PHONY: os_sync_full env_install sway_systemd_install sway_systemd_enable_user sway_config_install tmpfiles_install_safe tmpfiles_install_aggressive tmpfiles_install_very_aggressive journald_coredump_install docker_setup enable_safe_services enable_optin_services verify

os_sync_full: env_install sway_systemd_install sway_config_install tmpfiles_install_safe journald_coredump_install docker_setup enable_safe_services sway_systemd_enable_user verify

env_install:
	@echo "Installing environment file..."
	@sudo cp /etc/environment /etc/environment.bak.$(shell date -u +%Y%m%d%H%M%S) || true
	@sudo cp arch/environment /etc/environment

sway_systemd_install:
	@echo "Installing sway systemd user units..."
	@sudo cp arch/sway.sh /usr/local/bin/sway-start
	@sudo chmod +x /usr/local/bin/sway-start
	@sudo mkdir -p /etc/systemd/user
	@sudo cp arch/systemd-user/* /etc/systemd/user/
	@if [ -n "$$DBUS_SESSION_BUS_ADDRESS" ]; then systemctl --user daemon-reload; fi

sway_systemd_enable_user:
	@echo "Enabling sway systemd user service..."
	@if [ -n "$$DBUS_SESSION_BUS_ADDRESS" ]; then systemctl --user enable --now sway.service; fi

sway_config_install:
	@echo "Installing sway config..."
	@mkdir -p $(HOME)/.config/sway
	@cp sway/config $(HOME)/.config/sway/config

tmpfiles_install_safe:
	@echo "Installing safe tmpfiles..."
	@sudo mkdir -p /etc/tmpfiles.d
	@sudo mkdir -p /etc/user-tmpfiles.d
	@sudo cp arch/tmpfiles.d/20-wayland-sway.conf /etc/tmpfiles.d/
	@sudo cp arch/tmpfiles.d/30-docker.conf /etc/tmpfiles.d/
	@sudo cp arch/tmpfiles.d/40-networking.conf /etc/tmpfiles.d/
	@sudo cp arch/tmpfiles.d/50-system.conf /etc/tmpfiles.d/
	@sudo cp arch/user-tmpfiles.d/10-desktop-caches.conf /etc/user-tmpfiles.d/

tmpfiles_install_aggressive:
	@echo "Installing aggressive tmpfiles..."
	@sudo cp arch/tmpfiles.d/60-aggressive-system.conf /etc/tmpfiles.d/
	@sudo cp arch/user-tmpfiles.d/60-aggressive-desktop.conf /etc/user-tmpfiles.d/

tmpfiles_install_very_aggressive:
	@echo "Installing very aggressive tmpfiles..."
	@sudo cp arch/user-tmpfiles.d/70-very-aggressive-devcaches.conf /etc/user-tmpfiles.d/
	@sudo cp arch/user-tmpfiles.d/71-very-aggressive-electron.conf /etc/user-tmpfiles.d/

journald_coredump_install:
	@echo "Installing journald and coredump configs..."
	@sudo mkdir -p /etc/systemd/journald.conf.d
	@sudo mkdir -p /etc/systemd/coredump.conf.d
	@sudo cp arch/systemd/journald.conf.d/10-size.conf /etc/systemd/journald.conf.d/
	@sudo cp arch/systemd/coredump.conf.d/10-limits.conf /etc/systemd/coredump.conf.d/
	@sudo systemctl restart systemd-journald

docker_setup:
	@echo "Setting up docker..."
	@sudo mkdir -p /etc/docker
	@if [ -f /etc/docker/daemon.json ]; then sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak.$(shell date -u +%Y%m%d%H%M%S); fi
	@sudo cp arch/docker/daemon.json /etc/docker/daemon.json
	@sudo cp arch/systemd/docker-prune.service /etc/systemd/system/
	@sudo cp arch/systemd/docker-prune.timer /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl restart docker || true
	@sudo systemctl enable --now docker-prune.timer

enable_safe_services:
	@echo "Enabling safe services..."
	@sudo systemctl daemon-reload
	@sudo systemctl enable --now systemd-tmpfiles-clean.timer
	@sudo systemctl enable --now fstrim.timer
	@if [ -f /etc/systemd/system/paccache.timer ]; then sudo systemctl enable --now paccache.timer; fi
	@sudo systemctl enable --now docker-prune.timer

enable_optin_services:
	@echo "Installing opt-in services..."
	@sudo cp arch/systemd/xfs-fsr.service /etc/systemd/system/
	@sudo cp arch/systemd/xfs-fsr.timer /etc/systemd/system/
	@sudo cp arch/systemd/journal-vacuum.service /etc/systemd/system/
	@sudo cp arch/systemd/journal-vacuum.timer /etc/systemd/system/
	@sudo cp arch/systemd/docker-builder-prune.service /etc/systemd/system/
	@sudo cp arch/systemd/docker-builder-prune.timer /etc/systemd/system/
	@sudo cp arch/systemd/drop-caches.service /etc/systemd/system/
	@sudo cp arch/systemd/drop-caches.timer /etc/systemd/system/
	@echo "To enable these services, run:"
	@echo "sudo systemctl enable --now xfs-fsr.timer"
	@echo "sudo systemctl enable --now journal-vacuum.timer"
	@echo "sudo systemctl enable --now docker-builder-prune.timer"
	@echo "sudo systemctl enable --now drop-caches.timer"

verify:
	@echo "Verifying installation..."
	@if [ -n "$$DBUS_SESSION_BUS_ADDRESS" ]; then systemctl --user status sway.service; fi
	@systemctl list-timers
	@cat /etc/environment
	@ls -l /usr/local/bin/sway-start
	@ls -l $(HOME)/.config/sway/config
	@sudo docker info | grep "Logging Driver" || true
	@sudo journalctl --disk-usage || true
	@systemd-tmpfiles --cat-config || true
