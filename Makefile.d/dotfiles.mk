.PHONY: echo all run copy link clean perm

define DOTFILES_MAP
atuin/config.toml .config/atuin/config.toml
atuin/themes/zed_kpango.toml .config/atuin/themes/zed_kpango.toml
dockers/config.json .docker/config.json
dockers/daemon.json .docker/daemon.json
editorconfig .editorconfig
gemini/settings.json .gemini/settings.json
gemini/policies/policy.toml .gemini/policies/rules.toml
ghostty.conf .config/ghostty/config
gitattributes .gitattributes
gitconfig .gitconfig
.gitignore .gitignore
gpg-agent.conf .gnupg/gpg-agent.conf
helix/config.toml .config/helix/config.toml
helix/languages.toml .config/helix/languages.toml
helix/themes/zed_kpango.toml .config/helix/themes/zed_kpango.toml
sheldon.toml .config/sheldon/plugins.toml
starship.toml .config/starship.toml
tmux.conf .tmux.conf
tmux-kube .tmux-kube
tmux.new-session .tmux.new-session
zshrc .zshrc
zfunc .zfunc
zshenv .zshenv
endef
export DOTFILES_MAP

echo:
	@echo $(ROOTDIR)

all: prod_build login push profile git_push

run:
	source $(ROOTDIR)/zsh/20-docker.zsh && devrun

copy:
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		mkdir -p "$$(dirname "$(HOME)/$$dest")"; \
		cp "$(ROOTDIR)/$$src" "$(HOME)/$$dest"; \
	done
	sudo mkdir -p /etc/docker
	sudo cp $(ROOTDIR)/dockers/config.json /etc/docker/config.json
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json

link:
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		mkdir -p "$$(dirname "$(HOME)/$$dest")"; \
		ln -sfv "$(ROOTDIR)/$$src" "$(HOME)/$$dest"; \
	done
	sudo mkdir -p /etc/docker
	sudo ln -sfv $(ROOTDIR)/dockers/config.json /etc/docker/config.json
	sudo ln -sfv $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json

CLEAN_FILES = \
	$(HOME)/.config/fcitx5/conf/classicui.conf \
	$(HOME)/.config/fcitx5/config \
	$(HOME)/.config/fcitx5/profile \
	$(HOME)/.config/ghostty \
	$(HOME)/.config/helix \
	$(HOME)/.config/nvim \
	$(HOME)/.config/ranger \
	$(HOME)/.config/sheldon \
	$(HOME)/.config/sway \
	$(HOME)/.config/waybar \
	$(HOME)/.config/xdg-desktop-portal \
	$(HOME)/.config/wofi \
	$(HOME)/.config/workstyle \
	$(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist \
	$(HOME)/Library/LaunchAgents/ulimit.plist \
	$(HOME)/.Xmodmap \
	/etc/chrony.conf \
	/etc/default/tlp \
	/etc/docker/config.json \
	/etc/docker/daemon.json \
	/etc/environment \
	/etc/makepkg.conf \
	/etc/modprobe.d/blacklist-nouveau.conf \
	/etc/modprobe.d/nowatchdog.conf \
	/etc/modprobe.d/nvidia-tweaks.conf \
	/etc/modprobe.d/thinkfan.conf \
	/etc/modules-load.d/bbr.conf \
	/etc/modules-load.d/nf_conntrack.conf \
	/etc/modules-load.d/nvidia-uvm.conf \
	/etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh \
	/etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh \
	/etc/NetworkManager/dnsmasq.d/dnsmasq.conf \
	/etc/NetworkManager/NetworkManager.conf \
	/etc/pacman.conf \
	/etc/profile.d/fcitx.sh \
	/etc/profile.d/sway.sh \
	/etc/pulse/default.pa \
	/etc/resolv.dnsmasq.conf \
	/etc/resolv.pre-tailscale-backup.conf \
	/etc/sudoers.d/$(SYS_USER) \
	/etc/mkinitcpio.conf \
	/etc/mkinitcpio.d/linux.preset \
	/etc/mkinitcpio.d/linux-zen.preset \
	/etc/sysctl.d/99-sysctl.conf \
	/etc/systemd/system/nvidia-disable-resume.service \
	/etc/tmpfiles.d/thp.conf \
	/etc/systemd/system/nvidia-enable-power-off.service \
	/etc/systemd/system/nvidia-unload.service \
	/etc/systemd/system/pulseaudio.service \
	/etc/tlp.conf \
	/etc/udev/rules.d/60-ioschedulers.rules \
	/etc/udev/rules.d/60-nvidia.rules \
	/usr/share/applications/com.mitchellh.ghostty.desktop

clean: perm
	$(eval TMP_DIR := $(shell mktemp -d))
	jq . $(ROOTDIR)/arch/waybar.json > $(TMP_DIR)/waybar.json.tmp && mv $(TMP_DIR)/waybar.json.tmp $(ROOTDIR)/arch/waybar.json
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo rm -rf "$(HOME)/$$dest"; \
	done
	sudo rm -rf $(CLEAN_FILES)

perm:
	sudo chmod -R 755 $(ROOTDIR)/*
	sudo chmod -R 755 $(ROOTDIR)/.*
	sudo chown -R $(SYS_USER):$(GROUP_ID) $(ROOTDIR)/*
	sudo chown -R $(SYS_USER):$(GROUP_ID) $(ROOTDIR)/.*
	\find $(ROOTDIR) -type d -name '.git' -prune -o -type f \( -name '*.conf' -o -name '*.service' -o -name '*.rules' -o -name '*.toml' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) -exec sudo chmod 644 {} \;
	sudo chmod -R 644 $(ROOTDIR)/gpg-agent.conf
	sudo chmod -R 644 $(ROOTDIR)/arch/waybar.json
	\find $(ROOTDIR) \
		-type d \( -name '.git' -o -name '.worktrees' \) -prune \
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
