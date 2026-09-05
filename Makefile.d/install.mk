.PHONY: dotfiles/install dotfiles/compile dotfiles/clean dotfiles/perm precompile/zsh \
        arch/install arch/p1/install arch/desk/install arch/desk/audit arch/clean \
        mac/install m1/install m1air/install m3/install mac/clean \
        claude/install claude/docker/install \
        pi/install pi/docker/install \
        agy/install agy/docker/install \
        codex/install primeagent/install \
        tailscale/install \
        network/install network/unifi/install \
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
			$(3) rm -rf "$(2)" && $(3) cp -r "$(1)" "$(2)", \
			if [ -d "$(2)" ] && [ ! -L "$(2)" ]; then \
				echo "Skipping existing directory: $(2)"; \
			else \
				$(3) rm -f "$(2)" 2>/dev/null || true; \
				$(3) ln -sfvn "$(1)" "$(2)"; \
			fi \
		); \
	}
endef

define CLEAN_FUNC
	[ -z "$(1)" ] || $(2) rm -rf "$(1)"
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

# ── Dotfiles map ──────────────────────────────────────────────────────────────

define DOTFILES_MAP
atuin/config.toml .config/atuin/config.toml
atuin/themes/zed_kpango.toml .config/atuin/themes/zed_kpango.toml
bin/xdg-open .local/bin/xdg-open
bin/xdg-open .local/bin/google-chrome
bin/xdg-open .local/bin/google-chrome-stable
bin/xdg-open .local/bin/open
bin/xdg-open .local/bin/x-www-browser
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
agent/harnesses/pi/AGENTS.md .pi/agent/AGENTS.md
agent/harnesses/pi/SYSTEM.md .pi/agent/SYSTEM.md
agent/SWARM.md .pi/agent/SWARM.md
agent/SWARM_REFERENCES.md .pi/agent/SWARM_REFERENCES.md
agent/RTK.md .pi/agent/RTK.md
agent/harnesses/pi/settings.json .pi/agent/settings.json
agent/harnesses/pi/models.json .pi/agent/models.json
agent/harnesses/pi/keybindings.json .pi/agent/keybindings.json
agent/harnesses/pi/mcp.json .pi/agent/mcp.json
agent/harnesses/pi/model-routing.json .pi/agent/model-routing.json
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
agent/harnesses/agy/SYSTEM.md .gemini/SYSTEM.md
agent/SWARM.md .gemini/SWARM.md
agent/SWARM_REFERENCES.md .gemini/SWARM_REFERENCES.md
agent/RTK.md .gemini/RTK.md
agent/harnesses/agy/settings.json .gemini/settings.json
agent/harnesses/agy/settings.json .gemini/antigravity-cli/settings.json
agent/harnesses/agy/policies/policy.toml .gemini/policies/rules.toml
agent/harnesses/agy/policies/policy.toml .gemini/policies/policy.toml
agent/harnesses/agy/mcp_config.json .gemini/config/mcp_config.json
agent/harnesses/agy/hooks/hooks.json .gemini/config/hooks.json
agent/harnesses/agy/model-routing.json .gemini/model-routing.json
agent/harnesses/agy/model-routing.json .gemini/config/model-routing.json
agent/AGENTS.md .codex/AGENTS.md
agent/harnesses/codex/config.toml .codex/config.toml
agent/harnesses/codex/model-routing.json .codex/model-routing.json
agent/harnesses/pi/AGENTS.md .prime/agent/AGENTS.md
agent/harnesses/primeagent/settings.json .prime/agent/settings.json
agent/harnesses/primeagent/models.json .prime/agent/models.json
agent/harnesses/primeagent/model-routing.json .prime/agent/model-routing.json
agent/harnesses/pi/keybindings.json .prime/agent/keybindings.json
agent/harnesses/pi/mcp.json .prime/agent/mcp.json
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
systemd/user/atuin.service .config/systemd/user/atuin.service
systemd/user/herdr.service .config/systemd/user/herdr.service
systemd/user/kanshi.service .config/systemd/user/kanshi.service
systemd/user/tmux.service .config/systemd/user/tmux.service
systemd/user/zsh-patina.service .config/systemd/user/zsh-patina.service
tmux.conf.d .tmux.conf.d
tmux.conf .tmux.conf
tmux.new-session .tmux.new-session
zfunc .zfunc
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
arch/psd.conf .config/psd/psd.conf
arch/sway.conf .config/sway/config
sway/scripts .config/sway/scripts
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
arch/makepkg.conf.d/zen2-custom.conf /etc/makepkg.conf.d/zen2-custom.conf
arch/modules-load.d/bbr.conf /etc/modules-load.d/bbr.conf
arch/modules-load.d/nf_conntrack.conf /etc/modules-load.d/nf_conntrack.conf
arch/modules-load.d/erofs.conf /etc/modules-load.d/erofs.conf
arch/modules-load.d/i2c_dev.conf /etc/modules-load.d/i2c_dev.conf
arch/modprobe.d/nobeep.conf /etc/modprobe.d/nobeep.conf
arch/pacman.conf /etc/pacman.conf
arch/sway.sh /etc/profile.d/sway.sh
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
arch/systemd/NetworkManager.service.d/capabilities.conf /etc/systemd/system/NetworkManager.service.d/capabilities.conf
arch/systemd/sshd.service.d/tailscale.conf /etc/systemd/system/sshd.service.d/tailscale.conf
arch/sshd_config.d/10-tailscale.conf /etc/ssh/sshd_config.d/10-tailscale.conf
arch/initcpio/install/acpi_override /etc/initcpio/install/acpi_override
endef
export ARCH_SUDO_LINK_MAP

define ARCH_SUDO_CP_MAP
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
arch/modprobe.d/blacklist-nouveau.conf /etc/modprobe.d/blacklist-nouveau.conf
arch/modprobe.d/blacklist-eeepc-wmi.conf /etc/modprobe.d/blacklist-eeepc-wmi.conf
arch/modprobe.d/nowatchdog.conf /etc/modprobe.d/nowatchdog.conf
arch/modprobe.d/thinkfan-desk.conf /etc/modprobe.d/thinkfan.conf
arch/systemd/nvidia-unload.service /etc/systemd/system/nvidia-unload.service
arch/tmpfiles.d/thp.conf /etc/tmpfiles.d/thp.conf
endef
export ARCH_DESK_SUDO_LINK_MAP

define ARCH_DESK_SUDO_CP_MAP
arch/acpi/DSDT.aml /etc/acpi_override/DSDT.aml
arch/acpi/SSDT7.aml /etc/acpi_override/SSDT7.aml
arch/desk/fstab /etc/fstab
arch/loader/entries/arch.conf /boot/loader/entries/arch.conf
arch/loader/loader.conf /boot/loader/loader.conf
endef
export ARCH_DESK_SUDO_CP_MAP

define ARCH_PREP
	@if [ ! -f /boot/vmlinuz-linux ]; then sudo rm -f /etc/mkinitcpio.d/linux.preset /etc/mkinitcpio.d/linux.preset.pacsave; fi
	sudo mkdir -p /etc/systemd/system/NetworkManager.service.d
	sudo mkdir -p /etc/systemd/system/sshd.service.d
	sudo mkdir -p /etc/acpi_override
	sudo mkdir -p /etc/initcpio/install
	sudo mkdir -p /etc/pacman.d/hooks
	sudo mkdir -p /var/cache/aur-src
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
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/99-coalesce-x710
	sudo chown root:root /etc/NetworkManager/dispatcher.d/99-coalesce-x710
	sudo chown -R 0:0 /etc/sudoers.d
	sudo chmod 750 /etc/sudoers.d
	sudo find /etc/sudoers.d -type f -exec chmod 0440 {} +
	sudo chmod +x /usr/local/bin/rebuild-aur-helpers.sh
	sudo chown root:root /usr/local/bin/rebuild-aur-helpers.sh
	sudo sysctl -e -p /etc/sysctl.d/99-sysctl.conf
	sudo systemctl daemon-reload
	loginctl enable-linger $(SYS_USER)
	systemctl --user daemon-reload
	systemctl --user enable --now atuin.service
	systemctl --user enable --now kanshi.service
	systemctl --user enable --now tmux.service
	systemctl --user enable --now zsh-patina.service
	sudo systemctl enable systemd-resolved
	sudo systemctl restart systemd-resolved
	sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
	sudo systemctl restart NetworkManager
	tailscale set --accept-dns=true 2>/dev/null || echo "warning: tailscale not running -- run 'sudo tailscale set --accept-dns=true' manually"
endef

define ARCH_P1_POST
	rm -rf $(HOME)/.config/psd
	mkdir $(HOME)/.config/psd
	sudo systemctl daemon-reload
endef

define ARCH_DESK_POST
	sudo mkdir -p /etc/cdi
	sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml 2>/dev/null || echo "warning: nvidia-ctk cdi generate skipped (reboot required after driver update)"
	sudo mkdir -p /etc/systemd/system/irqbalance.service.d
	sudo rm -rf /etc/systemd/system/irqbalance.service.d/override.conf
	sudo cp $(ROOTDIR)/arch/service/irqbalance.service /etc/systemd/system/irqbalance.service.d/override.conf
	sudo rm -rf /etc/NetworkManager/system-connections
	sudo mkdir -p /etc/NetworkManager/system-connections
	sudo cp $(ROOTDIR)/network/nm/desk/bond0.nmconnection /etc/NetworkManager/system-connections/bond0.nmconnection
	sudo cp $(ROOTDIR)/network/nm/desk/eth0.nmconnection /etc/NetworkManager/system-connections/eth0.nmconnection
	sudo cp $(ROOTDIR)/network/nm/desk/slave0.nmconnection /etc/NetworkManager/system-connections/slave0.nmconnection
	sudo cp $(ROOTDIR)/network/nm/desk/slave1.nmconnection /etc/NetworkManager/system-connections/slave1.nmconnection
	sudo chmod 700 /etc/NetworkManager/system-connections
	sudo find /etc/NetworkManager/system-connections -type f -exec chmod 600 {} +
	sudo chown -R root:root /etc/NetworkManager/system-connections
	sudo udevadm control --reload-rules
	sudo udevadm trigger
	sudo nmcli connection reload
	sudo systemctl daemon-reload
	sudo systemctl enable nvidia-unload.service
	sudo systemctl restart NetworkManager
	sudo systemd-tmpfiles --create /etc/tmpfiles.d/thp.conf
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
	sudo rm -rf \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
		$(HOME)/.docker/config.json \
		$(HOME)/.docker/daemon.json \
		$(HOME)/.gnupg/gpg-agent.conf \
		$(HOME)/.tmux.conf \
		$(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist \
		$(HOME)/Library/LaunchAgents/ulimit.plist
	# dotfiles/install (a prerequisite above) just symlinked .zshrc/.zshenv
	# straight from the dotfiles repo. On macOS nix-darwin's home-manager
	# activation (nix/setup below) is the final owner and generates its own
	# .zshrc/.zshenv (nix/modules/home/programs/zsh.nix) that differs
	# byte-for-byte from the raw repo file — and unlike other home-manager
	# entries, `force = true` can't rescue this one (see that module's
	# comment: home-manager's own dotDirRel="." key shape makes force a
	# no-op here). Removing dotfiles/install's copy lets home-manager place
	# its own without a "would be clobbered" collision. Plain rm, no sudo:
	# these are always just user-owned symlinks, never real file content.
	rm -f $(HOME)/.zshrc $(HOME)/.zshenv
	cp $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	cp $(ROOTDIR)/gpg-agent.conf $(HOME)/.gnupg/gpg-agent.conf
	sed -i.bak '/^#.*set-environment -g PATH/s/^#//' $(HOME)/.tmux.conf
	# gpg-agent.conf is left pointing at /usr/local/bin/pinentry-tmux (the
	# template default) — nix-darwin's home-manager activation (invoked by
	# nix/setup below) owns the final pinentry-program value from here.
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
	@$(call DEPLOY_FUNC,$(ROOTDIR)/nvidia/nvidia-tweaks.conf,/etc/modprobe.d/nvidia-tweaks.conf,sudo)
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
	    cp $(ROOTDIR)/tmux.conf.d/kube          $(HOME)/.zcache/tmux-kube; \
	    cp $(ROOTDIR)/tmux.conf.d/status-left   $(HOME)/.zcache/tmux-status-left; \
	    cp $(ROOTDIR)/tmux.conf.d/status-branch $(HOME)/.zcache/tmux-status-branch; \
	    cp $(ROOTDIR)/tmux.conf.d/short-path    $(HOME)/.zcache/tmux-short-path; \
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
	cp $(ROOTDIR)/tmux.conf.d/pl-right $(HOME)/.zcache/tmux-pl-right
	cp $(ROOTDIR)/tmux.conf.d/pl-left  $(HOME)/.zcache/tmux-pl-left
	chmod +x $(HOME)/.zcache/tmux-pl-right $(HOME)/.zcache/tmux-pl-left

## create symlinks (or copies) of all dotfiles into $HOME (MODE=link|copy)
dotfiles/install:
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); \
	done
ifneq ($(UNAME_S),Darwin)
	# Linux only: macOS uses apple/container (see nix/modules/darwin/containerization.nix),
	# which replaces Docker/containerd and doesn't read these files — see mac/install below.
	@$(call DEPLOY_FUNC,$(ROOTDIR)/dockers/config.json,/etc/docker/config.json,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/dockers/daemon.json,/etc/docker/daemon.json,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/containerd.toml,/etc/containerd/config.toml,sudo)
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
	find "$(ROOTDIR)/agent/agents" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.claude/agents/" \;
	@install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.claude/skills"
	@for skill_dir in "$(ROOTDIR)/agent/skills"/*/; do \
		skill_name=$$(basename "$$skill_dir"); \
		dest="$(HOME)/.claude/skills/$${skill_name}"; \
		rm -rf "$$dest"; \
		cp -R "$${skill_dir}" "$$dest"; \
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
	envsubst < "$(ROOTDIR)/agent/harnesses/claude/installed_plugins.json" > "$(HOME)/.claude/plugins/installed_plugins.json"
	ln -sfvn "$(ROOTDIR)/agent/agents" "$(HOME)/.claude/agents"
	@if [ -L "$(HOME)/.claude/hooks" ]; then rm -f "$(HOME)/.claude/hooks"; fi
	@mkdir -p "$(HOME)/.claude/hooks"
	@find "$(ROOTDIR)/agent/harnesses/claude/hooks" -maxdepth 1 -name "*.sh" \
		-exec ln -sfvn {} "$(HOME)/.claude/hooks/" \;
	@find "$(ROOTDIR)/agent/hooks/claude" -maxdepth 1 -name "*.sh" \
		-exec ln -sfvn {} "$(HOME)/.claude/hooks/" \;
	ln -sfvn "$(ROOTDIR)/agent/skills" "$(HOME)/.claude/skills"
	ln -sfvn "$(ROOTDIR)/agent/rules"   "$(HOME)/.claude/rules"
	ln -sfvn "$(ROOTDIR)/agent/RTK.md" "$(HOME)/.claude/RTK.md"
	@pass_claude="$(HOME)/go/src/github.com/kpango/pass/claude"; \
	mkdir -p "$${pass_claude}/projects"; \
	test -f "$${pass_claude}/history.jsonl" || touch "$${pass_claude}/history.jsonl"; \
	ln -sfvn "$${pass_claude}/projects"      "$(HOME)/.claude/projects"; \
	ln -sfvn "$${pass_claude}/history.jsonl" "$(HOME)/.claude/history.jsonl"; \
	echo "linked: ~/.claude/projects -> $${pass_claude}/projects"; \
	echo "linked: ~/.claude/history.jsonl -> $${pass_claude}/history.jsonl"
	@echo "Sharing Claude session: $(ROOT_HOME)/.claude -> $(HOME)/.claude"
	@if ! sudo mountpoint -q $(ROOT_HOME)/.claude 2>/dev/null; then \
		sudo rm -rf $(ROOT_HOME)/.claude && sudo ln -sfvn "$(HOME)/.claude" $(ROOT_HOME)/.claude; \
	fi
	sudo ln -sfvn "$(ROOTDIR)/gitconfig"                   $(ROOT_HOME)/.gitconfig
	sudo mkdir -p $(ROOT_HOME)/.agy/policies
	sudo ln -sfvn "$(ROOTDIR)/agent/harnesses/agy/settings.json"        $(ROOT_HOME)/.agy/settings.json
	sudo ln -sfvn "$(ROOTDIR)/agent/harnesses/agy/policies/policy.toml" $(ROOT_HOME)/.agy/policies/rules.toml

## Deploy Pi Coding Agent config inside a Docker build layer (no sudo, copies not symlinks)
pi/docker/install:
	install -d -m 700 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(HOME)/.pi" \
		"$(HOME)/.pi/agent" \
		"$(HOME)/.pi/agent/agents" \
		"$(HOME)/.pi/agent/skills" \
		"$(HOME)/.pi/agent/prompts" \
		"$(HOME)/.pi/agent/extensions" \
		"$(HOME)/.pi/agent/rules" \
		"$(HOME)/.pi/agent/themes" \
		"$(HOME)/.pi/agent/sessions"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/pi/settings.json" "$(HOME)/.pi/agent/settings.json"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/pi/models.json" "$(HOME)/.pi/agent/models.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/pi/AGENTS.md" "$(HOME)/.pi/agent/AGENTS.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/pi/SYSTEM.md" "$(HOME)/.pi/agent/SYSTEM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM.md" "$(HOME)/.pi/agent/SWARM.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/SWARM_REFERENCES.md" "$(HOME)/.pi/agent/SWARM_REFERENCES.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/RTK.md" "$(HOME)/.pi/agent/RTK.md"
	find "$(ROOTDIR)/agent/rules" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.pi/agent/rules/" \;
	find "$(ROOTDIR)/agent/harnesses/pi/extensions" -maxdepth 1 -name "*.ts" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.pi/agent/extensions/" \;
	find "$(ROOTDIR)/agent/hooks/pi" -maxdepth 1 -name "*.ts" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.pi/agent/extensions/" \;
	install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.pi/agent/extensions/lib"
	find "$(ROOTDIR)/agent/harnesses/pi/extensions/lib" -maxdepth 1 -name "*.ts" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.pi/agent/extensions/lib/" \;
	find "$(ROOTDIR)/agent/hooks/pi/lib" -maxdepth 1 -name "*.ts" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.pi/agent/extensions/lib/" \;
	find "$(ROOTDIR)/agent/harnesses/pi/prompts" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.pi/agent/prompts/" \;
	find "$(ROOTDIR)/agent/agents" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.pi/agent/agents/" \;
	@install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" "$(HOME)/.pi/agent/skills"
	@for skill_dir in "$(ROOTDIR)/agent/skills"/*/; do \
		skill_name=$$(basename "$$skill_dir"); \
		dest="$(HOME)/.pi/agent/skills/$${skill_name}"; \
		rm -rf "$$dest"; \
		cp -R "$${skill_dir}" "$$dest"; \
		find "$$dest" -type d -exec chmod 755 {} \; ; \
		find "$$dest" -type f -exec chmod 644 {} \; ; \
		find "$$dest" -type f -name "*.sh" -exec chmod 755 {} \; ; \
		chown -R "$(USER_ID):$(GROUP_ID)" "$$dest"; \
	done

## symlink ~/.pi/agent/ config files, agents, skills, extensions, rules, and prompts
pi/install: dotfiles/install
	mkdir -p "$(HOME)/.pi/agent/sessions"
	ln -sfvn "$(ROOTDIR)/agent/agents"  "$(HOME)/.pi/agent/agents"
	ln -sfvn "$(ROOTDIR)/agent/skills"     "$(HOME)/.pi/agent/skills"
	ln -sfvn "$(ROOTDIR)/agent/rules"   "$(HOME)/.pi/agent/rules"
	ln -sfvn "$(ROOTDIR)/agent/harnesses/pi/prompts"    "$(HOME)/.pi/agent/prompts"
	@if [ -L "$(HOME)/.pi/agent/extensions" ]; then rm -f "$(HOME)/.pi/agent/extensions"; fi
	@mkdir -p "$(HOME)/.pi/agent/extensions/lib"
	@find "$(ROOTDIR)/agent/harnesses/pi/extensions" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.pi/agent/extensions/" \;
	@find "$(ROOTDIR)/agent/hooks/pi" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.pi/agent/extensions/" \;
	@find "$(ROOTDIR)/agent/harnesses/pi/extensions/lib" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.pi/agent/extensions/lib/" \;
	@find "$(ROOTDIR)/agent/hooks/pi/lib" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.pi/agent/extensions/lib/" \;
	ln -sfvn "$(ROOTDIR)/agent/harnesses/pi/themes"     "$(HOME)/.pi/agent/themes"
	@echo "Sharing Pi session: $(ROOT_HOME)/.pi -> $(HOME)/.pi"
	@if ! sudo mountpoint -q $(ROOT_HOME)/.pi 2>/dev/null; then \
		sudo rm -rf $(ROOT_HOME)/.pi && sudo ln -sfvn "$(HOME)/.pi" $(ROOT_HOME)/.pi; \
	fi

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
		"$(HOME)/.gemini/policies" \
		"$(HOME)/.gemini/config" \
		"$(HOME)/.gemini/config/skills" \
		"$(HOME)/.gemini/config/rules" \
		"$(HOME)/.gemini/config/agents" \
		"$(HOME)/.gemini/skills" \
		"$(HOME)/.gemini/rules" \
		"$(HOME)/.gemini/agents" \
		"$(HOME)/.gemini/hooks"
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
		"$(ROOTDIR)/agent/harnesses/agy/AGENTS.md" "$(HOME)/.agy/AGENTS.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/agent/harnesses/agy/AGENTS.md" "$(HOME)/.gemini/AGENTS.md"
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
		for target_dir in "$(HOME)/.agy/skills" "$(HOME)/.gemini/config/skills" "$(HOME)/.gemini/skills"; do \
			dest="$${target_dir}/$${skill_name}"; \
			rm -rf "$$dest"; \
			cp -R "$${skill_dir}" "$$dest"; \
			find "$$dest" -type d -exec chmod 755 {} \; ; \
			find "$$dest" -type f -exec chmod 644 {} \; ; \
			find "$$dest" -type f -name "*.sh" -exec chmod 755 {} \; ; \
			chown -R "$(USER_ID):$(GROUP_ID)" "$$dest"; \
		done; \
	done

## symlink ~/.agy and ~/.gemini/ agents, skills, rules, hooks, and policy.toml
## (per-file config symlinks such as settings.json/AGENTS.md/SYSTEM.md are handled
## by dotfiles/install via DOTFILES_MAP, not here)
agy/install: dotfiles/install
	mkdir -p "$(HOME)/.agy/policies" "$(HOME)/.gemini/antigravity-cli" "$(HOME)/.gemini/config" "$(HOME)/.gemini/policies"
	ln -sfvn "$(ROOTDIR)/agent/agents"           "$(HOME)/.agy/agents"
	ln -sfvn "$(ROOTDIR)/agent/skills"           "$(HOME)/.agy/skills"
	ln -sfvn "$(ROOTDIR)/agent/rules"            "$(HOME)/.agy/rules"
	@if [ -L "$(HOME)/.agy/hooks" ]; then rm -f "$(HOME)/.agy/hooks"; fi
	@mkdir -p "$(HOME)/.agy/hooks"
	@find "$(ROOTDIR)/agent/harnesses/agy/hooks" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.agy/hooks/" \;
	@find "$(ROOTDIR)/agent/hooks/agy" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.agy/hooks/" \;
	ln -sfvn "$(ROOTDIR)/agent/harnesses/agy/policies/policy.toml" "$(HOME)/.agy/policies/policy.toml"
	ln -sfvn "$(ROOTDIR)/agent/skills"           "$(HOME)/.gemini/config/skills"
	ln -sfvn "$(ROOTDIR)/agent/rules"            "$(HOME)/.gemini/config/rules"
	ln -sfvn "$(ROOTDIR)/agent/agents"           "$(HOME)/.gemini/config/agents"
	ln -sfvn "$(ROOTDIR)/agent/skills"           "$(HOME)/.gemini/skills"
	ln -sfvn "$(ROOTDIR)/agent/rules"            "$(HOME)/.gemini/rules"
	ln -sfvn "$(ROOTDIR)/agent/agents"           "$(HOME)/.gemini/agents"
	@if [ -L "$(HOME)/.gemini/hooks" ]; then rm -f "$(HOME)/.gemini/hooks"; fi
	@mkdir -p "$(HOME)/.gemini/hooks"
	@find "$(ROOTDIR)/agent/harnesses/agy/hooks" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.gemini/hooks/" \;
	@find "$(ROOTDIR)/agent/hooks/agy" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.gemini/hooks/" \;
	@echo "Sharing Antigravity sessions: $(ROOT_HOME)/.agy -> $(HOME)/.agy and $(ROOT_HOME)/.gemini -> $(HOME)/.gemini"
	@if ! sudo mountpoint -q $(ROOT_HOME)/.agy 2>/dev/null; then \
		sudo rm -rf $(ROOT_HOME)/.agy && sudo ln -sfvn "$(HOME)/.agy" $(ROOT_HOME)/.agy; \
	fi
	@if ! sudo mountpoint -q $(ROOT_HOME)/.gemini 2>/dev/null; then \
		sudo rm -rf $(ROOT_HOME)/.gemini && sudo ln -sfvn "$(HOME)/.gemini" $(ROOT_HOME)/.gemini; \
	fi

## symlink ~/.codex config files and shared skills
codex/install: dotfiles/install
	mkdir -p "$(HOME)/.codex"
	ln -sfvn "$(ROOTDIR)/agent/skills" "$(HOME)/.codex/skills"

## symlink ~/.prime/agent config files and shared skills/rules
primeagent/install: dotfiles/install
	mkdir -p "$(HOME)/.prime/agent/sessions"
	ln -sfvn "$(ROOTDIR)/agent/agents"                 "$(HOME)/.prime/agent/agents"
	ln -sfvn "$(ROOTDIR)/agent/skills"                 "$(HOME)/.prime/agent/skills"
	ln -sfvn "$(ROOTDIR)/agent/rules"                  "$(HOME)/.prime/agent/rules"
	ln -sfvn "$(ROOTDIR)/agent/harnesses/pi/prompts"   "$(HOME)/.prime/agent/prompts"
	ln -sfvn "$(ROOTDIR)/agent/harnesses/pi/themes"    "$(HOME)/.prime/agent/themes"
	ln -sfvn "$(ROOTDIR)/agent/SWARM.md"               "$(HOME)/.prime/agent/SWARM.md"
	ln -sfvn "$(ROOTDIR)/agent/SWARM_REFERENCES.md"    "$(HOME)/.prime/agent/SWARM_REFERENCES.md"
	ln -sfvn "$(ROOTDIR)/agent/RTK.md"                 "$(HOME)/.prime/agent/RTK.md"
	ln -sfvn "$(ROOTDIR)/agent/harnesses/pi/SYSTEM.md" "$(HOME)/.prime/agent/SYSTEM.md"
	@if [ -L "$(HOME)/.prime/agent/extensions" ]; then rm -f "$(HOME)/.prime/agent/extensions"; fi
	@mkdir -p "$(HOME)/.prime/agent/extensions/lib"
	@find "$(ROOTDIR)/agent/harnesses/pi/extensions" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.prime/agent/extensions/" \;
	@find "$(ROOTDIR)/agent/hooks/pi" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.prime/agent/extensions/" \;
	@find "$(ROOTDIR)/agent/harnesses/pi/extensions/lib" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.prime/agent/extensions/lib/" \;
	@find "$(ROOTDIR)/agent/hooks/pi/lib" -maxdepth 1 -type f \
		-exec ln -sfvn {} "$(HOME)/.prime/agent/extensions/lib/" \;

## remove all dotfile symlinks/copies from $HOME and clean generated config files
dotfiles/clean: dotfiles/perm
	$(eval TMP_DIR := $(shell mktemp -d))
	trap 'rm -rf "$(TMP_DIR)"' EXIT; \
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
		  -name 'zshrc' -o -name 'zshenv' -o \
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
	    && rm -f /tmp/pinentry-tmux \
	    && echo "pinentry-tmux: installed /usr/local/bin/pinentry-tmux"; \
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
	    && rm -f /tmp/pinentry-tmux \
	    && echo "pinentry-tmux: updated to latest at /usr/local/bin/pinentry-tmux"; \
	else \
	    echo "pinentry-tmux: Go not found — cannot update"; \
	    exit 1; \
	fi

## initialize .claude/graph/{graphify,codegraph} output dirs and, if a real
## .codegraph/ exists from before this migration, move its data behind a
## symlink (CODEGRAPH_DIR only accepts a single path segment, so a multi-level
## output path needs this symlink indirection). Idempotent — safe to re-run.
graph/init:
	mkdir -p $(ROOTDIR)/.claude/graph/graphify
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
	sudo cp $(ROOTDIR)/network/nm/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo cp $(ROOTDIR)/network/nm/nmcli-bond-auto-connect.sh   /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
	sudo cp $(ROOTDIR)/network/nm/99-coalesce-x710              /etc/NetworkManager/dispatcher.d/99-coalesce-x710
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

## deploy UDM Pro on_boot.d performance script via SSH and apply immediately
## Requires: ssh udmpro to work (Host alias in ~/.ssh/config)
network/unifi/install:
	ssh udmpro "mkdir -p /data/on_boot.d"
	cat $(ROOTDIR)/network/unifi/on_boot.d/10-sysctl.sh | ssh udmpro "cat > /data/on_boot.d/10-sysctl.sh && chmod +x /data/on_boot.d/10-sysctl.sh"
	ssh udmpro "/data/on_boot.d/10-sysctl.sh"
	@echo "network/unifi/install: deployed and applied 10-sysctl.sh on UDM Pro"

## install Arch Linux packages and apply dotfiles (runs dotfiles/install)
arch/install: dotfiles/install claude/install pi/install agy/install codex/install primeagent/install
	$(ARCH_PREP)
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$$dest,sudo); \
	done
	$(ARCH_POST)

## arch/install variant for ThinkPad P1 (adds P1 waybar CSS + NVIDIA drivers)
arch/p1/install: arch/install
	rm -rf $(HOME)/.config/waybar/style.css
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/waybar_p1.css,$(HOME)/.config/waybar/style.css,)
	$(NVIDIA_INSTALL)
	$(ARCH_P1_POST)

## arch/install variant for the desktop workstation (NVIDIA + network udev rules)
arch/desk/install: arch/install
	$(NVIDIA_INSTALL)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/network/nm/desk/70-persistent-network.rules,/etc/udev/rules.d/70-persistent-network.rules,sudo)
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$$dest,sudo); \
	done
	@echo "$$ARCH_DESK_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
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
mac/install: dotfiles/install claude/install pi/install agy/install codex/install primeagent/install
	$(MAC_PREP)
	# No docker/daemon.json deployment here any more — apple/container (see
	# nix/modules/darwin/containerization.nix) replaces colima/Docker entirely on macOS
	# and doesn't read Docker's config.json/daemon.json. MAC_PREP above still removes any
	# leftover files from a pre-migration install.
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		rm -f "$(HOME)/Library/LaunchAgents/$$agent"; \
		cp -f "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua
	@$(MAKE) pinentry/install ROOTDIR='$(ROOTDIR)'
	@$(MAKE) nix/setup ROOTDIR='$(ROOTDIR)' NIX_HOST_NAME=$(MAC_NIX_HOST_NAME)

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
