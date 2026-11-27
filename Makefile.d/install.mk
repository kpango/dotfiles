.PHONY: dotfiles/install dotfiles/compile dotfiles/clean dotfiles/perm precompile/zsh \
        arch/install arch/p1/install arch/desk/install arch/desk/audit arch/clean \
        mac/install m1/install m1air/install m3/install mac/clean \
        claude/install claude/docker/install \
        omp/install omp/docker/install omp/models/update omp/models/sync omp/models/timer/install omp/auth/dedupe \
        agy/install agy/docker/install \
        hermes/install hermes/docker/install hermes/systemd/install hermes/cron/install hermes/cron/check \
        agent-decide/systemd/install \
        tailscale/install \
        network/install \
        graph/init \
        cdi/update \
        pinentry/install pinentry/update \
        echo run \
        link copy clean perm \
        arch_link arch_copy arch_p1_link arch_p1_copy arch_desk_link arch_desk_copy \
        mac_link mac_copy \
        tmux/go/install \
        tmux/go/update

MODE ?= link

define DEPLOY_FUNC
	[ -z "$(1)" ] || { \
		$(3) mkdir -p "$$(dirname "$(2)")"; \
		$(if $(filter copy,$(MODE)), \
			$(3) $(RM) "$(2)" && $(3) $(CP) "$(1)" "$(2)", \
			if [ -d "$(2)" ] && [ ! -L "$(2)" ]; then \
				echo "Skipping existing directory: $(2)"; \
			else \
				$(3) $(RM) "$(2)" 2>/dev/null || true; \
				$(3) ln -sfvn "$(1)" "$(2)"; \
			fi \
		); \
	}
endef

# $(call LINK_DIR_FUNC,src,dest): `ln -sfvn src dest` for a directory link, but when
# dest is already a real directory (e.g. Claude Code ran once before this install
# and created ~/.claude/skills or ~/.claude/projects) — where plain ln would nest
# the link inside it as dest/<basename src> — its contents are merged into src
# (never overwriting) and the directory is kept aside as dest.pre-dotfiles.<ts>.
# cp's status is ignored on purpose: macOS `cp -n` exits 1 whenever it skips an
# existing file, and nothing is lost either way since dest is moved, not deleted.
# Plain cp (not $(CP)) on purpose: cpz has no -n/-p, and `cpz dir/. dst/` copies
# dir itself into dst/ instead of merging its contents.
define LINK_DIR_FUNC
	if [ -d "$(2)" ] && [ ! -L "$(2)" ]; then \
		if [ -L "$(2)/$$(basename "$(1)")" ]; then $(RM) "$(2)/$$(basename "$(1)")"; fi; \
		mkdir -p "$(1)" || exit 1; \
		cp -Rpn "$(2)/." "$(1)/" || true; \
		mv "$(2)" "$(2).pre-dotfiles.$$(date +%Y%m%d%H%M%S)" || exit 1; \
		echo "merged pre-existing $(2) into $(1) (original kept as $(2).pre-dotfiles.*)"; \
	fi; \
	ln -sfvn "$(1)" "$(2)"
endef

define CLEAN_FUNC
	[ -z "$(1)" ] || $(2) $(RM) "$(1)"
endef

define FIND_GO
	_go=''; _root=''; \
	for _c in \
	    /usr/lib/go/bin/go \
	    /usr/local/go/bin/go \
	    /opt/homebrew/bin/go \
	    /opt/homebrew/opt/go/libexec/bin/go; \
	do \
	    [ -x "$$_c" ] || continue; \
	    _r="$$(dirname "$$(dirname "$$_c")")"; \
	    GOROOT="$$_r" "$$_c" version >/dev/null 2>&1 && { _go="$$_c"; _root="$$_r"; break; }; \
	done; \
	if [ -z "$$_go" ] && _c="$$(command -v go 2>/dev/null)" && [ -x "$$_c" ]; then \
	    _r="$$(env -u GOROOT "$$_c" env GOROOT 2>/dev/null)"; \
	    [ -n "$$_r" ] && GOROOT="$$_r" "$$_c" version >/dev/null 2>&1 \
	        && { _go="$$_c"; _root="$$_r"; }; \
	fi
endef

# Run `systemctl --user` with explicit runtime dir and D-Bus user bus address so
# non-PAM / SSH / cron shells without XDG_RUNTIME_DIR or DBUS_SESSION_BUS_ADDRESS
# still reach the target user's systemd instance.
SYSTEMCTL_USER = XDG_RUNTIME_DIR="/run/user/$(USER_ID)" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(USER_ID)/bus" systemctl --user

# Ensure the target user's systemd manager (user@<uid>.service) is active and
# accepting connections on the user scope bus before running `systemctl --user`.
# Recovers cleanly when user@<uid>.service died (e.g. OOM-killed -> Active: failed,
# leaving stale /run/user/<uid>/systemd/private sockets -> "Connection refused")
# or has not finished starting after `loginctl enable-linger`.
# Note: probes `show --property=Version` rather than `is-system-running` because
# `is-system-running` exits 1 whenever any single unit is degraded.
define ENSURE_USER_SYSTEMD
	@if [ ! -d /run/systemd/system ]; then \
		echo "systemd: PID 1 is not systemd — cannot connect to user scope bus" >&2; \
		exit 1; \
	fi; \
	if ! sudo systemctl is-active --quiet "user@$(USER_ID).service"; then \
		echo "systemd: user@$(USER_ID).service is not active — starting it..."; \
		sudo systemctl reset-failed "user@$(USER_ID).service" 2>/dev/null || true; \
		sudo systemctl start "user@$(USER_ID).service"; \
	fi; \
	_i=0; \
	until $(SYSTEMCTL_USER) show --property=Version >/dev/null 2>&1; do \
		_i=$$((_i + 1)); \
		if [ "$$_i" -ge 50 ]; then \
			echo "systemd: timed out waiting for user@$(USER_ID).service bus (/run/user/$(USER_ID)/bus)" >&2; \
			exit 1; \
		fi; \
		sleep 0.1; \
	done
endef

# ── Dotfiles map ──────────────────────────────────────────────────────────────

define DOTFILES_MAP
atuin/config.toml .config/atuin/config.toml
atuin/themes/zed_kpango.toml .config/atuin/themes/zed_kpango.toml
bin/xdg-open .local/bin/xdg-open
bin/xdg-open .local/bin/google-chrome
bin/xdg-open .local/bin/google-chrome-stable
bin/xdg-open .local/bin/open
bin/xdg-open .local/bin/x-www-browser
agent/scripts/sandbox/pa-sandbox .local/bin/pa-sandbox
agent/scripts/trail-guard.sh .local/bin/trail
chrome-beta-flags.conf .config/chrome-beta-flags.conf
agent/harnesses/claude/CLAUDE.md .claude/CLAUDE.md
agent/AGENTS.md .claude/AGENTS.md
agent/AGENTS-claude-supplement.md .claude/AGENTS-supplement.md
agent/SWARM.md .claude/SWARM.md
agent/SWARM_REFERENCES.md .claude/SWARM_REFERENCES.md
agent/harnesses/claude/keybindings.json .claude/keybindings.json
agent/harnesses/claude/settings.json .claude/settings.json
agent/harnesses/claude/settings.local.json .claude/settings.local.json
agent/harnesses/claude/statusline-command.sh .claude/statusline-command.sh
agent/harnesses/claude/model-routing.json .claude/model-routing.json
agent/harnesses/omp/AGENTS.md .omp/agent/AGENTS.md
agent/harnesses/omp/SYSTEM.md .omp/agent/SYSTEM.md
agent/SWARM.md .omp/agent/SWARM.md
agent/SWARM_REFERENCES.md .omp/agent/SWARM_REFERENCES.md
agent/RTK.md .omp/agent/RTK.md
agent/harnesses/omp/models.yml .omp/agent/models.yml
agent/harnesses/omp/lsp.yml .omp/agent/lsp.yml
agent/harnesses/omp/dap.json .omp/agent/dap.json
agent/harnesses/omp/sol-pi.json .omp/agent/sol-pi.json
agent/harnesses/omp/keybindings.json .omp/agent/keybindings.json
agent/harnesses/omp/model-routing.json .omp/agent/model-routing.json
desktop/discord.desktop .local/share/applications/discord.desktop
desktop/slack.desktop .local/share/applications/slack.desktop
dockers/config.json .docker/config.json
dockers/daemon.json .docker/daemon.json
editorconfig .editorconfig
agent/harnesses/agy/AGENTS.md .agy/AGENTS.md
agent/harnesses/agy/SYSTEM.md .agy/SYSTEM.md
agent/SWARM.md .agy/SWARM.md
agent/SWARM_REFERENCES.md .agy/SWARM_REFERENCES.md
agent/RTK.md .agy/RTK.md
agent/harnesses/agy/settings.json .agy/settings.json
agent/harnesses/agy/policies/policy.toml .agy/policies/rules.toml
agent/harnesses/agy/mcp_config.json .agy/mcp_config.json
agent/harnesses/agy/model-routing.json .agy/model-routing.json
agent/harnesses/agy/AGENTS.md .gemini/AGENTS.md
agent/harnesses/agy/AGENTS.md .gemini/GEMINI.md
agent/harnesses/agy/SYSTEM.md .gemini/SYSTEM.md
agent/SWARM.md .gemini/SWARM.md
agent/SWARM_REFERENCES.md .gemini/SWARM_REFERENCES.md
agent/RTK.md .gemini/RTK.md
agent/harnesses/agy/settings.json .gemini/settings.json
agent/harnesses/agy/policies/policy.toml .gemini/policies/rules.toml
agent/harnesses/agy/policies/policy.toml .gemini/policies/policy.toml
agent/harnesses/agy/mcp_config.json .gemini/config/mcp_config.json
agent/harnesses/agy/hooks/hooks.json .gemini/config/hooks.json
agent/harnesses/agy/hooks/hooks.json .gemini/antigravity-cli/hooks.json
agent/harnesses/agy/model-routing.json .gemini/model-routing.json
agent/harnesses/agy/model-routing.json .gemini/config/model-routing.json
agent/harnesses/hermes/config.yaml .hermes/config.yaml
agent/harnesses/hermes/SOUL.md .hermes/SOUL.md
agent/harnesses/hermes/model-routing.json .hermes/model-routing.json
agent/harnesses/hermes/omh/category-maestro.json .omh/routing/category-maestro.json
ghostty.conf .config/ghostty/config
ghostty/shaders .config/ghostty/shaders
ghostty/themes .config/ghostty/themes
gitattributes .gitattributes
gitconfig .gitconfig
.gitignore .gitignore
gitui/key_bindings.ron .config/gitui/key_bindings.ron
gitui/theme.ron .config/gitui/theme.ron
gpg-agent.conf .gnupg/gpg-agent.conf
helix/config.toml .config/helix/config.toml
helix/languages.toml .config/helix/languages.toml
helix/themes .config/helix/themes
herdr/config.toml .config/herdr/config.toml
lumen.json .config/lumen/lumen.config.json
sheldon.toml .config/sheldon/plugins.toml
systemd/environment.d/xdg.conf .config/environment.d/xdg.conf
systemd/user/app-com.mitchellh.ghostty.service .config/systemd/user/app-com.mitchellh.ghostty.service
systemd/user/agent-decide.service .config/systemd/user/agent-decide.service
systemd/user/atuin.service .config/systemd/user/atuin.service
systemd/user/herdr.service .config/systemd/user/herdr.service
systemd/user/hermes-gateway.service .config/systemd/user/hermes-gateway.service
systemd/user/kanshi.service .config/systemd/user/kanshi.service
systemd/user/omp-model-catalog-update.service .config/systemd/user/omp-model-catalog-update.service
systemd/user/omp-model-catalog-update.timer .config/systemd/user/omp-model-catalog-update.timer
systemd/user/sway-session.target .config/systemd/user/sway-session.target
systemd/user/tmux.service .config/systemd/user/tmux.service
systemd/user/zsh-patina.service .config/systemd/user/zsh-patina.service
tmux.conf.d .tmux.conf.d
tmux.conf .tmux.conf
zfunc .zfunc
zprofile .zprofile
zshenv .zshenv
zshrc .zshrc
endef
export DOTFILES_MAP



# ── Arch maps ─────────────────────────────────────────────────────────────────

define ARCH_LINK_MAP
arch/fcitx.classicui.conf .config/fcitx5/conf/classicui.conf
arch/fcitx.conf .config/fcitx5/config
arch/fcitx.profile .config/fcitx5/profile
arch/kanshi.conf .config/kanshi/config
arch/mako.conf .config/mako/config
arch/psd.conf .config/psd/psd.conf
arch/sway.conf .config/sway/config
arch/sway/cheatsheet.md .config/sway/cheatsheet.md
sway/config.d .config/sway/config.d
sway/scripts .config/sway/scripts
arch/xdg-desktop-portal.conf .config/xdg-desktop-portal/portals.conf
arch/waybar.css .config/waybar/style.css
arch/waybar.json .config/waybar/config
arch/wofi/style.css .config/wofi/style.css
arch/wofi/wofi.conf .config/wofi/config
arch/workstyle.toml .config/workstyle/config.toml
arch/Xdefaults .Xdefaults
arch/Xmodmap .Xmodmap
bunfig.toml .bunfig.toml
go.env .config/go/env
endef
export ARCH_LINK_MAP

define ARCH_SUDO_LINK_MAP
arch/60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules
arch/default.pa /etc/pulse/default.pa
arch/limits.conf /etc/security/limits.conf
arch/makepkg.conf.d/zen2-custom.conf /etc/makepkg.conf.d/zen2-custom.conf
arch/modules-load.d/bbr.conf /etc/modules-load.d/bbr.conf
arch/modules-load.d/nf_conntrack.conf /etc/modules-load.d/nf_conntrack.conf
arch/modules-load.d/erofs.conf /etc/modules-load.d/erofs.conf
arch/modules-load.d/i2c_dev.conf /etc/modules-load.d/i2c_dev.conf
arch/pacman.conf /etc/pacman.conf
arch/thinkfan.conf /etc/thinkfan.conf
arch/tlp /etc/default/tlp
arch/tlp /etc/tlp.conf
dockers/config.json /root/.docker/config.json
dockers/daemon.json /root/.docker/daemon.json
network/nm/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
network/dns/resolved.conf /etc/systemd/resolved.conf
network/sysctl/sysctl.conf /etc/sysctl.d/99-sysctl.conf
arch/ghostty.desktop /usr/share/applications/com.mitchellh.ghostty.desktop
arch/hooks/rebuild-aur-helpers.hook /etc/pacman.d/hooks/rebuild-aur-helpers.hook
arch/hooks.d/rebuild-aur-helpers.sh /usr/local/bin/rebuild-aur-helpers.sh
arch/mkinitcpio.conf /etc/mkinitcpio.conf
arch/mkinitcpio/linux-zen.preset /etc/mkinitcpio.d/linux-zen.preset
arch/systemd/journald.conf.d/limits.conf /etc/systemd/journald.conf.d/limits.conf
arch/systemd/NetworkManager.service.d/capabilities.conf /etc/systemd/system/NetworkManager.service.d/capabilities.conf
arch/systemd/sshd.service.d/tailscale.conf /etc/systemd/system/sshd.service.d/tailscale.conf
arch/systemd/tmp-orphan-clean.service /etc/systemd/system/tmp-orphan-clean.service
arch/systemd/tmp-orphan-clean.timer /etc/systemd/system/tmp-orphan-clean.timer
arch/sshd_config.d/10-tailscale.conf /etc/ssh/sshd_config.d/10-tailscale.conf
arch/initcpio/install/acpi_override /etc/initcpio/install/acpi_override
endef
export ARCH_SUDO_LINK_MAP

define ARCH_SUDO_CP_MAP
arch/modprobe.d/nobeep.conf /etc/modprobe.d/nobeep.conf
arch/chrony.conf /etc/chrony.conf
arch/wireless-regdom /etc/conf.d/wireless-regdom
arch/sudoers /etc/sudoers.d/$(SYS_USER)
arch/environment /etc/environment
network/nm/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
network/nm/nmcli-bond-auto-connect.sh /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
network/nm/99-coalesce-x710 /etc/NetworkManager/dispatcher.d/99-coalesce-x710
endef
export ARCH_SUDO_CP_MAP

define ARCH_DESK_SUDO_LINK_MAP
arch/systemd/nvidia-unload.service /etc/systemd/system/nvidia-unload.service
arch/systemd/tailscale-gro.service /etc/systemd/system/tailscale-gro.service
arch/tmpfiles.d/thp.conf /etc/tmpfiles.d/thp.conf
arch/tmpfiles.d/thp-khugepaged.conf /etc/tmpfiles.d/thp-khugepaged.conf
arch/tmpfiles.d/ksm.conf /etc/tmpfiles.d/ksm.conf
endef
export ARCH_DESK_SUDO_LINK_MAP

define ARCH_DESK_SUDO_CP_MAP
arch/modprobe.d/blacklist-nouveau.conf /etc/modprobe.d/blacklist-nouveau.conf
arch/modprobe.d/blacklist-eeepc-wmi.conf /etc/modprobe.d/blacklist-eeepc-wmi.conf
arch/modprobe.d/nowatchdog.conf /etc/modprobe.d/nowatchdog.conf
arch/modprobe.d/thinkfan-desk.conf /etc/modprobe.d/thinkfan.conf
arch/acpi/DSDT.aml /etc/acpi_override/DSDT.aml
arch/acpi/SSDT7.aml /etc/acpi_override/SSDT7.aml
arch/desk/fstab /etc/fstab
arch/greetd/config.toml /etc/greetd/config.toml
arch/loader/entries/arch.conf /boot/loader/entries/arch.conf
arch/loader/loader.conf /boot/loader/loader.conf
endef
export ARCH_DESK_SUDO_CP_MAP

define ARCH_PREP
	@if [ ! -f /boot/vmlinuz-linux ]; then sudo $(RM) /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux.preset.pacsave; fi
	@if [ -L /etc/profile.d/sway.sh ] || grep -qs 'system-wide sway launcher' /etc/profile.d/sway.sh; then sudo $(RM) /etc/profile.d/sway.sh; fi
	@# modprobe.d is copied, not linked: the initramfs (modconf) would carry the links dangling (no /home there),
	@# so libkmod errors out and options such as nvidia-tweaks never reach modules loaded early. Drop old links
	@# first; `cp` onto them would write through into the repo file.
	@for f in /etc/modprobe.d/*.conf; do [ -L "$$f" ] && case "$$(readlink "$$f")" in */dotfiles/*) sudo $(RM) "$$f";; esac; done; true
	sudo mkdir -p /etc/systemd/journald.conf.d
	sudo mkdir -p /etc/systemd/system/NetworkManager.service.d
	sudo mkdir -p /etc/systemd/system/sshd.service.d
	sudo mkdir -p /etc/acpi_override
	sudo mkdir -p /etc/greetd
	sudo mkdir -p /etc/initcpio/install
	sudo mkdir -p /etc/pacman.d/hooks
	sudo mkdir -p /var/cache/aur-src
	mkdir -p $(HOME)/.config/fcitx5/conf
	mkdir -p $(HOME)/.config/go
	mkdir -p $(HOME)/.config/kanshi
	mkdir -p $(HOME)/.config/mako
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
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/99-coalesce-x710
	sudo chown root:root /etc/NetworkManager/dispatcher.d/99-coalesce-x710
	sudo chown -R 0:0 /etc/sudoers.d
	sudo chmod 750 /etc/sudoers.d
	sudo find /etc/sudoers.d -type f -exec chmod 0440 {} +
	sudo chmod +x /usr/local/bin/rebuild-aur-helpers.sh
	sudo chown root:root /usr/local/bin/rebuild-aur-helpers.sh
	sudo sysctl -e -p /etc/sysctl.d/99-sysctl.conf
	sudo systemctl daemon-reload
	sudo systemctl enable --now tmp-orphan-clean.timer
	sudo loginctl enable-linger $(SYS_USER)
	$(ENSURE_USER_SYSTEMD)
	$(SYSTEMCTL_USER) daemon-reload
	$(SYSTEMCTL_USER) enable --now atuin.service
	@# no --now: kanshi needs a Wayland session; sway-session.target starts it (ConditionEnvironment=WAYLAND_DISPLAY)
	$(SYSTEMCTL_USER) enable kanshi.service
	$(SYSTEMCTL_USER) enable app-com.mitchellh.ghostty.service
	$(SYSTEMCTL_USER) enable --now tmux.service
	$(SYSTEMCTL_USER) enable --now zsh-patina.service
	@if [ -x "$(HOME)/.local/bin/hermes" ]; then $(SYSTEMCTL_USER) enable --now hermes-gateway.service; else echo "systemd: hermes not installed at $(HOME)/.local/bin/hermes — skipping hermes-gateway.service"; fi
	@if [ -x /usr/local/lib/rust/cargo/bin/herdr ]; then $(SYSTEMCTL_USER) enable herdr.service; else echo "systemd: herdr not installed — skipping herdr.service"; fi
	sudo systemctl enable systemd-resolved
	sudo systemctl restart systemd-resolved
	sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
	sudo systemctl restart NetworkManager
	tailscale set --accept-dns=true 2>/dev/null || echo "warning: tailscale not running -- run 'sudo tailscale set --accept-dns=true' manually"
endef

define ARCH_P1_POST
	$(RM) $(HOME)/.config/psd
	mkdir $(HOME)/.config/psd
	sudo systemctl daemon-reload
endef

define ARCH_DESK_POST
	sudo mkdir -p /etc/cdi
	sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml 2>/dev/null || echo "warning: nvidia-ctk cdi generate skipped (reboot required after driver update)"
	sudo mkdir -p /etc/systemd/system/irqbalance.service.d
	sudo $(RM) /etc/systemd/system/irqbalance.service.d/override.conf
	sudo $(CP) $(ROOTDIR)/arch/service/irqbalance.service /etc/systemd/system/irqbalance.service.d/override.conf
	sudo $(RM) /etc/NetworkManager/system-connections
	sudo mkdir -p /etc/NetworkManager/system-connections
	sudo $(CP) $(ROOTDIR)/network/nm/desk/bond0.nmconnection /etc/NetworkManager/system-connections/bond0.nmconnection
	sudo $(CP) $(ROOTDIR)/network/nm/desk/eth0.nmconnection /etc/NetworkManager/system-connections/eth0.nmconnection
	sudo $(CP) $(ROOTDIR)/network/nm/desk/slave0.nmconnection /etc/NetworkManager/system-connections/slave0.nmconnection
	sudo $(CP) $(ROOTDIR)/network/nm/desk/slave1.nmconnection /etc/NetworkManager/system-connections/slave1.nmconnection
	sudo chmod 700 /etc/NetworkManager/system-connections
	sudo find /etc/NetworkManager/system-connections -type f -exec chmod 600 {} +
	sudo chown -R root:root /etc/NetworkManager/system-connections
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	sudo nmcli connection reload
	sudo systemctl daemon-reload
	sudo systemctl enable nvidia-unload.service
	sudo systemctl enable tailscale-gro.service
	@# greetd owns tty1 from the next boot (autologin once + tuigreet). Rollback from SSH/tty2:
	@# systemctl disable greetd && systemctl enable getty@tty1
	@if command -v greetd >/dev/null; then sudo systemctl disable getty@tty1.service; sudo systemctl enable greetd.service; fi
	sudo systemctl restart NetworkManager
	sudo systemd-tmpfiles --create /etc/tmpfiles.d/thp.conf /etc/tmpfiles.d/thp-khugepaged.conf /etc/tmpfiles.d/ksm.conf
	@sudo find /boot/loader/entries/ -name '*.conf' -not -name 'arch.conf' -delete && \
		echo "boot: stale entries removed" || true
	sudo mkinitcpio -P
endef

# ── macOS ──────────────────────────────────────────────────────────────────────

MACOS_LAUNCH_AGENTS = localhost.homebrew-autoupdate.plist ulimit.plist

# darwinConfigurations host (nix/flake.nix) applied by mac/install's nix/setup step.
# Override per-machine: make mac/install MAC_NIX_HOST_NAME=macbook-air-m1
# (or use the m1/install, m1air/install, m3/install convenience targets below).
MAC_NIX_HOST_NAME ?= macbook-pro-m3

define MAC_PREP
	sudo $(RM) \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
		$(HOME)/.docker/config.json \
		$(HOME)/.docker/daemon.json \
		$(HOME)/.gnupg/gpg-agent.conf \
		$(HOME)/.tmux.conf \
		$(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist \
		$(HOME)/Library/LaunchAgents/ulimit.plist
	# dotfiles/install (a prerequisite above) just symlinked (or copied) .zshrc/.zshenv/.zprofile
	# straight from the dotfiles repo. On macOS nix-darwin's home-manager
	# activation (nix/setup below) is the final owner and generates its own
	# .zshrc/.zshenv/.zprofile (nix/modules/home/programs/zsh.nix) that differs
	# byte-for-byte from the raw repo file — and unlike other home-manager
	# entries, `force = true` can't rescue this one (see that module's
	# comment: home-manager's own dotDirRel="." key shape makes force a
	# no-op here). Removing dotfiles/install's copy lets home-manager place
	# its own without a "would be clobbered" collision. Plain rm, no sudo:
	# by this point all three are dotfiles/install's own output (its DEPLOY_FUNC
	# already replaced any hand-written ~/.zprofile, e.g. one with brew shellenv).
	$(RM) $(HOME)/.zshrc $(HOME)/.zshenv $(HOME)/.zprofile
	$(CP) $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	sed -i.bak '/^#.*set-environment -g PATH/s/^#//' $(HOME)/.tmux.conf
	# gpg-agent.conf is NOT copied here: nix-darwin's home-manager activation
	# (nix/setup below) owns it (darwin.nix, Nix-built pinentry wrapper path).
	# A plain-file copy here made home-manager back it up to
	# gpg-agent.conf.hm-bak on every run, and the second run aborted with
	# "Existing file '...gpg-agent.conf.hm-bak' would be clobbered".
	# Previously this rewrote the path to /opt/homebrew/bin/pinentry-mac, a
	# Homebrew path that stopped existing once Homebrew was disabled in favor
	# of nixpkgs (see nix/modules/home/dotfiles/darwin.nix) — that stale sed
	# is what broke `gpg --clearsign`/commit signing after a `mac/install`
	# re-run on an already-Nix-managed machine (found 2026-08-22).
endef

## Regenerate CDI spec from the currently installed NVIDIA driver directly into /etc/cdi/
cdi/update:
	sudo mkdir -p /etc/cdi
	sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml

# ── Shared Nvidia block (used by arch/p1/install and arch/desk/install) ────────

define NVIDIA_INSTALL
	sudo $(CP) $(ROOTDIR)/nvidia/nvidia-tweaks.conf /etc/modprobe.d/nvidia-tweaks.conf
	@$(call DEPLOY_FUNC,$(ROOTDIR)/nvidia/nvidia-uvm.conf,/etc/modules-load.d/nvidia-uvm.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/nvidia/60-nvidia.rules,/etc/udev/rules.d/60-nvidia.rules,sudo)
endef

# ── Targets ───────────────────────────────────────────────────────────────────

echo:
	@echo $(ROOTDIR)

run:
	source $(ROOTDIR)/zsh/20-docker.zsh && devrun

## build and install tmux-pane-info to ~/.zcache/ (host OS)
## Invoked as: tmux-pane-info path|branch|kube [args]  (called from tmux status.conf)
## Detects Go across Arch (/usr/lib/go), macOS Homebrew (/opt/homebrew), and PATH.
## Falls back to zsh + zcompile when Go is unavailable.
tmux/go/install:
	mkdir -p $(HOME)/.zcache
	@$(FIND_GO); \
	if [ -n "$$_go" ]; then \
	    cd $(ROOTDIR)/tmux.conf.d/tmux-pane-info \
	    && GOROOT="$$_root" GOBIN=$(HOME)/.zcache "$$_go" install -trimpath -ldflags="-s -w" -buildvcs=false . \
	    && echo "tmux-pane-info: installed $(HOME)/.zcache/tmux-pane-info"; \
	else \
	    echo "tmux-pane-info: Go not found — installing zsh fallback scripts"; \
	    $(CP) $(ROOTDIR)/tmux.conf.d/kube          $(HOME)/.zcache/tmux-kube; \
	    $(CP) $(ROOTDIR)/tmux.conf.d/status-left   $(HOME)/.zcache/tmux-status-left; \
	    $(CP) $(ROOTDIR)/tmux.conf.d/status-branch $(HOME)/.zcache/tmux-status-branch; \
	    $(CP) $(ROOTDIR)/tmux.conf.d/short-path    $(HOME)/.zcache/tmux-short-path; \
	    zsh -c 'zcompile $(HOME)/.zcache/tmux-kube; zcompile $(HOME)/.zcache/tmux-status-left; zcompile $(HOME)/.zcache/tmux-status-branch; zcompile $(HOME)/.zcache/tmux-short-path' || true; \
	fi

## install or update tmux-pane-info from the published module (no local clone required)
## Equivalent to: GOBIN=~/.zcache go install github.com/kpango/dotfiles/tmux.conf.d/tmux-pane-info@latest
## Use this target on a fresh host or to upgrade to the latest published version.
tmux/go/update:
	mkdir -p $(HOME)/.zcache
	@$(FIND_GO); \
	if [ -n "$$_go" ]; then \
	    GOROOT="$$_root" GOBIN=$(HOME)/.zcache "$$_go" install \
	        -trimpath -ldflags="-s -w" \
	        github.com/kpango/dotfiles/tmux.conf.d/tmux-pane-info@latest \
	    && echo "tmux-pane-info: updated to latest at $(HOME)/.zcache/tmux-pane-info"; \
	else \
	    echo "tmux-pane-info: Go not found — cannot update"; \
	    exit 1; \
	fi

## install tmux powerline glyph scripts and Go-compiled status helpers to ~/.zcache
dotfiles/compile: tmux/go/install pinentry/install
	mkdir -p $(HOME)/.zcache
	$(CP) $(ROOTDIR)/tmux.conf.d/pl-right $(HOME)/.zcache/tmux-pl-right
	$(CP) $(ROOTDIR)/tmux.conf.d/pl-left  $(HOME)/.zcache/tmux-pl-left
	chmod +x $(HOME)/.zcache/tmux-pl-right $(HOME)/.zcache/tmux-pl-left

## symlink or copy all dotfiles to $HOME (see DEPLOY_FUNC for MODE=link|copy).
## NIX_MANAGED=1 skips destinations a home-manager module generates more
## richly than a plain symlink (programs.zsh's .zshrc/.zshenv/.zprofile, programs.git's
## .gitconfig, programs.tmux's .tmux.conf -- everywhere; darwin.nix's
## Nix-built .gnupg/gpg-agent.conf, Darwin only) -- set automatically by
## nix/modules/home/dotfiles/agent-tools.nix's home.activation call, so a
## fresh non-nix bootstrap (arch/install, mac/install's first run, before
## nix/setup) still gets every DOTFILES_MAP entry untouched.
dotfiles/install:
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		if [ -n "$(NIX_MANAGED)" ]; then \
			case "$$dest" in \
				.zshrc|.zshenv|.zprofile|.gitconfig|.tmux.conf) continue ;; \
				.gnupg/gpg-agent.conf) [ "$(UNAME_S)" = Darwin ] && continue ;; \
			esac; \
		fi; \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); \
	done
	@if [ -L "$(HOME)/.tmux.new-session" ]; then $(RM) "$(HOME)/.tmux.new-session"; fi
	@for legacy in "$(HOME)/.pi" "$(HOME)/.codex" "$(HOME)/.dsh" "$(HOME)/.prime"; do \
		[ -L "$$legacy" ] && $(RM) "$$legacy"; \
	done; true
	@if [ -d "$(HOME)/.local/bin" ]; then \
		find "$(HOME)/.local/bin" -maxdepth 1 -type l ! -exec test -e {} \; -print | while IFS= read -r _link; do \
			case "$$(readlink "$$_link")" in */dotfiles/*) $(RM) "$$_link" ;; esac; \
		done; \
	fi
	@if [ -d "$(HOME)/.config/systemd/user" ]; then \
		find "$(HOME)/.config/systemd/user" -maxdepth 2 -type l ! -exec test -e {} \; -print | while IFS= read -r _link; do \
			case "$$(readlink "$$_link")" in */dotfiles/*) $(RM) "$$_link" ;; esac; \
		done; \
	fi
ifneq ($(UNAME_S),Darwin)
	# Linux, non-NixOS only: NixOS manages /etc/docker declaratively
	# (nix/modules/nixos/virtualization/docker.nix, nix/hosts/tr/virtualization/
	# docker.nix), reading this same dockers/daemon.json as its base — writing it
	# here too would fight Nix's own /etc management and get reverted on the next
	# nixos-rebuild switch anyway. macOS uses apple/container (see
	# nix/modules/darwin/containerization.nix), which doesn't read these files at
	# all — see mac/install below.
	@[ -f /etc/NIXOS ] || $(call DEPLOY_FUNC,$(ROOTDIR)/dockers/config.json,/etc/docker/config.json,sudo)
	@[ -f /etc/NIXOS ] || { \
		sudo mkdir -p /etc/docker && \
		jq '. + {"runtimes": {"runsc": {"path": "/usr/local/bin/runsc"}, "runu": {"path": "/usr/local/bin/runu"}}}' \
			"$(ROOTDIR)/dockers/daemon.json" | sudo tee /etc/docker/daemon.json > /dev/null; \
	}
	@[ -f /etc/NIXOS ] || $(call DEPLOY_FUNC,$(ROOTDIR)/arch/containerd.toml,/etc/containerd/config.toml,sudo)
endif
	@$(MAKE) dotfiles/compile ROOTDIR='$(ROOTDIR)'
	@$(MAKE) precompile/zsh ROOTDIR='$(ROOTDIR)'

## pre-generate and zcompile all zsh caches (safe to run after dotfiles/install)
precompile/zsh:
	@zsh -i -c 'source "$(ROOTDIR)/zsh/05-functions.zsh" && zprecompile' 2>/dev/null || \
		printf "Note: some zsh caches skipped (tools not installed)\n" >&2

## Deploy Claude Code config inside a Docker build layer (no sudo, copies not symlinks)
claude/docker/install:
	install -d -m 700 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(HOME)/.claude" \
		"$(HOME)/.claude/hooks" \
		"$(HOME)/.claude/agents" \
		"$(HOME)/.claude/rules" \
		"$(HOME)/.claude/plugins" \
		"$(HOME)/.claude/memory" \
		"$(HOME)/.claude/projects" \
		"$(HOME)/.claude/session-data"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/claude/settings.json" "$(HOME)/.claude/settings.json"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/claude/settings.local.json" "$(HOME)/.claude/settings.local.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/claude/CLAUDE.md" "$(HOME)/.claude/CLAUDE.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/AGENTS.md" "$(HOME)/.claude/AGENTS.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/AGENTS-claude-supplement.md" "$(HOME)/.claude/AGENTS-supplement.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/RTK.md" "$(HOME)/.claude/RTK.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM.md" "$(HOME)/.claude/SWARM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM_REFERENCES.md" "$(HOME)/.claude/SWARM_REFERENCES.md"
	install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/claude/statusline-command.sh" "$(HOME)/.claude/statusline-command.sh"
	find "$(ROOTDIR)/agent/rules" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.claude/rules/" \;
	HOME="$(HOME)" envsubst < "$(ROOTDIR)/agent/harnesses/claude/installed_plugins.json" \
		> "$(HOME)/.claude/plugins/installed_plugins.json"
	chown "$(USER_ID):$(GROUP_ID)" "$(HOME)/.claude/plugins/installed_plugins.json"
	find "$(ROOTDIR)/agent/harnesses/claude/hooks" -maxdepth 1 -name "*.sh" \
		-exec install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.claude/hooks/" \;
	find "$(ROOTDIR)/agent/hooks/claude" -maxdepth 1 -name "*.sh" \
		-exec install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.claude/hooks/" \;
	@if [ -f "$(ROOTDIR)/.trail/hook.cjs" ]; then \
		install -d -m 700 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.claude/helpers"; \
		install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" \
			"$(ROOTDIR)/.trail/hook.cjs" "$(HOME)/.claude/helpers/graft-hooks.cjs"; \
	fi
	install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.local/bin"
	install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/scripts/trail-guard.sh" "$(HOME)/.local/bin/trail"
	find "$(ROOTDIR)/agent/agents" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.claude/agents/" \;
	@install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.claude/skills"
	@for skill_dir in "$(ROOTDIR)/agent/skills"/*/; do \
		skill_name=$$(basename "$$skill_dir"); \
		dest="$(HOME)/.claude/skills/$${skill_name}"; \
		$(RM) "$$dest"; \
		$(CP) "$${skill_dir}" "$$dest"; \
		find "$$dest" -type d -exec chmod 755 {} \; ; \
		find "$$dest" -type f -exec chmod 644 {} \; ; \
		find "$$dest" -type f -name "*.sh" -exec chmod 755 {} \; ; \
		chown -R "$(USER_ID):$(GROUP_ID)" "$$dest"; \
	done

## symlink ~/.claude/settings.json + settings.local.json + CLAUDE.md and share session with root
## Credentials (~/.claude/.credentials.json) are NOT managed here — SSO login handles them
## User-level symlinks (agents/hooks/skills/RTK.md, plugins, pass-repo projects/history) are set
## up first so they take effect even if the root-sharing block below is unavailable; the root home
## path itself (/root vs macOS's /var/root) is resolved once via $(ROOT_HOME) in variables.mk.
claude/install: dotfiles/install
	mkdir -p "$(HOME)/.claude/plugins" "$(HOME)/.claude/memory" "$(HOME)/.claude/session-data"
	@# envsubst (gettext) is absent on a fresh Mac before nix/setup; perl ships with macOS.
	if command -v envsubst >/dev/null 2>&1; then \
		envsubst < "$(ROOTDIR)/agent/harnesses/claude/installed_plugins.json"; \
	else \
		perl -pe 's{\$$(?:\{(\w+)\}|(\w+))}{$$ENV{$$1 // $$2} // ""}ge' "$(ROOTDIR)/agent/harnesses/claude/installed_plugins.json"; \
	fi > "$(HOME)/.claude/plugins/installed_plugins.json"
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/agents,$(HOME)/.claude/agents)
	@if [ -L "$(HOME)/.claude/hooks" ]; then $(RM) "$(HOME)/.claude/hooks"; fi
	@mkdir -p "$(HOME)/.claude/hooks"
	@find "$(ROOTDIR)/agent/harnesses/claude/hooks" -maxdepth 1 -name "*.sh" \
		-exec ln -sfvn {} "$(HOME)/.claude/hooks/" \;
	@find "$(ROOTDIR)/agent/hooks/claude" -maxdepth 1 -name "*.sh" \
		-exec ln -sfvn {} "$(HOME)/.claude/hooks/" \;
	@find "$(HOME)/.claude/hooks" -maxdepth 1 -type l ! -exec test -e {} \; -delete
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/skills,$(HOME)/.claude/skills)
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/rules,$(HOME)/.claude/rules)
	ln -sfvn "$(ROOTDIR)/agent/RTK.md" "$(HOME)/.claude/RTK.md"
	@if [ -f "$(ROOTDIR)/.trail/hook.cjs" ]; then \
		mkdir -p "$(HOME)/.claude/helpers"; \
		ln -sfvn "$(ROOTDIR)/.trail/hook.cjs" "$(HOME)/.claude/helpers/graft-hooks.cjs"; \
	fi
	@pass_claude="$(HOME)/go/src/github.com/kpango/pass/claude"; \
	mkdir -p "$${pass_claude}/projects"; \
	test -f "$${pass_claude}/history.jsonl" || touch "$${pass_claude}/history.jsonl"; \
	$(call LINK_DIR_FUNC,$${pass_claude}/projects,$(HOME)/.claude/projects); \
	if [ -f "$(HOME)/.claude/history.jsonl" ] && [ ! -L "$(HOME)/.claude/history.jsonl" ]; then \
		cat "$(HOME)/.claude/history.jsonl" >> "$${pass_claude}/history.jsonl" && $(RM) "$(HOME)/.claude/history.jsonl"; \
	fi; \
	ln -sfvn "$${pass_claude}/history.jsonl" "$(HOME)/.claude/history.jsonl"; \
	echo "linked: ~/.claude/projects -> $${pass_claude}/projects"; \
	echo "linked: ~/.claude/history.jsonl -> $${pass_claude}/history.jsonl"
	@echo "Sharing Claude session: $(ROOT_HOME)/.claude -> $(HOME)/.claude"
	@if ! sudo mountpoint -q $(ROOT_HOME)/.claude 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.claude && sudo ln -sfvn "$(HOME)/.claude" $(ROOT_HOME)/.claude; \
	fi
	sudo ln -sfvn "$(ROOTDIR)/gitconfig"                   $(ROOT_HOME)/.gitconfig

## Deploy Oh My Pi (OMP) config inside a Docker build layer (no sudo, copies not symlinks)
omp/docker/install:
	install -d -m 700 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(HOME)/.omp" \
		"$(HOME)/.omp/agent" \
		"$(HOME)/.omp/agent/agents" \
		"$(HOME)/.omp/agent/skills" \
		"$(HOME)/.omp/agent/prompts" \
		"$(HOME)/.omp/agent/extensions" \
		"$(HOME)/.omp/agent/extensions/lib" \
		"$(HOME)/.omp/agent/rules" \
		"$(HOME)/.omp/agent/themes" \
		"$(HOME)/.omp/agent/sessions" \
		"$(HOME)/.local/bin"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/config.yml" "$(HOME)/.omp/agent/config.yml"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/models.yml" "$(HOME)/.omp/agent/models.yml"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/lsp.yml" "$(HOME)/.omp/agent/lsp.yml"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/dap.json" "$(HOME)/.omp/agent/dap.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/sol-pi.json" "$(HOME)/.omp/agent/sol-pi.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/keybindings.json" "$(HOME)/.omp/agent/keybindings.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/model-routing.json" "$(HOME)/.omp/agent/model-routing.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/AGENTS.md" "$(HOME)/.omp/agent/AGENTS.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/omp/SYSTEM.md" "$(HOME)/.omp/agent/SYSTEM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM.md" "$(HOME)/.omp/agent/SWARM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM_REFERENCES.md" "$(HOME)/.omp/agent/SWARM_REFERENCES.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/RTK.md" "$(HOME)/.omp/agent/RTK.md"
	install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/scripts/sandbox/pa-sandbox" "$(HOME)/.local/bin/pa-sandbox"
	find "$(ROOTDIR)/agent/rules" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/rules/" \;
	find "$(ROOTDIR)/agent/harnesses/omp/extensions" -maxdepth 1 -type f \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/extensions/" \;
	find "$(ROOTDIR)/agent/hooks/omp" -maxdepth 1 -type f \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/extensions/" \;
	find "$(ROOTDIR)/agent/harnesses/omp/extensions/lib" -maxdepth 1 -type f \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/extensions/lib/" \;
	find "$(ROOTDIR)/agent/hooks/omp/lib" -maxdepth 1 -type f \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/extensions/lib/" \;
	find "$(ROOTDIR)/agent/harnesses/omp/prompts" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/prompts/" \;
	find "$(ROOTDIR)/agent/harnesses/omp/themes" -maxdepth 1 -name "*.json" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/themes/" \;
	find "$(ROOTDIR)/agent/agents" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.omp/agent/agents/" \;
	@install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.omp/agent/skills"
	@for skill_dir in "$(ROOTDIR)/agent/skills"/*/; do \
		skill_name=$$(basename "$$skill_dir"); \
		[ "$$skill_name" = "synced" ] && continue; \
		dest="$(HOME)/.omp/agent/skills/$${skill_name}"; \
		$(RM) "$$dest"; \
		$(CP) "$${skill_dir}" "$$dest"; \
		find "$$dest" -type d -exec chmod 755 {} \; ; \
		find "$$dest" -type f -exec chmod 644 {} \; ; \
		find "$$dest" -type f -name "*.sh" -exec chmod 755 {} \; ; \
		chown -R "$(USER_ID):$(GROUP_ID)" "$$dest"; \
	done

## symlink ~/.omp/agent/ config files (never settings.json), agents, skills, extensions, rules, prompts, and themes
omp/install: dotfiles/install
	mkdir -p "$(HOME)/.omp/agent/sessions"
	# config.yml is runtime state (OMP rewrites modelRoles.default/comments on every
	# launch), so it is seeded as a regular file instead of a symlink: a symlink makes
	# OMP's normalization dirty the repository. Reinstall refreshes it from canonical
	# while keeping the persisted modelRoles.default.
	@cfg_dst="$(HOME)/.omp/agent/config.yml"; \
	cfg_src="$(ROOTDIR)/agent/harnesses/omp/config.yml"; \
	prev_default="$$( [ -f "$$cfg_dst" ] && sed -n 's/^  default: //p' "$$cfg_dst" | head -n1 )"; \
	tmp="$$(mktemp)"; \
	install -m 600 "$$cfg_src" "$$tmp"; \
	if [ -n "$$prev_default" ]; then \
		sed -i "s|^  default: .*|  default: $$prev_default|" "$$tmp"; \
	fi; \
	$(RM) -f "$$cfg_dst"; \
	mv "$$tmp" "$$cfg_dst"
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/agents,$(HOME)/.omp/agent/agents)
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/skills,$(HOME)/.omp/agent/skills)
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/rules,$(HOME)/.omp/agent/rules)
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/harnesses/omp/prompts,$(HOME)/.omp/agent/prompts)
	@if [ -L "$(HOME)/.omp/agent/extensions" ]; then $(RM) "$(HOME)/.omp/agent/extensions"; fi
	@mkdir -p "$(HOME)/.omp/agent/extensions/lib"
	@find "$(ROOTDIR)/agent/harnesses/omp/extensions" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.omp/agent/extensions/" \;
	@find "$(ROOTDIR)/agent/hooks/omp" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.omp/agent/extensions/" \;
	@find "$(ROOTDIR)/agent/harnesses/omp/extensions/lib" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.omp/agent/extensions/lib/" \;
	@find "$(ROOTDIR)/agent/hooks/omp/lib" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.omp/agent/extensions/lib/" \;
	@find "$(HOME)/.omp/agent/extensions" -maxdepth 1 -type l ! -exec test -e {} \; -delete
	@find "$(HOME)/.omp/agent/extensions/lib" -maxdepth 1 -type l ! -exec test -e {} \; -delete
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/harnesses/omp/themes,$(HOME)/.omp/agent/themes)
	@python3 "$(ROOTDIR)/agent/scripts/omp-auth-dedupe.py" --apply
	@echo "Sharing OMP session: $(ROOT_HOME)/.omp -> $(HOME)/.omp"
	@if ! sudo mountpoint -q $(ROOT_HOME)/.omp 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.omp && sudo ln -sfvn "$(HOME)/.omp" $(ROOT_HOME)/.omp; \
	fi

## disable superseded duplicate OMP api_key logins (backup taken; keeps newest per provider)
omp/auth/dedupe:
	python3 "$(ROOTDIR)/agent/scripts/omp-auth-dedupe.py" --apply

## fetch public/local model feeds and run daily Pareto optimization across tiers
omp/models/update:
	python3 "$(ROOTDIR)/agent/scripts/update-model-catalog.py" --fetch --optimize --report

## deterministically sync derived harness configs from agent/models/catalog.json
omp/models/sync:
	python3 "$(ROOTDIR)/agent/scripts/update-model-catalog.py" --sync-only --report

## enable and start daily model catalog update systemd user timer (host only; skips/refuses inside Docker)
omp/models/timer/install: dotfiles/install
	@if [ -f /.dockerenv ]; then \
		echo "omp/models/timer/install: skipped inside Docker — run 'make omp/models/timer/install' on the host" >&2; \
		exit 1; \
	fi
	$(ENSURE_USER_SYSTEMD)
	$(SYSTEMCTL_USER) daemon-reload
	$(SYSTEMCTL_USER) enable --now omp-model-catalog-update.timer

## Deploy Antigravity (AGY) config inside a Docker build layer (no sudo, copies not symlinks)
agy/docker/install:
	install -d -m 700 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(HOME)/.agy" \
		"$(HOME)/.agy/policies" \
		"$(HOME)/.agy/agents" \
		"$(HOME)/.agy/skills" \
		"$(HOME)/.agy/rules" \
		"$(HOME)/.agy/hooks" \
		"$(HOME)/.gemini" \
		"$(HOME)/.gemini/antigravity-cli" \
		"$(HOME)/.gemini/antigravity-cli/conversations" \
		"$(HOME)/.gemini/antigravity-cli/brain" \
		"$(HOME)/.gemini/antigravity-cli/annotations" \
		"$(HOME)/.gemini/antigravity-cli/cache" \
		"$(HOME)/.gemini/antigravity" \
		"$(HOME)/.gemini/antigravity/conversations" \
		"$(HOME)/.gemini/policies" \
		"$(HOME)/.gemini/config" \
		"$(HOME)/.gemini/config/projects" \
		"$(HOME)/.gemini/config/skills" \
		"$(HOME)/.gemini/config/rules" \
		"$(HOME)/.gemini/config/agents" \
		"$(HOME)/.gemini/skills" \
		"$(HOME)/.gemini/rules" \
		"$(HOME)/.gemini/agents" \
		"$(HOME)/.gemini/hooks" \
		"$(HOME)/.gemini/memory" \
		"$(HOME)/.gemini/extensions" \
		"$(HOME)/.antigravity" \
		"$(HOME)/.config/Antigravity" \
		"$(HOME)/.config/antigravity" \
		"$(HOME)/.cache/antigravity"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/settings.json" "$(HOME)/.agy/settings.json"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/settings.json" "$(HOME)/.gemini/settings.json"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/settings.json" "$(HOME)/.gemini/antigravity-cli/settings.json"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/mcp_config.json" "$(HOME)/.agy/mcp_config.json"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/mcp_config.json" "$(HOME)/.gemini/config/mcp_config.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/model-routing.json" "$(HOME)/.agy/model-routing.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/model-routing.json" "$(HOME)/.gemini/model-routing.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/model-routing.json" "$(HOME)/.gemini/config/model-routing.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/AGENTS.md" "$(HOME)/.agy/AGENTS.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/AGENTS.md" "$(HOME)/.gemini/AGENTS.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/AGENTS.md" "$(HOME)/.gemini/GEMINI.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/SYSTEM.md" "$(HOME)/.agy/SYSTEM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/SYSTEM.md" "$(HOME)/.gemini/SYSTEM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM.md" "$(HOME)/.agy/SWARM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM.md" "$(HOME)/.gemini/SWARM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM_REFERENCES.md" "$(HOME)/.agy/SWARM_REFERENCES.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM_REFERENCES.md" "$(HOME)/.gemini/SWARM_REFERENCES.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/RTK.md" "$(HOME)/.agy/RTK.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/RTK.md" "$(HOME)/.gemini/RTK.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/policies/policy.toml" "$(HOME)/.agy/policies/rules.toml"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/policies/policy.toml" "$(HOME)/.agy/policies/policy.toml"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/policies/policy.toml" "$(HOME)/.gemini/policies/rules.toml"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/policies/policy.toml" "$(HOME)/.gemini/policies/policy.toml"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/hooks/hooks.json" "$(HOME)/.gemini/config/hooks.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/hooks/hooks.json" "$(HOME)/.gemini/antigravity-cli/hooks.json"
	find "$(ROOTDIR)/agent/rules" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.agy/rules/" \; \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.gemini/config/rules/" \; \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.gemini/rules/" \;
	find "$(ROOTDIR)/agent/harnesses/agy/hooks" -maxdepth 1 -name "*.sh" \
		-exec install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.agy/hooks/" \; \
		-exec install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.gemini/hooks/" \;
	find "$(ROOTDIR)/agent/hooks/agy" -maxdepth 1 -name "*.sh" \
		-exec install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.agy/hooks/" \; \
		-exec install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.gemini/hooks/" \;
	find "$(ROOTDIR)/agent/agents" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.agy/agents/" \; \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.gemini/config/agents/" \; \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.gemini/agents/" \;
	@install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.agy/skills" "$(HOME)/.gemini/config/skills" "$(HOME)/.gemini/skills"
	@for skill_dir in "$(ROOTDIR)/agent/skills"/*/; do \
		skill_name=$$(basename "$$skill_dir"); \
		[ "$$skill_name" = "synced" ] && continue; \
		for target_dir in "$(HOME)/.agy/skills" "$(HOME)/.gemini/config/skills" "$(HOME)/.gemini/skills"; do \
			dest="$${target_dir}/$${skill_name}"; \
			$(RM) "$$dest"; \
			$(CP) "$${skill_dir}" "$$dest"; \
			find "$$dest" -type d -exec chmod 755 {} \; ; \
			find "$$dest" -type f -exec chmod 644 {} \; ; \
			find "$$dest" -type f -name "*.sh" -exec chmod 755 {} \; ; \
			chown -R "$(USER_ID):$(GROUP_ID)" "$$dest"; \
		done; \
	done

## deploy ~/.agy and ~/.gemini for Antigravity CLI: merged 0600 ~/.gemini/antigravity-cli/settings.json
## (preserving user runtime keys such as model and trustedWorkspaces across atomic CLI rewrites),
## persistent conversation/history/secret dirs, and per-entry hook symlinks via agent/harnesses/agy/install.sh.
agy/install: dotfiles/install
	@ROOTDIR='$(ROOTDIR)' HOME='$(HOME)' bash '$(ROOTDIR)/agent/harnesses/agy/install.sh'
	@echo "Sharing Antigravity sessions: $(ROOT_HOME)/{.agy,.gemini,.antigravity,.config/antigravity,.cache/antigravity} -> $(HOME)/..."
	@if ! sudo mountpoint -q $(ROOT_HOME)/.agy 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.agy && sudo ln -sfvn "$(HOME)/.agy" $(ROOT_HOME)/.agy; \
	fi
	@if ! sudo mountpoint -q $(ROOT_HOME)/.gemini 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.gemini && sudo ln -sfvn "$(HOME)/.gemini" $(ROOT_HOME)/.gemini; \
	fi
	@if ! sudo mountpoint -q $(ROOT_HOME)/.antigravity 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.antigravity && sudo ln -sfvn "$(HOME)/.antigravity" $(ROOT_HOME)/.antigravity; \
	fi
	@sudo mkdir -p $(ROOT_HOME)/.config $(ROOT_HOME)/.cache
	@if ! sudo mountpoint -q $(ROOT_HOME)/.config/antigravity 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.config/antigravity && sudo ln -sfvn "$(HOME)/.config/antigravity" $(ROOT_HOME)/.config/antigravity; \
	fi
	@if ! sudo mountpoint -q $(ROOT_HOME)/.cache/antigravity 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.cache/antigravity && sudo ln -sfvn "$(HOME)/.cache/antigravity" $(ROOT_HOME)/.cache/antigravity; \
	fi

## Deploy Hermes Agent + Oh My Hermes (OMH) config inside a Docker build layer (no sudo, copies not symlinks)
hermes/docker/install:
	install -d -m 700 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(HOME)/.hermes" \
		"$(HOME)/.hermes/profiles" \
		"$(HOME)/.hermes/skills" \
		"$(HOME)/.omh" \
		"$(HOME)/.omh/routing" \
		"$(HOME)/.local/bin"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/hermes/config.yaml" "$(HOME)/.hermes/config.yaml"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/hermes/SOUL.md" "$(HOME)/.hermes/SOUL.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/hermes/model-routing.json" "$(HOME)/.hermes/model-routing.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/hermes/omh/category-maestro.json" "$(HOME)/.omh/routing/category-maestro.json"
	install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/scripts/sandbox/pa-sandbox" "$(HOME)/.local/bin/pa-sandbox"
	@set -e; for prof in "$(ROOTDIR)/agent/harnesses/hermes/profiles"/*; do \
		[ -d "$$prof" ] || continue; \
		prof_name=$$(basename "$$prof"); \
		dest="$(HOME)/.hermes/profiles/$${prof_name}"; \
		$(RM) "$$dest"; \
		$(CP) "$$prof" "$$dest"; \
		chmod 700 "$$dest"; \
		find "$$dest" -type f -exec chmod 600 {} +; \
		chown -R "$(USER_ID):$(GROUP_ID)" "$$dest"; \
	done
	@set -e; for skill_dir in "$(ROOTDIR)/agent/skills"/*/; do \
		skill_name=$$(basename "$$skill_dir"); \
		[ "$$skill_name" = "synced" ] && continue; \
		dest="$(HOME)/.hermes/skills/$${skill_name}"; \
		$(RM) "$$dest"; \
		$(CP) "$${skill_dir}" "$$dest"; \
		find "$$dest" -type d -exec chmod 755 {} +; \
		find "$$dest" -type f -exec chmod 644 {} +; \
		find "$$dest" -type f -name "*.sh" -exec chmod 755 {} +; \
		chown -R "$(USER_ID):$(GROUP_ID)" "$$dest"; \
	done

## symlink ~/.hermes/ skills, per-profile dirs, and ~/.omh/routing/, and share session with root
hermes/install: dotfiles/install
	mkdir -p "$(HOME)/.hermes/profiles" "$(HOME)/.omh/routing"
	@$(call LINK_DIR_FUNC,$(ROOTDIR)/agent/skills,$(HOME)/.hermes/skills)
	@for prof in "$(ROOTDIR)/agent/harnesses/hermes/profiles"/*; do \
		[ -d "$$prof" ] || continue; \
		ln -sfvn "$$prof" "$(HOME)/.hermes/profiles/$$(basename "$$prof")"; \
	done
	@echo "Sharing Hermes session: $(ROOT_HOME)/.hermes -> $(HOME)/.hermes"
	@if ! sudo mountpoint -q $(ROOT_HOME)/.hermes 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.hermes && sudo ln -sfvn "$(HOME)/.hermes" $(ROOT_HOME)/.hermes; \
	fi
	@if ! sudo mountpoint -q $(ROOT_HOME)/.omh 2>/dev/null; then \
		sudo $(RM) $(ROOT_HOME)/.omh && sudo ln -sfvn "$(HOME)/.omh" $(ROOT_HOME)/.omh; \
	fi

## enable and start hermes-gateway user systemd service (host only; skips/refuses inside Docker)
hermes/systemd/install: dotfiles/install
	@if [ -f /.dockerenv ]; then \
		echo "hermes/systemd/install: skipped inside Docker — run 'make hermes/systemd/install' on the host" >&2; \
		exit 1; \
	fi
	$(ENSURE_USER_SYSTEMD)
	$(SYSTEMCTL_USER) daemon-reload
	$(SYSTEMCTL_USER) enable --now hermes-gateway.service

## register the pre-check-gated Hermes cron jobs from agent/harnesses/hermes/cron/jobs.json (idempotent; needs the hermes CLI;
## cron fires only while hermes-gateway.service runs). Preview with: bash agent/scripts/bot/hermes-cron-install.sh --dry-run
hermes/cron/install: hermes/install
	@bash '$(ROOTDIR)/agent/scripts/bot/hermes-cron-install.sh'

## read-only: exit 1 unless every cron gate is current and every job is listed
hermes/cron/check:
	@bash '$(ROOTDIR)/agent/scripts/bot/hermes-cron-install.sh' --check

## enable and start agent-decide user systemd service (hook decision daemon; host only; refuses inside Docker)
agent-decide/systemd/install: dotfiles/install
	@if [ -f /.dockerenv ]; then \
		echo "agent-decide/systemd/install: skipped inside Docker — run 'make agent-decide/systemd/install' on the host" >&2; \
		exit 1; \
	fi
	$(ENSURE_USER_SYSTEMD)
	$(SYSTEMCTL_USER) daemon-reload
	$(SYSTEMCTL_USER) enable --now agent-decide.service

## remove all dotfile symlinks/copies from $HOME and clean generated config files
dotfiles/clean: dotfiles/perm
	$(eval TMP_DIR := $(shell mktemp -d))
	trap '$(RM) "$(TMP_DIR)"' EXIT; \
	jq . $(ROOTDIR)/arch/waybar.json > $(TMP_DIR)/waybar.json.tmp && mv $(TMP_DIR)/waybar.json.tmp $(ROOTDIR)/arch/waybar.json || \
		{ echo "Error: failed to reformat arch/waybar.json (jq parse or mv failed) — leaving it untouched" >&2; exit 1; }
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$(HOME)/$$dest,sudo); \
	done
	@$(call CLEAN_FUNC,/etc/docker/config.json,sudo)
	@$(call CLEAN_FUNC,/etc/docker/daemon.json,sudo)
	@$(call CLEAN_FUNC,/etc/containerd/config.toml,sudo)

## fix file/dir permissions and normalise line endings across the repo
dotfiles/perm:
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type d -exec sudo chmod 755 {} +
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type f -exec sudo chmod 644 {} +
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type f -name '*.sh' -exec sudo chmod 755 {} +
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type f -name '*.py' -exec sudo chmod 755 {} +
	sudo chmod 755 $(ROOTDIR)/herdr/shell
	sudo chmod 755 $(ROOTDIR)/sway/scripts/import-gsettings 2>/dev/null || true
	sudo chown -R $(SYS_USER):$(GROUP_ID) $(ROOTDIR)
	\find $(ROOTDIR) \
		-type d \( -name '.git' -o -name '.worktrees' -o -name '.claude' \) -prune \
		-o -type f \( \
		  -name '*.zsh' -o -name '*.sh'   -o -name '*.conf' -o \
		  -name '*.txt' -o -name '*.md'   -o -name '*.mk'   -o \
		  -name '*.py'  -o -name '*.nix'  -o -name '*.toml' -o \
		  -name '*.yaml' -o -name '*.yml' -o -name '*.json' -o \
		  -name '*.service' -o -name '*.rules' -o -name '*.desktop' -o \
		  -name 'zshrc' -o -name 'zshenv' -o -name 'zprofile' -o \
		  -name 'gitconfig' -o -name 'gitattributes' -o \
		  -name 'sshconfig' -o -name 'editorconfig' -o -name 'Makefile' \
		\) -not -name 'tmux.conf' -exec nkf -Lu -w --overwrite {} +
	sudo chmod 755 $(ROOTDIR)/tmux.conf.d/disk-info 2>/dev/null || true

## build and install the Go pinentry-tmux binary to /usr/local/bin
## Detects Go across Arch, macOS Homebrew, and PATH. Also invoked by mac/install
## so gpg-agent.conf's pinentry-program (see darwin.nix) resolves on first setup.
pinentry/install:
	@$(FIND_GO); \
	if [ -n "$$_go" ]; then \
	    cd $(ROOTDIR)/tmux.conf.d/pinentry-tmux \
	    && GOROOT="$$_root" GOEXPERIMENT=runtimesecret "$$_go" build -trimpath -ldflags="-s -w" -buildvcs=false -o /tmp/pinentry-tmux . \
	    && sudo install -m 755 /tmp/pinentry-tmux /usr/local/bin/pinentry-tmux \
	    && $(RM) /tmp/pinentry-tmux \
	    && echo "pinentry-tmux: installed /usr/local/bin/pinentry-tmux"; \
	elif [ "$(UNAME_S)" = Darwin ] && [ -z "$(PINENTRY_STRICT)" ]; then \
	    echo "pinentry-tmux: Go not found — skipped (mac/install builds it after nix/setup provides Go)"; \
	else \
	    echo "pinentry-tmux: Go not found — cannot build"; \
	    exit 1; \
	fi

## install or update pinentry-tmux from the published module (no local clone required)
pinentry/update:
	@$(FIND_GO); \
	if [ -n "$$_go" ]; then \
	    GOROOT="$$_root" GOEXPERIMENT=runtimesecret "$$_go" build -trimpath -ldflags="-s -w" -buildvcs=false -o /tmp/pinentry-tmux github.com/kpango/dotfiles/tmux.conf.d/pinentry-tmux@latest \
	    && sudo install -m 755 /tmp/pinentry-tmux /usr/local/bin/pinentry-tmux \
	    && $(RM) /tmp/pinentry-tmux \
	    && echo "pinentry-tmux: updated to latest at /usr/local/bin/pinentry-tmux"; \
	else \
	    echo "pinentry-tmux: Go not found — cannot update"; \
	    exit 1; \
	fi

## initialize .claude/graph/codegraph output dir and, if a real
## .codegraph/ exists from before this migration, move its data behind a
## symlink (CODEGRAPH_DIR only accepts a single path segment, so a multi-level
## output path needs this symlink indirection). Idempotent — safe to re-run.
## (Previously also initialized .claude/graph/graphify — removed with graphify's
## retirement.)
graph/init:
	@if [ -e "$(ROOTDIR)/.codegraph" ] && [ ! -d "$(ROOTDIR)/.codegraph" ] && [ ! -L "$(ROOTDIR)/.codegraph" ]; then \
		mv "$(ROOTDIR)/.codegraph" "$(ROOTDIR)/.codegraph.bak-$$(date +%s)"; \
		echo "warning: .codegraph was neither a directory nor a symlink — moved aside to .codegraph.bak-*"; \
	fi
	@if [ -d "$(ROOTDIR)/.codegraph" ] && [ ! -L "$(ROOTDIR)/.codegraph" ]; then \
		mkdir -p $(ROOTDIR)/.claude/graph; \
		mv "$(ROOTDIR)/.codegraph" "$(ROOTDIR)/.claude/graph/codegraph"; \
		echo "moved: .codegraph -> .claude/graph/codegraph"; \
	else \
		mkdir -p $(ROOTDIR)/.claude/graph/codegraph; \
	fi
	@if [ ! -L "$(ROOTDIR)/.codegraph" ]; then \
		ln -sfvn "$(ROOTDIR)/.claude/graph/codegraph" "$(ROOTDIR)/.codegraph"; \
	fi

## deploy Tailscale sshd config, apply node preferences, UDP GRO optimization, and enable sshd as fallback
tailscale/install:
	sudo mkdir -p /etc/ssh/sshd_config.d /etc/systemd/system/sshd.service.d
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/sshd_config.d/10-tailscale.conf,/etc/ssh/sshd_config.d/10-tailscale.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/systemd/sshd.service.d/tailscale.conf,/etc/systemd/system/sshd.service.d/tailscale.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/systemd/tailscale-gro.service,/etc/systemd/system/tailscale-gro.service,sudo)
	sudo systemctl daemon-reload
	sudo systemctl enable --now sshd.service
	sudo systemctl enable --now tailscale-gro.service
	bash $(ROOTDIR)/tailscale/setup.sh

## deploy network configs (sysctl, NM dispatcher, irqbalance) and restart services
## Idempotent: safe to run repeatedly without side effects.
## DNS: systemd-resolved is the sole resolver; NM delegates via dns=systemd-resolved;
##      Tailscale accept-dns registers .ts.net split DNS automatically.
network/install:
	sudo mkdir -p /etc/sysctl.d
	@$(call DEPLOY_FUNC,$(ROOTDIR)/network/nm/NetworkManager.conf,/etc/NetworkManager/NetworkManager.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/network/dns/resolved.conf,/etc/systemd/resolved.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/network/dns/resolv.dnsmasq.conf,/etc/resolv.dnsmasq.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/network/sysctl/sysctl.conf,/etc/sysctl.d/99-sysctl.conf,sudo)
	sudo $(CP) $(ROOTDIR)/network/nm/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo $(CP) $(ROOTDIR)/network/nm/nmcli-bond-auto-connect.sh   /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
	sudo $(CP) $(ROOTDIR)/network/nm/99-coalesce-x710              /etc/NetworkManager/dispatcher.d/99-coalesce-x710
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh \
	               /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh \
	               /etc/NetworkManager/dispatcher.d/99-coalesce-x710
	sudo chown root:root /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh \
	                     /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh \
	                     /etc/NetworkManager/dispatcher.d/99-coalesce-x710
	sudo sysctl -e -p /etc/sysctl.d/99-sysctl.conf
	sudo systemctl enable systemd-resolved
	sudo systemctl restart systemd-resolved
	sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
	sudo systemctl restart NetworkManager
	sudo systemctl restart irqbalance
	tailscale set --accept-dns=true 2>/dev/null || echo "warning: tailscale not running -- run 'sudo tailscale set --accept-dns=true' manually"
	@echo "network/install: done."

## [deprecated] use `make unifi/install` — the full UDM Pro SSoT in dotfiles/unifi/ supersedes network/unifi/
network/unifi/install:
	@echo "network/unifi/install is deprecated; use 'make unifi/install' (SSoT: dotfiles/unifi/)" >&2
	@exit 1

## deploy all dotfiles, dev/env configs, AI harnesses (Claude/OMP/AGY/Hermes), codegraph link, and Arch system configs
arch/install: dotfiles/install claude/install omp/install agy/install hermes/install graph/init
	$(ARCH_PREP)
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo $(CP) "$(ROOTDIR)/$$src" "$$dest"; \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$$dest,sudo); \
	done
	$(ARCH_POST)

## arch/install variant for ThinkPad P1 (adds P1 waybar CSS + NVIDIA drivers)
arch/p1/install: arch/install
	$(RM) $(HOME)/.config/waybar/style.css
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/waybar_p1.css,$(HOME)/.config/waybar/style.css,)
	$(NVIDIA_INSTALL)
	$(ARCH_P1_POST)

## deploy all dotfiles, dev/env/AI configs, and desktop workstation configs (NVIDIA, network, tmpfiles, greetd, boot)
arch/desk/install: arch/install
	$(NVIDIA_INSTALL)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/network/nm/desk/70-persistent-network.rules,/etc/udev/rules.d/70-persistent-network.rules,sudo)
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$$dest,sudo); \
	done
	@echo "$$ARCH_DESK_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo $(CP) "$(ROOTDIR)/$$src" "$$dest"; \
	done
	$(ARCH_DESK_POST)

## diff dotfiles vs live system for desk-specific configs (read-only)
arch/desk/audit:
	@echo "=== Boot loader ==="
	@sudo diff "$(ROOTDIR)/arch/loader/entries/arch.conf" /boot/loader/entries/arch.conf \
		&& echo "  OK: loader/entries/arch.conf" || echo "  DRIFT: loader/entries/arch.conf"
	@sudo diff "$(ROOTDIR)/arch/loader/loader.conf" /boot/loader/loader.conf \
		&& echo "  OK: loader/loader.conf" || echo "  DRIFT: loader/loader.conf"
	@echo "=== initramfs ==="
	@diff "$(ROOTDIR)/arch/mkinitcpio.conf" /etc/mkinitcpio.conf \
		&& echo "  OK: mkinitcpio.conf" || echo "  DRIFT: mkinitcpio.conf"
	@echo "=== modprobe.d ==="
	@diff "$(ROOTDIR)/arch/modprobe.d/nobeep.conf" /etc/modprobe.d/nobeep.conf \
		&& echo "  OK: modprobe.d/nobeep.conf" || echo "  DRIFT: modprobe.d/nobeep.conf"
	@diff "$(ROOTDIR)/arch/modprobe.d/blacklist-nouveau.conf" /etc/modprobe.d/blacklist-nouveau.conf \
		&& echo "  OK: modprobe.d/blacklist-nouveau.conf" || echo "  DRIFT: modprobe.d/blacklist-nouveau.conf"
	@diff "$(ROOTDIR)/arch/modprobe.d/nowatchdog.conf" /etc/modprobe.d/nowatchdog.conf \
		&& echo "  OK: modprobe.d/nowatchdog.conf" || echo "  DRIFT: modprobe.d/nowatchdog.conf"
	@echo "=== fstab ==="
	@sudo diff "$(ROOTDIR)/arch/desk/fstab" /etc/fstab \
		&& echo "  OK: fstab" || echo "  DRIFT: fstab"
	@echo "=== modules-load.d ==="
	@diff "$(ROOTDIR)/arch/modules-load.d/erofs.conf" /etc/modules-load.d/erofs.conf \
		&& echo "  OK: modules-load.d/erofs.conf" || echo "  DRIFT: modules-load.d/erofs.conf"
	@diff "$(ROOTDIR)/arch/modules-load.d/i2c_dev.conf" /etc/modules-load.d/i2c_dev.conf \
		&& echo "  OK: modules-load.d/i2c_dev.conf" || echo "  DRIFT: modules-load.d/i2c_dev.conf"

arch/clean:
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$(HOME)/$$dest,sudo); \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$$dest,sudo); \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$$dest,sudo); \
	done
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$$dest,sudo); \
	done
	@echo "$$ARCH_DESK_SUDO_CP_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$$dest,sudo); \
	done
	@$(call CLEAN_FUNC,/etc/modprobe.d/nvidia-tweaks.conf,sudo)
	@$(call CLEAN_FUNC,/etc/modules-load.d/nvidia-uvm.conf,sudo)
	@$(call CLEAN_FUNC,/etc/udev/rules.d/60-nvidia.rules,sudo)
	@$(call CLEAN_FUNC,/etc/cdi/nvidia.yaml,sudo)
	@$(call CLEAN_FUNC,$(HOME)/.config/waybar/style.css,sudo)
	@$(call CLEAN_FUNC,/etc/udev/rules.d/70-persistent-network.rules,sudo)

## install macOS Homebrew packages and apply dotfiles + Claude config + nix-darwin
## config in one shot (runs dotfiles/install, claude/install, then nix/setup for
## MAC_NIX_HOST_NAME). Prefer the m1/install, m1air/install, m3/install aliases
## below over passing MAC_NIX_HOST_NAME directly.
mac/install: dotfiles/install claude/install omp/install agy/install hermes/install
	$(MAC_PREP)
	# No docker/daemon.json deployment here any more — apple/container (see
	# nix/modules/darwin/containerization.nix) replaces colima/Docker entirely on macOS
	# and doesn't read Docker's config.json/daemon.json. MAC_PREP above still removes any
	# leftover files from a pre-migration install.
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		$(RM) "$(HOME)/Library/LaunchAgents/$$agent"; \
		$(CP) "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo $(RM) $(ROOTDIR)/nvim/lua/lua
	@$(MAKE) nix/setup ROOTDIR='$(ROOTDIR)' NIX_HOST_NAME=$(MAC_NIX_HOST_NAME)
	@# After nix/setup so a fresh Mac (no Go before Nix) still gets pinentry-tmux.
	@# This make process still has the pre-Nix PATH, so take PATH from a fresh zsh,
	@# which loads whatever environment the system now configures (nix-darwin's
	@# /etc/zshenv) — no Nix paths spelled out here. Strict: a missing Go is an error.
	@# Keeps the current PATH if zsh is missing or fails: an empty PATH would hide
	@# make itself ("make: not found"), and this line runs even under `make -n`.
	@PATH="$$(zsh -c 'printf %s "$$PATH"' 2>/dev/null || printf %s "$$PATH")" $(MAKE) pinentry/install ROOTDIR='$(ROOTDIR)' PINENTRY_STRICT=1

## mac/install pinned to the MacBook Pro (M1, account "yusukekato") nix-darwin host
m1/install:
	@$(MAKE) mac/install MAC_NIX_HOST_NAME=macbook-pro-m1

## mac/install pinned to the MacBook Air (M1) nix-darwin host
m1air/install:
	@$(MAKE) mac/install MAC_NIX_HOST_NAME=macbook-air-m1

## mac/install pinned to the MacBook Pro (M3) nix-darwin host
m3/install:
	@$(MAKE) mac/install MAC_NIX_HOST_NAME=macbook-pro-m3

mac/clean:
	@$(call CLEAN_FUNC,$(HOME)/.docker/config.json,sudo)
	@$(call CLEAN_FUNC,/etc/docker/config.json,sudo)
	@$(call CLEAN_FUNC,/etc/docker/daemon.json,sudo)
	@$(call CLEAN_FUNC,$(HOME)/.docker/daemon.json,sudo)

# ── Backward-compat aliases ───────────────────────────────────────────────────

link:           ; @$(MAKE) dotfiles/install
copy:           ; @$(MAKE) dotfiles/install MODE=copy
clean:          ; @$(MAKE) dotfiles/clean
perm:           ; @$(MAKE) dotfiles/perm
arch_link:      ; @$(MAKE) arch/install
arch_copy:      ; @$(MAKE) arch/install MODE=copy
arch_p1_link:   ; @$(MAKE) arch/p1/install
arch_p1_copy:   ; @$(MAKE) arch/p1/install MODE=copy
arch_desk_link: ; @$(MAKE) arch/desk/install
arch_desk_copy: ; @$(MAKE) arch/desk/install MODE=copy
mac_link:       ; @$(MAKE) mac/install
mac_copy:       ; @$(MAKE) mac/install MODE=copy
