.PHONY: all link zsh bash build prod_build profile run push pull


ROOTDIR = $(eval ROOTDIR := $(shell git rev-parse --show-toplevel))$(ROOTDIR)

all: prod_build login push profile git_push

run:
	source $(ROOTDIR)/alias && devrun

link:
	mkdir -p ${HOME}/.config/nvim/colors
	mkdir -p ${HOME}/.config/nvim/syntax
	mkdir -p ${HOME}/.config/TabNine
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))alias $(HOME)/.aliases
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))coc-settings.json $(HOME)/.config/nvim/coc-settings.json
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))editorconfig $(HOME)/.editorconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))efm-lsp-conf.yaml $(HOME)/.config/nvim/efm-lsp-conf.yaml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))efm-lsp-conf.yaml $(HOME)/.config/nvim/efm-lsp-conf.yaml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))gitattributes $(HOME)/.gitattributes
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))gitconfig $(HOME)/.gitconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))gitignore $(HOME)/.gitignore
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))go.vim $(HOME)/.config/nvim/syntax/go.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))init.vim $(HOME)/.config/nvim/init.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))monokai.vim $(HOME)/.config/nvim/colors/monokai.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))starship.toml $(HOME)/.config/starship.toml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))tabnine_config.json $(HOME)/.config/TabNine/tabnine_config.json
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))tmux-kube $(HOME)/.tmux-kube
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))tmux.conf $(HOME)/.tmux.conf
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))tmux.new-session $(HOME)/.tmux.new-session
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))zshrc $(HOME)/.zshrc

arch_link: \
	clean \
	link
	mkdir -p ${HOME}/.config/alacritty
	mkdir -p ${HOME}/.config/fcitx/conf
	mkdir -p ${HOME}/.config/sway
	mkdir -p ${HOME}/.config/waybar
	mkdir -p ${HOME}/.config/wofi
	mkdir -p ${HOME}/.config/workstyle
	mkdir -p ${HOME}/.docker
	mkdir -p /etc/docker
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/Xmodmap $(HOME)/.Xmodmap
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/alacritty.yml $(HOME)/.config/alacritty/alacritty.yml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/fcitx-classic-ui.config $(HOME)/.config/fcitx/conf/fcitx-classic-ui.config
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/gitconfig $(HOME)/.gitconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/ranger $(HOME)/.config/ranger
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/sway.conf $(HOME)/.config/sway/config
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/waybar.conf $(HOME)/.config/waybar/config
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/waybar.css $(HOME)/.config/waybar/style.css
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/wofi/style.css $(HOME)/.config/wofi/style.css
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/wofi/wofi.conf $(HOME)/.config/wofi/config
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/workstyle.toml $(HOME)/.config/workstyle/config.toml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/xinitrc $(HOME)/.xinitrc
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/chrony.conf /etc/chrony.conf
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/xinitrc /etc/environment
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/NetworkManager-dispatcher.service /etc/systemd/system/NetworkManager-dispatcher.service
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/limits.conf /etc/security/limits.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/modules-load.d/bbr.conf /etc/modules-load.d/bbr.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/tlp /etc/default/tlp
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/tlp /etc/tlp.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/suduers /etc/sudoers.d/kpango
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/sway.sh /etc/profile.d/sway.sh
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/xinitrc /etc/profile.d/fcitx.sh
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/config.json $(HOME)/.docker/config.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/config.json /etc/docker/config.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/daemon.json $(HOME)/.docker/daemon.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/daemon.json /etc/docker/daemon.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/dnsmasq.conf /etc/NetworkManager/dnsmasq.d/dnsmasq.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/resolv.dnsmasq.conf /etc/resolv.dnsmasq.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/sysctl.conf /etc/sysctl.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/thinkfan.conf /etc/thinkfan.conf
	sudo echo "options thinkpad_acpi fan_control=1" | sudo tee /etc/modprobe.d/thinkfan.conf
	sudo modprobe -rv thinkpad_acpi
	sudo modprobe -v thinkpad_acpi
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo chown root:root /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo sysctl -p
	sudo systemctl daemon-reload

arch_p1_link: \
	arch_link
	sudo echo "options bbswitch load_state=0 unload_state=1" | sudo tee /etc/modprobe.d/bbswitch.conf
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/nvidia-enable-power-off.service /etc/systemd/system/nvidia-enable-power-off.service
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/nvidia-disable-resume.service /etc/systemd/system/nvidia-disable-resume.service
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/default.pa /etc/pulse/default.pa
	sudo systemctl daemon-reload


clean:
	# sed -e "/\[\ \-f\ \$HOME\/\.aliases\ \]\ \&\&\ source\ \$HOME\/\.aliases/d" ~/.bashrc
	# sed -e "/\[\ \-f\ \$HOME\/\.aliases\ \]\ \&\&\ source\ \$HOME\/\.aliases/d" ~/.zshrc
	sudo rm -rf \
		$(HOME)/.Xdefaults \
		$(HOME)/.Xmodmap \
		$(HOME)/.aliases \
		$(HOME)/.config/TabNine \
		$(HOME)/.config/alacritty \
		$(HOME)/.config/compton \
		$(HOME)/.config/fcitx \
		$(HOME)/.config/i3 \
		$(HOME)/.config/i3status \
		$(HOME)/.config/nvim \
		$(HOME)/.config/ranger \
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
		$(HOME)/.gitconfig \
		$(HOME)/.gitignore \
		$(HOME)/.tmux-kube \
		$(HOME)/.tmux.conf \
		$(HOME)/.tmux.new-session \
		$(HOME)/.xinitrc \
		$(HOME)/.zshrc \
		/etc/NetworkManager/NetworkManager.conf \
		/etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh \
		/etc/NetworkManager/dnsmasq.d/dnsmasq.conf \
		/etc/chrony.conf \
		/etc/dbus-1/system.d/pulseaudio-bluetooth.conf \
		/etc/default/tlp \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
		/etc/environment \
		/etc/lightdm \
		/etc/modprobe.d/bbswitch.conf \
		/etc/modprobe.d/thinkfan.conf \
		/etc/modules-load.d/bbr.conf \
		/etc/profile.d/fcitx.sh \
		/etc/profile.d/sway.sh \
		/etc/pulse/default.pa \
		/etc/sudoers.d/kpango \
		/etc/sysctl.conf \
		/etc/systemd/system/NetworkManager-dispatcher.service \
		/etc/systemd/system/nvidia-disable-resume.service \
		/etc/systemd/system/nvidia-enable-power-off.service \
		/etc/systemd/system/pulseaudio.service \
		/etc/tlp.conf \
		/etc/udev/rules.d/60-ioschedulers.rules

zsh: link
	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc

bash: link
	[ -f $(HOME)/.bashrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.bashrc

build: \
	login \
	build_base
	@xpanes -s -c "make -f $(GOPATH)/src/github.com/kpango/dotfiles/Makefile build_and_push_{}" go docker rust dart k8s nim gcloud env base
	# @make prod

prod: \
	prod_build \
	prod_push

docker_build:
	docker build --squash --network=host -t ${IMAGE_NAME}:latest -f ${DOCKERFILE} .
	# docker build --squash --no-cache --network=host -t ${IMAGE_NAME}:latest -f ${DOCKERFILE} .

docker_push:
	docker push ${IMAGE_NAME}:latest

prod_build:
	@make DOCKERFILE="$(ROOTDIR)/Dockerfile" IMAGE_NAME="kpango/dev" docker_build

build_go:
	@make DOCKERFILE="$(ROOTDIR)/dockers/go.Dockerfile" IMAGE_NAME="kpango/go" docker_build

build_rust:
	@make DOCKERFILE="$(ROOTDIR)/dockers/rust.Dockerfile" IMAGE_NAME="kpango/rust" docker_build

build_nim:
	@make DOCKERFILE="$(ROOTDIR)/dockers/nim.Dockerfile" IMAGE_NAME="kpango/nim" docker_build

build_dart:
	@make DOCKERFILE="$(ROOTDIR)/dockers/dart.Dockerfile" IMAGE_NAME="kpango/dart" docker_build

build_docker:
	@make DOCKERFILE="$(ROOTDIR)/dockers/docker.Dockerfile" IMAGE_NAME="kpango/docker" docker_build

build_base:
	@make DOCKERFILE="$(ROOTDIR)/dockers/base.Dockerfile" IMAGE_NAME="kpango/dev-base" docker_build

build_env:
	@make DOCKERFILE="$(ROOTDIR)/dockers/env.Dockerfile" IMAGE_NAME="kpango/env" docker_build

build_gcloud:
	@make DOCKERFILE="$(ROOTDIR)/dockers/gcloud.Dockerfile" IMAGE_NAME="kpango/gcloud" docker_build

build_k8s:
	@make DOCKERFILE="$(ROOTDIR)/dockers/k8s.Dockerfile" IMAGE_NAME="kpango/kube" docker_build

prod_push:
	@make IMAGE_NAME="kpango/dev" docker_push

push_go:
	@make IMAGE_NAME="kpango/go" docker_push

push_rust:
	@make IMAGE_NAME="kpango/rust" docker_push

push_nim:
	@make IMAGE_NAME="kpango/nim" docker_push

push_dart:
	@make IMAGE_NAME="kpango/dart" docker_push

push_docker:
	@make IMAGE_NAME="kpango/docker" docker_push

push_base:
	@make IMAGE_NAME="kpango/dev-base" docker_push

push_env:
	@make IMAGE_NAME="kpango/env" docker_push

push_gcloud:
	@make IMAGE_NAME="kpango/gcloud" docker_push

push_k8s:
	@make IMAGE_NAME="kpango/kube" docker_push


build_and_push_base: \
	build_base \
	push_base

build_and_push_env: \
	build_env \
	push_env

build_and_push_go: \
	build_go \
	push_go

build_and_push_rust: \
	build_rust \
	push_rust \
	prod

build_and_push_docker: \
	build_docker \
	push_docker

build_and_push_k8s: \
	build_k8s \
	push_k8s

build_and_push_nim: \
	build_nim \
	push_nim

build_and_push_dart: \
	build_dart \
	push_dart

build_and_push_gcloud: \
	build_gcloud \
	push_gcloud


build_all: \
	build_base \
	build_env \
	build_dart \
	build_docker \
	build_gcloud \
	build_go \
	build_k8s \
	build_nim \
	prod_build
	echo "done"

push_all: \
	push_base \
	push_env \
	push_dart \
	push_docker \
	push_gcloud \
	push_go \
	push_k8s \
	push_nim \
	prod_push
	echo "done"

profile:
	rm -f analyze.txt
	type dlayer >/dev/null 2>&1 && docker save kpango/dev:latest | dlayer >> analyze.txt

login:
	docker login -u kpango

push:
	docker push kpango/dev:latest

pull:
	docker pull kpango/dev:latest

perm:
	chmod -R 755 $(ROOTDIR)/*
	chmod -R 755 $(ROOTDIR)/.*
	chown -R 1000:985 $(ROOTDIR)/*
	chown -R 1000:985 $(ROOTDIR)/.*

git_push:
	git add -A
	git commit -m fix
	git push
