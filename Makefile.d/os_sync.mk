.PHONY: os_sync_full env_install sway_systemd_install sway_systemd_enable_user sway_config_install tmpfiles_install_safe tmpfiles_install_aggressive tmpfiles_install_very_aggressive journald_coredump_install docker_setup enable_safe_services enable_optin_services verify

os_sync_full: env_install sway_systemd_install sway_config_install tmpfiles_install_safe journald_coredump_install docker_setup enable_safe_services sway_systemd_enable_user verify

env_install:
	@echo "Installing environment file..."
	@sudo cp /etc/environment /etc/environment.bak.$$(date -u +%Y%m%d%H%M%S) || true
	@sudo cp arch/environment /etc/environment

sway_systemd_install:
	@echo "Installing sway systemd user units..."
	@sudo cp arch/sway.sh /usr/local/bin/sway-start
	@sudo chmod +x /usr/local/bin/sway-start
	@sudo cp arch/systemd-user/* /etc/systemd/user/
	@systemctl --user daemon-reload

sway_systemd_enable_user:
	@echo "Enabling sway systemd user service..."
	@systemctl --user enable --now sway.service

sway_config_install:
	@echo "Installing sway config..."
	@mkdir -p ~/.config/sway
	@cp sway/config ~/.config/sway/config
	@sudo chown -R $$(whoami):$$(whoami) ~/.config/sway

tmpfiles_install_safe:
	@echo "Installing safe tmpfiles..."
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
	@sudo cp arch/systemd/journald.conf.d/10-size.conf /etc/systemd/journald.conf.d/
	@sudo cp arch/systemd/coredump.conf.d/10-limits.conf /etc/systemd/coredump.conf.d/
	@sudo systemctl restart systemd-journald

docker_setup:
	@echo "Setting up Docker..."
	@sudo cp arch/docker/daemon.json /etc/docker/daemon.json
	@sudo systemctl restart docker
	@sudo cp arch/systemd/system/docker-*.service /etc/systemd/system/
	@sudo cp arch/systemd/system/docker-*.timer /etc/systemd/system/

enable_safe_services:
	@echo "Enabling safe services..."
	@sudo systemctl daemon-reload
	@sudo systemctl enable --now systemd-tmpfiles-clean.timer
	@sudo systemctl enable --now fstrim.timer || true
	@sudo systemctl enable --now paccache.timer || true
	@sudo systemctl enable --now docker-prune.timer

enable_optin_services:
	@echo "Installing opt-in services..."
	@sudo cp arch/systemd/system/xfs-fsr.* /etc/systemd/system/
	@sudo cp arch/systemd/system/journal-vacuum.* /etc/systemd/system/
	@sudo cp arch/systemd/system/drop-caches.* /etc/systemd/system/
	@echo "To enable opt-in services, run:"
	@echo "sudo systemctl enable --now xfs-fsr.timer"
	@echo "sudo systemctl enable --now journal-vacuum.timer"
	@echo "sudo systemctl enable --now docker-builder-prune.timer"
	@echo "sudo systemctl enable --now drop-caches.timer"

verify:
	@echo "Verifying installation..."
	@systemctl list-timers
	@docker info --format '{{.LoggingDriver}}'
	@ls /usr/local/bin/sway-start
	@ls ~/.config/sway/config
