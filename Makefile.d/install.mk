.PHONY: dotfiles/install dotfiles/compile dotfiles/clean dotfiles/perm precompile/zsh \
        arch/install arch/p1/install arch/desk/install arch/desk/audit \
        mac/install \
        claude/install claude/docker/install \
        tailscale/install \
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
chrome-beta-flags.conf .config/chrome-beta-flags.conf
claude/CLAUDE.md .claude/CLAUDE.md
claude/settings.json .claude/settings.json
claude/settings.local.json .claude/settings.local.json
desktop/discord.desktop .local/share/applications/discord.desktop
desktop/slack.desktop .local/share/applications/slack.desktop
dockers/config.json .docker/config.json
dockers/daemon.json .docker/daemon.json
editorconfig .editorconfig
gemini/policies/policy.toml .gemini/policies/rules.toml
gemini/settings.json .gemini/settings.json
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
helix/themes/zed_kpango.toml .config/helix/themes/zed_kpango.toml
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
ranger .config/ranger
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
network/dns/dnsmasq.conf /etc/NetworkManager/dnsmasq.d/dnsmasq.conf
network/nm/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
network/dns/resolv.dnsmasq.conf /etc/resolv.dnsmasq.conf
network/dns/resolv.dnsmasq.conf /etc/resolv.pre-tailscale-backup.conf
network/sysctl/sysctl.conf /etc/sysctl.d/99-sysctl.conf
arch/ghostty.desktop /usr/share/applications/com.mitchellh.ghostty.desktop
arch/hooks/rebuild-aur-helpers.hook /etc/pacman.d/hooks/rebuild-aur-helpers.hook
arch/hooks.d/rebuild-aur-helpers.sh /usr/local/bin/rebuild-aur-helpers.sh
arch/mkinitcpio.conf /etc/mkinitcpio.conf
arch/mkinitcpio/linux.preset /etc/mkinitcpio.d/linux.preset
arch/mkinitcpio/linux-zen.preset /etc/mkinitcpio.d/linux-zen.preset
arch/systemd/NetworkManager.service.d/capabilities.conf /etc/systemd/system/NetworkManager.service.d/capabilities.conf
arch/sshd_config.d/10-tailscale.conf /etc/ssh/sshd_config.d/10-tailscale.conf
endef
export ARCH_SUDO_LINK_MAP

define ARCH_SUDO_CP_MAP
arch/chrony.conf /etc/chrony.conf
arch/sudoers /etc/sudoers.d/$(SYS_USER)
arch/environment /etc/environment
network/nm/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
network/nm/nmcli-bond-auto-connect.sh /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
network/nm/99-coalesce-x710 /etc/NetworkManager/dispatcher.d/99-coalesce-x710
endef
export ARCH_SUDO_CP_MAP

define ARCH_DESK_SUDO_LINK_MAP
arch/modprobe.d/blacklist-nouveau.conf /etc/modprobe.d/blacklist-nouveau.conf
arch/modprobe.d/nowatchdog.conf /etc/modprobe.d/nowatchdog.conf
arch/modprobe.d/thinkfan-desk.conf /etc/modprobe.d/thinkfan.conf
arch/systemd/nvidia-unload.service /etc/systemd/system/nvidia-unload.service
arch/tmpfiles.d/thp.conf /etc/tmpfiles.d/thp.conf
endef
export ARCH_DESK_SUDO_LINK_MAP

define ARCH_DESK_SUDO_CP_MAP
arch/desk/fstab /etc/fstab
arch/loader/entries/arch.conf /boot/loader/entries/arch.conf
arch/loader/loader.conf /boot/loader/loader.conf
endef
export ARCH_DESK_SUDO_CP_MAP

define ARCH_PREP
	sudo mkdir -p /etc/systemd/system/NetworkManager.service.d
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
	sudo chmod -R 0440 /etc/sudoers.d
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
endef

define ARCH_P1_POST
	rm -rf $(HOME)/.config/psd
	mkdir $(HOME)/.config/psd
	sudo systemctl daemon-reload
endef

define ARCH_DESK_POST
	sudo mkdir -p /etc/cdi
	sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
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
	@sudo find /boot/loader/entries/ -name '*.conf' -not -name 'arch.conf' -delete && \
		echo "boot: stale entries removed" || true
endef

# ── macOS ──────────────────────────────────────────────────────────────────────

MACOS_LAUNCH_AGENTS = localhost.homebrew-autoupdate.plist ulimit.plist

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
	cp $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	cp $(ROOTDIR)/gpg-agent.conf $(HOME)/.gnupg/gpg-agent.conf
	sed -i.bak '/^#.*set-environment -g PATH/s/^#//' $(HOME)/.tmux.conf
	sed -i.bak 's|/usr/local/bin/pinentry-tmux|/opt/homebrew/bin/pinentry-mac|g' $(HOME)/.gnupg/gpg-agent.conf
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
	@$(call DEPLOY_FUNC,$(ROOTDIR)/dockers/config.json,/etc/docker/config.json,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/dockers/daemon.json,/etc/docker/daemon.json,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/containerd.toml,/etc/containerd/config.toml,sudo)
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
		"$(HOME)/.claude/plugins" \
		"$(HOME)/.claude/memory" \
		"$(HOME)/.claude/projects" \
		"$(HOME)/.claude/session-data"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/claude/settings.json" "$(HOME)/.claude/settings.json"
	install -m 600 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/claude/settings.local.json" "$(HOME)/.claude/settings.local.json"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/claude/CLAUDE.md" "$(HOME)/.claude/CLAUDE.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/claude/RTK.md" "$(HOME)/.claude/RTK.md"
	install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
		"$(ROOTDIR)/claude/SWARM.md" "$(HOME)/.claude/SWARM.md"
	HOME="$(HOME)" envsubst < "$(ROOTDIR)/claude/installed_plugins.json" \
		> "$(HOME)/.claude/plugins/installed_plugins.json"
	chown "$(USER_ID):$(GROUP_ID)" "$(HOME)/.claude/plugins/installed_plugins.json"
	find "$(ROOTDIR)/claude/hooks" -maxdepth 1 -name "*.sh" \
		-exec install -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.claude/hooks/" \;
	find "$(ROOTDIR)/claude/agents" -maxdepth 1 -name "*.md" \
		-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" {} "$(HOME)/.claude/agents/" \;
	@for skill_dir in "$(ROOTDIR)/claude/skills"/*/; do \
		skill_name=$$(basename "$$skill_dir"); \
		install -d -m 755 -o "$(USER_ID)" -g "$(GROUP_ID)" \
			"$(HOME)/.claude/skills/$${skill_name}"; \
		find "$${skill_dir}" -name "*.md" \
			-exec install -m 644 -o "$(USER_ID)" -g "$(GROUP_ID)" \
				{} "$(HOME)/.claude/skills/$${skill_name}/" \; ; \
	done

## symlink ~/.claude/settings.json + settings.local.json + CLAUDE.md and share session with root
## Credentials (~/.claude/.credentials.json) are NOT managed here — SSO login handles them
claude/install: dotfiles/install
	@echo "Sharing Claude session: /root/.claude -> $(HOME)/.claude"
	sudo rm -rf /root/.claude
	sudo ln -sfvn "$(HOME)/.claude" /root/.claude
	sudo ln -sfvn "$(ROOTDIR)/gitconfig"                        /root/.gitconfig
	sudo mkdir -p /root/.gemini/policies
	sudo ln -sfvn "$(ROOTDIR)/gemini/settings.json"             /root/.gemini/settings.json
	sudo ln -sfvn "$(ROOTDIR)/gemini/policies/policy.toml"      /root/.gemini/policies/rules.toml
	mkdir -p "$(HOME)/.claude/plugins" "$(HOME)/.claude/memory" "$(HOME)/.claude/session-data"
	envsubst < "$(ROOTDIR)/claude/installed_plugins.json" > "$(HOME)/.claude/plugins/installed_plugins.json"
	ln -sfvn "$(ROOTDIR)/claude/agents" "$(HOME)/.claude/agents"
	ln -sfvn "$(ROOTDIR)/claude/hooks"  "$(HOME)/.claude/hooks"
	ln -sfvn "$(ROOTDIR)/claude/skills" "$(HOME)/.claude/skills"
	ln -sfvn "$(ROOTDIR)/claude/RTK.md" "$(HOME)/.claude/RTK.md"
	@pass_claude="$(HOME)/go/src/github.com/kpango/pass/claude"; \
	mkdir -p "$${pass_claude}/projects"; \
	test -f "$${pass_claude}/history.jsonl" || touch "$${pass_claude}/history.jsonl"; \
	ln -sfvn "$${pass_claude}/projects"      "$(HOME)/.claude/projects"; \
	ln -sfvn "$${pass_claude}/history.jsonl" "$(HOME)/.claude/history.jsonl"; \
	echo "linked: ~/.claude/projects -> $${pass_claude}/projects"; \
	echo "linked: ~/.claude/history.jsonl -> $${pass_claude}/history.jsonl"

## remove all dotfile symlinks/copies from $HOME and clean generated config files
dotfiles/clean: dotfiles/perm
	$(eval TMP_DIR := $(shell mktemp -d))
	jq . $(ROOTDIR)/arch/waybar.json > $(TMP_DIR)/waybar.json.tmp && mv $(TMP_DIR)/waybar.json.tmp $(ROOTDIR)/arch/waybar.json
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$(HOME)/$$dest,sudo); \
	done
	@$(call CLEAN_FUNC,/etc/docker/config.json,sudo)
	@$(call CLEAN_FUNC,/etc/docker/daemon.json,sudo)
	@$(call CLEAN_FUNC,/etc/containerd/config.toml,sudo)

## fix file/dir permissions and normalise line endings across the repo
dotfiles/perm:
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type d -exec sudo chmod 755 {} \;
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type f -exec sudo chmod 644 {} \;
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type f -name '*.sh' -exec sudo chmod 755 {} \;
	find $(ROOTDIR) -not \( -path '*/\.git/*' -o -path '*/\.worktrees/*' -o -path '*/\.claude/*' \) -type f -name '*.py' -exec sudo chmod 755 {} \;
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
		\) -not -name 'tmux.conf' -exec nkf -Lu -w --overwrite {} \;
	sudo chmod 755 $(ROOTDIR)/tmux.conf.d/disk-info 2>/dev/null || true

## build and install the Go pinentry-tmux binary to /usr/local/bin
## Detects Go across Arch, macOS Homebrew, and PATH.
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

## deploy Tailscale sshd config, apply node preferences, and enable sshd as fallback
tailscale/install:
	sudo mkdir -p /etc/ssh/sshd_config.d
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/sshd_config.d/10-tailscale.conf,/etc/ssh/sshd_config.d/10-tailscale.conf,sudo)
	sudo systemctl enable --now sshd.service
	bash $(ROOTDIR)/tailscale/setup.sh

## install Arch Linux packages and apply dotfiles (runs dotfiles/install)
arch/install: dotfiles/install
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

## install macOS Homebrew packages and apply dotfiles (runs dotfiles/install)
mac/install: dotfiles/install
	$(MAC_PREP)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/macos/docker_config.json,$(HOME)/.docker/config.json,)
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	@$(call DEPLOY_FUNC,$(ROOTDIR)/macos/docker_config.json,/etc/docker/config.json,sudo)
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		sudo ln -sfvn "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chown root:wheel "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua

mac/clean:
	@$(call CLEAN_FUNC,$(HOME)/.docker/config.json,sudo)
	@$(call CLEAN_FUNC,/etc/docker/config.json,sudo)

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
