.PHONY: all link zsh bash build prod_build profile run push pull

ROOTDIR = $(eval ROOTDIR := $(shell git rev-parse --show-toplevel))$(ROOTDIR)
USER = $(eval USER := $(shell whoami))$(USER)
USER_ID = $(eval USER_ID := $(shell id -u $(USER)))$(USER_ID)
GROUP_ID = $(eval GROUP_ID := $(shell id -g $(USER)))$(GROUP_ID)
GROUP_IDS = $(eval GROUP_IDS := $(shell id -G $(USER)))$(GROUP_IDS)
GITHUB_ACCESS_TOKEN = $(eval GITHUB_ACCESS_TOKEN := $(shell pass github.api.ro.token))$(GITHUB_ACCESS_TOKEN)
GITHUB_SHA = $(eval GITHUB_SHA := $(shell git rev-parse HEAD))$(GITHUB_SHA)
GITHUB_URL = https://github.com/kpango/dotfiles
EMAIL = kpango@vdaas.org

DOCKER_EXTRA_OPTS ?=
DOCKER_BUILDER_NAME = "kpango-builder"
DOCKER_BUILDER_DRIVER = "docker-container"
DOCKER_BUILDER_PLATFORM = "linux/amd64,linux/arm64/v8"
DOCKER_CACHE_REPO := $(USER)/$(NAME):buildcache
DOCKER_BUILD_CACHE_DIR:= $(HOME)/.docker/buildcache
DOCKER_MEMORY_LIMIT = 32G

VERSION = latest

echo:
	@echo $(ROOTDIR)

all: prod_build login push profile git_push

run:
	source $(ROOTDIR)/alias && devrun

copy:
	mkdir -p $(HOME)/.config/alacritty
	mkdir -p $(HOME)/.config/helix/themes
	mkdir -p $(HOME)/.config/sheldon
	mkdir -p $(HOME)/.config/TabNine
	mkdir -p $(HOME)/.docker
	mkdir -p $(HOME)/.gnupg
	sudo mkdir -p /etc/docker
	cp $(ROOTDIR)/alias $(HOME)/.aliases
	cp $(ROOTDIR)/arch/alacritty.toml $(HOME)/.config/alacritty/alacritty.toml
	cp $(ROOTDIR)/dockers/config.json $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	cp $(ROOTDIR)/editorconfig $(HOME)/.editorconfig
	cp $(ROOTDIR)/ghostty.conf $(HOME)/.config/ghostty/config
	cp $(ROOTDIR)/gitattributes $(HOME)/.gitattributes
	cp $(ROOTDIR)/gitconfig $(HOME)/.gitconfig
	cp $(ROOTDIR)/gitignore $(HOME)/.gitignore
	cp $(ROOTDIR)/gpg-agent.conf $(HOME)/.gnupg/gpg-agent.conf
	cp $(ROOTDIR)/helix/config.toml $(HOME)/.config/helix/config.toml
	cp $(ROOTDIR)/helix/languages.toml $(HOME)/.config/helix/languages.toml
	cp $(ROOTDIR)/helix/themes/zed_kpango.toml $(HOME)/.config/helix/themes/zed_kpango.toml
	cp $(ROOTDIR)/sheldon.toml $(HOME)/.config/sheldon/plugins.toml
	cp $(ROOTDIR)/starship.toml $(HOME)/.config/starship.toml
	cp $(ROOTDIR)/tmux-kube $(HOME)/.tmux-kube
	cp $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	cp $(ROOTDIR)/tmux.new-session $(HOME)/.tmux.new-session
	cp $(ROOTDIR)/zshrc $(HOME)/.zshrc
	sudo cp $(ROOTDIR)/dockers/config.json /etc/docker/config.json
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json

link:
	mkdir -p $(HOME)/.config/alacritty
	mkdir -p $(HOME)/.config/helix/themes
	mkdir -p $(HOME)/.config/sheldon
	mkdir -p $(HOME)/.config/TabNine
	mkdir -p $(HOME)/.docker
	mkdir -p $(HOME)/.gnupg
	ln -sfv $(ROOTDIR)/alias $(HOME)/.aliases
	ln -sfv $(ROOTDIR)/arch/alacritty.toml $(HOME)/.config/alacritty/alacritty.toml
	ln -sfv $(ROOTDIR)/dockers/config.json $(HOME)/.docker/config.json
	ln -sfv $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	ln -sfv $(ROOTDIR)/editorconfig $(HOME)/.editorconfig
	ln -sfv $(ROOTDIR)/ghostty.conf $(HOME)/.config/ghostty/config
	ln -sfv $(ROOTDIR)/gitattributes $(HOME)/.gitattributes
	ln -sfv $(ROOTDIR)/gitconfig $(HOME)/.gitconfig
	ln -sfv $(ROOTDIR)/gitignore $(HOME)/.gitignore
	ln -sfv $(ROOTDIR)/gpg-agent.conf $(HOME)/.gnupg/gpg-agent.conf
	ln -sfv $(ROOTDIR)/helix/config.toml $(HOME)/.config/helix/config.toml
	ln -sfv $(ROOTDIR)/helix/languages.toml $(HOME)/.config/helix/languages.toml
	ln -sfv $(ROOTDIR)/helix/themes/zed_kpango.toml $(HOME)/.config/helix/themes/zed_kpango.toml
	ln -sfv $(ROOTDIR)/sheldon.toml $(HOME)/.config/sheldon/plugins.toml
	ln -sfv $(ROOTDIR)/starship.toml $(HOME)/.config/starship.toml
	ln -sfv $(ROOTDIR)/tmux-kube $(HOME)/.tmux-kube
	ln -sfv $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	ln -sfv $(ROOTDIR)/tmux.new-session $(HOME)/.tmux.new-session
	ln -sfv $(ROOTDIR)/zshrc $(HOME)/.zshrc
	sudo mkdir -p /etc/docker
	sudo ln -sfv $(ROOTDIR)/dockers/config.json /etc/docker/config.json
	sudo ln -sfv $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json

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
	# ln -sfv $(ROOTDIR)/arch/swaylock.sh $(HOME)/.config/sway/swaylock.sh
	ln -sfv $(ROOTDIR)/arch/fcitx.classicui.conf $(HOME)/.config/fcitx5/conf/classicui.conf
	ln -sfv $(ROOTDIR)/arch/fcitx.conf $(HOME)/.config/fcitx5/config
	ln -sfv $(ROOTDIR)/arch/fcitx.profile $(HOME)/.config/fcitx5/profile
	ln -sfv $(ROOTDIR)/arch/kanshi.conf $(HOME)/.config/kanshi/config
	ln -sfv $(ROOTDIR)/arch/psd.conf $(HOME)/.config/psd/psd.conf
	ln -sfv $(ROOTDIR)/arch/ranger $(HOME)/.config/ranger
	ln -sfv $(ROOTDIR)/arch/sway.conf $(HOME)/.config/sway/config
	ln -sfv $(ROOTDIR)/arch/waybar.css $(HOME)/.config/waybar/style.css
	ln -sfv $(ROOTDIR)/arch/waybar.json $(HOME)/.config/waybar/config
	ln -sfv $(ROOTDIR)/arch/wofi/style.css $(HOME)/.config/wofi/style.css
	ln -sfv $(ROOTDIR)/arch/wofi/wofi.conf $(HOME)/.config/wofi/config
	ln -sfv $(ROOTDIR)/arch/workstyle.toml $(HOME)/.config/workstyle/config.toml
	ln -sfv $(ROOTDIR)/arch/xinitrc $(HOME)/.xinitrc
	ln -sfv $(ROOTDIR)/arch/Xmodmap $(HOME)/.Xmodmap
	sudo cp $(ROOTDIR)/arch/chrony.conf /etc/chrony.conf
	sudo cp $(ROOTDIR)/arch/suduers /etc/sudoers.d/$(USER)
	sudo cp $(ROOTDIR)/arch/xinitrc /etc/environment
	sudo cp $(ROOTDIR)/network/NetworkManager-dispatcher.service /etc/systemd/system/NetworkManager-dispatcher.service
	sudo cp $(ROOTDIR)/network/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo cp $(ROOTDIR)/network/nmcli-bond-auto-connect.sh /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
	sudo ln -sfv $(ROOTDIR)/arch/60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules
	sudo ln -sfv $(ROOTDIR)/arch/default.pa /etc/pulse/default.pa
	sudo ln -sfv $(ROOTDIR)/arch/limits.conf /etc/security/limits.conf
	sudo ln -sfv $(ROOTDIR)/arch/makepkg.conf /etc/makepkg.conf
	sudo ln -sfv $(ROOTDIR)/arch/modules-load.d/bbr.conf /etc/modules-load.d/bbr.conf
	sudo ln -sfv $(ROOTDIR)/arch/pacman.conf /etc/pacman.conf
	sudo ln -sfv $(ROOTDIR)/arch/sway.sh /etc/profile.d/sway.sh
	sudo ln -sfv $(ROOTDIR)/arch/thinkfan.conf /etc/thinkfan.conf
	sudo ln -sfv $(ROOTDIR)/arch/tlp /etc/default/tlp
	sudo ln -sfv $(ROOTDIR)/arch/tlp /etc/tlp.conf
	sudo ln -sfv $(ROOTDIR)/arch/xinitrc /etc/profile.d/fcitx.sh
	sudo ln -sfv $(ROOTDIR)/dockers/config.json /root/.docker/config.json
	sudo ln -sfv $(ROOTDIR)/dockers/daemon.json /root/.docker/daemon.json
	sudo ln -sfv $(ROOTDIR)/network/dnsmasq.conf /etc/NetworkManager/dnsmasq.d/dnsmasq.conf
	sudo ln -sfv $(ROOTDIR)/network/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
	sudo ln -sfv $(ROOTDIR)/network/resolv.dnsmasq.conf /etc/resolv.dnsmasq.conf
	sudo ln -sfv $(ROOTDIR)/network/sysctl.conf /etc/sysctl.d/99-sysctl.conf
	sudo echo "options thinkpad_acpi fan_control=1" | sudo tee /etc/modprobe.d/thinkfan.conf
	# sudo modprobe -rv thinkpad_acpi
	# sudo modprobe -v thinkpad_acpi
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo chown root:root /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
	sudo chown root:root /etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh
	sudo chown -R 0:0 /etc/sudoers.d
	sudo chmod -R 0440 /etc/sudoers.d
	sudo chown -R 0:0 /etc/sudoers.d/$(USER)
	sudo chmod -R 0440 /etc/sudoers.d/$(USER)
	sudo sysctl -e -p /etc/sysctl.d/99-sysctl.conf
	sudo systemctl daemon-reload

arch_p1_link: \
	arch_link
	rm -rf $(HOME)/.config/alacritty/alacritty.toml
	ln -sfv $(ROOTDIR)/arch/alacritty_p1.toml $(HOME)/.config/alacritty/alacritty.toml
	rm -rf $(HOME)/.config/waybar/style.css
	ln -sfv $(ROOTDIR)/arch/waybar_p1.css $(HOME)/.config/waybar/style.css
	rm -rf $(HOME)/.config/psd
	mkdir $(HOME)/.config/psd
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	sudo systemctl daemon-reload
	# sudo cp $(ROOTDIR)/arch/nvidia-enable-power-off.service /etc/systemd/system/nvidia-enable-power-off.service
	# sudo cp $(ROOTDIR)/arch/nvidia-disable-resume.service /etc/systemd/system/nvidia-disable-resume.service

arch_desk_link: \
	arch_link
	rm -rf $(HOME)/.config/alacritty/alacritty.toml
	ln -sfv $(ROOTDIR)/arch/alacritty_desk.toml $(HOME)/.config/alacritty/alacritty.toml
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia.conf /etc/modprobe.d/nvidia-tweaks.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/nvidia-uvm.conf /etc/modules-load.d/nvidia-uvm.conf
	sudo ln -sfv $(ROOTDIR)/nvidia/60-nvidia.rules /etc/udev/rules.d/60-nvidia.rules
	sudo ln -sfv $(ROOTDIR)/network/desk/70-persistent-network.rules /etc/udev/rules.d/70-persistent-network.rules
	sudo mkdir -p /etc/systemd/system/irqbalance.service.d
	sudo rm -rf /etc/systemd/system/irqbalance.service.d/override.conf
	sudo ln -sfv $(ROOTDIR)/arch/irqbalance.service /etc/systemd/system/irqbalance.service.d/override.conf
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

mac_link: \
	link
	sudo rm -rf \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
		$(HOME)/.config/alacritty/alacritty.toml \
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
	ln -sfv $(ROOTDIR)/macos/alacritty.toml $(HOME)/.config/alacritty/alacritty.toml
	ln -sfv $(ROOTDIR)/macos/docker_config.json $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	sudo ln -sfv $(ROOTDIR)/macos/docker_config.json /etc/docker/config.json
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json
	sudo ln -sfv $(ROOTDIR)/macos/localhost.homebrew-autoupdate.plist $(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist
	sudo ln -sfv $(ROOTDIR)/macos/ulimit.plist $(HOME)/Library/LaunchAgents/ulimit.plist
	sudo chmod 600 $(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist
	sudo chmod 600 $(HOME)/Library/LaunchAgents/ulimit.plist
	sudo chown root:wheel $(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist
	sudo chown root:wheel $(HOME)/Library/LaunchAgents/ulimit.plist
	sudo plutil -lint $(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist
	sudo plutil -lint $(HOME)/Library/LaunchAgents/ulimit.plist
	sudo launchctl load -w $(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist
	sudo launchctl load -w $(HOME)/Library/LaunchAgents/ulimit.plist
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua

clean: perm
	$(eval TMP_DIR := $(shell mktemp -d))
	jq . $(ROOTDIR)/arch/waybar.json > $(TMP_DIR)/waybar.json.tmp && mv $(TMP_DIR)/waybar.json.tmp $(ROOTDIR)/arch/waybar.json
	sudo rm -rf \
		/etc/chrony.conf \
		/etc/dbus-1/system.d/pulseaudio-bluetooth.conf \
		/etc/default/tlp \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
		/etc/environment \
		/etc/lightdm \
		/etc/makepkg.conf \
		/etc/modprobe.d/bbswitch.conf \
		/etc/modprobe.d/nvidia-tweaks.conf \
		/etc/modprobe.d/thinkfan.conf \
		/etc/modules-load.d/bbr.conf \
		/etc/modules-load.d/nvidia-uvm.conf \
		/etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh \
		/etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh \
		/etc/NetworkManager/dnsmasq.d/dnsmasq.conf \
		/etc/NetworkManager/NetworkManager.conf \
		/etc/pacman.conf \
		/etc/profile.d/fcitx.sh \
		/etc/profile.d/sway.sh \
		/etc/pulse/default.pa \
		/etc/sudoers.d/$(USER) \
		/etc/sysctl.conf \
		/etc/sysctl.d/99-sysctl.conf \
		/etc/systemd/system/NetworkManager-dispatcher.service \
		/etc/systemd/system/nvidia-disable-resume.service \
		/etc/systemd/system/nvidia-enable-power-off.service \
		/etc/systemd/system/pulseaudio.service \
		/etc/tlp.conf \
		/etc/udev/rules.d/60-ioschedulers.rules \
		/etc/udev/rules.d/60-nvidia.rules \
		$(HOME)/.aliases \
		$(HOME)/.config/alacritty \
		$(HOME)/.config/compton \
		$(HOME)/.config/fcitx5/conf/classicui.conf \
		$(HOME)/.config/fcitx5/config \
		$(HOME)/.config/fcitx5/profile \
		$(HOME)/.config/ghostty \
		$(HOME)/.config/helix \
		$(HOME)/.config/i3 \
		$(HOME)/.config/i3status \
		$(HOME)/.config/nvim \
		$(HOME)/.config/ranger \
		$(HOME)/.config/sheldon \
		$(HOME)/.config/starship.toml \
		$(HOME)/.config/sway \
		$(HOME)/.config/waybar \
		$(HOME)/.config/wofi \
		$(HOME)/.config/workstyle \
		$(HOME)/.docker/config.json \
		$(HOME)/.docker/daemon.json \
		$(HOME)/.editorconfig \
		$(HOME)/.gitattributes \
		$(HOME)/.gitconfig \
		$(HOME)/.gitignore \
		$(HOME)/.gnupg/gpg-agent.conf \
		$(HOME)/.tmux-kube \
		$(HOME)/.tmux.conf \
		$(HOME)/.tmux.new-session \
		$(HOME)/.Xdefaults \
		$(HOME)/.xinitrc \
		$(HOME)/.Xmodmap \
		$(HOME)/.zshrc \
		$(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist \
		$(HOME)/Library/LaunchAgents/ulimit.plist



zsh: link
	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc

bash: link
	[ -f $(HOME)/.bashrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.bashrc

build: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx \
	build_base
	@xpanes -s -c "make DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) -f $(ROOTDIR)/Makefile build_{}" go docker rust dart k8s nim gcloud env

prod: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx
	@make DOCKER_EXTRA_OPTS="--no-cache" prod_build

github_check:
	curl --request GET \
		-H "Authorization: Bearer $(GITHUB_ACCESS_TOKEN)" \
		--url https://api.github.com/octocat
	curl --request GET \
		-H "Authorization: Bearer $(GITHUB_ACCESS_TOKEN)" \
		--url https://api.github.com/rate_limit

docker_build:
	@make DOCKER_BUILDER_NAME=$(DOCKER_BUILDER_NAME) create_buildx
	$(eval TMP_DIR := $(shell mktemp -d))
	@echo $(GITHUB_ACCESS_TOKEN) > $(TMP_DIR)/gat
	@chmod 600 $(TMP_DIR)/gat
	DOCKER_BUILDKIT=1 docker buildx build \
		$(DOCKER_EXTRA_OPTS) \
		--builder "$(DOCKER_BUILDER_NAME)" \
		--platform "$(DOCKER_BUILDER_PLATFORM)" \
		--allow "network.host" \
		--attest type=sbom,generator=docker/buildkit-syft-scanner:edge \
		--build-arg BUILDKIT_INLINE_CACHE=1 \
		--build-arg BUILDKIT_MULTI_PLATFORM=1 \
		--build-arg EMAIL="$(EMAIL)" \
		--build-arg GROUP_ID="$(GROUP_ID)" \
		--build-arg GROUP_IDS="$(GROUP_IDS)" \
		--build-arg HOME="$(HOME)" \
		--build-arg USER="$(USER)" \
		--build-arg USER_ID="$(USER_ID)" \
		--build-arg WHOAMI="$(USER)" \
		--cache-from type=local,src=$(DOCKER_BUILD_CACHE_DIR) \
		--cache-from type=registry,ref=$(DOCKER_CACHE_REPO) \
		--cache-to type=local,dest=$(DOCKER_BUILD_CACHE_DIR),mode=max \
		--cache-to type=registry,ref=$(DOCKER_CACHE_REPO),mode=max,inline=true \
		--label org.opencontainers.image.revision="$(GITHUB_SHA)" \
		--label org.opencontainers.image.source="$(GITHUB_URL)" \
		--label org.opencontainers.image.title="$(USER)/$(NAME)" \
		--label org.opencontainers.image.url="$(GITHUB_URL)" \
		--label org.opencontainers.image.version="$(VERSION)" \
		--memory $(DOCKER_MEMORY_LIMIT) \
		--memory-swap $(DOCKER_MEMORY_LIMIT) \
		--network=host \
		--output type=registry,oci-mediatypes=true,compression=zstd,compression-level=5,force-compression=true,push=true \
		--provenance=mode=max \
		--secret id=gat,src="$(TMP_DIR)/gat" \
		-t "$(USER)/$(NAME):$(VERSION)" \
		-f $(DOCKERFILE) .
	docker buildx rm --force "$(DOCKER_BUILDER_NAME)"
	@rm -rf $(TMP_DIR)

init_buildx:
	docker run \
		--network=host \
		--privileged \
		--rm tonistiigi/binfmt:master \
		--install $(DOCKER_BUILDER_PLATFORM)

create_buildx:
	-docker buildx rm --force $(DOCKER_BUILDER_NAME)
	docker buildx create --use \
		--name $(DOCKER_BUILDER_NAME) \
		--driver $(DOCKER_BUILDER_DRIVER) \
		--driver-opt=image=moby/buildkit:master \
		--driver-opt=network=host \
		--buildkitd-flags="--oci-worker-gc=false --oci-worker-snapshotter=stargz" \
		--platform $(DOCKER_BUILDER_PLATFORM) \
		--bootstrap
	# make add_nodes
	docker buildx ls
	docker buildx inspect --bootstrap $(DOCKER_BUILDER_NAME)
	sudo chown -R $(USER):$(GROUP_ID) "$(HOME)/.docker"

add_nodes:
	@echo $(DOCKER_BUILDER_PLATFORM) | tr ',' '\n' | while read platform; do \
		node_name=$$(echo $$platform | tr '/' '_' | tr -d '[:space:]'); \
		echo "Adding node to $(DOCKER_BUILDER_NAME) for $$platform as $$node_name..."; \
		docker buildx create --append --name $(DOCKER_BUILDER_NAME) --node $${DOCKER_BUILDER_NAME}-$$node_name --platform $$platform; \
	done

remove_buildx:
	docker buildx rm --force --all-inactive
	sudo rm -rf $(HOME)/.docker/buildx
	docker buildx ls

do_build:
	@make DOCKERFILE="$(ROOTDIR)/dockers/$(NAME).Dockerfile" \
		NAME="$(NAME)" \
		DOCKER_BUILDER_NAME="$(DOCKER_BUILDER_NAME)-$(NAME)" \
		DOCKER_BUILDER_PLATFORM="$(DOCKER_BUILDER_PLATFORM)" \
		DOCKER_MEMORY_LIMIT=$(DOCKER_MEMORY_LIMIT) \
		docker_build

prod_build:
	@make NAME="dev" do_build

build_mkl:
	@make NAME="mkl" do_build

build_go:
	cd $(ROOTDIR)/dockers && go get tool && cd -
	@make NAME="go" do_build

build_rust:
	@make NAME="rust" do_build

build_nim:
	@make NAME="nim" do_build

build_dart:
	@make NAME="dart" do_build

build_docker:
	@make NAME="docker" do_build

build_base:
	@make NAME="base" do_build

build_env:
	@make NAME="env" do_build

build_gcloud:
	@make NAME="gcloud" do_build

build_k8s:
	@make NAME="kube" do_build

profile:
	rm -f analyze.txt
	type dlayer >/dev/null 2>&1 && docker save kpango/dev:latest | dlayer >> analyze.txt

login:
	rm -rf $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/config.json $(HOME)/.docker/config.json
	docker login

push:
	docker push kpango/dev:latest

pull:
	docker pull kpango/dev:latest

perm:
	sudo chmod -R 755 $(ROOTDIR)/*
	sudo chmod -R 755 $(ROOTDIR)/.*
	sudo chown -R $(USER):$(GROUP_ID) $(ROOTDIR)/*
	sudo chown -R $(USER):$(GROUP_ID) $(ROOTDIR)/.*
	sudo chmod -R 644 $(ROOTDIR)/gpg-agent.conf
	sudo chmod -R 644 $(ROOTDIR)/arch/waybar.json
	\find $(ROOTDIR) -type d -name '.git' -prune -o -type f -not -name 'tmux.conf' -exec nkf -Lu -w --overwrite {} \;


git_push:
	git add -A
	git commit -m fix
	git push
