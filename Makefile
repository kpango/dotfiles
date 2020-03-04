.PHONY: all link zsh bash build prod_build profile run push pull

all: prod_build login push profile git_push

run:
	source ./alias && devrun

link:
	mkdir -p ${HOME}/.config/nvim/colors
	mkdir -p ${HOME}/.config/nvim/syntax
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))init.vim $(HOME)/.config/nvim/init.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))starship.toml $(HOME)/.config/starship.toml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))efm-lsp-conf.yaml $(HOME)/.config/nvim/efm-lsp-conf.yaml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))coc-settings.json $(HOME)/.config/nvim/coc-settings.json
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))monokai.vim $(HOME)/.config/nvim/colors/monokai.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))go.vim $(HOME)/.config/nvim/syntax/go.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))efm-lsp-conf.yaml $(HOME)/.config/nvim/efm-lsp-conf.yaml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))zshrc $(HOME)/.zshrc
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))editorconfig $(HOME)/.editorconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))alias $(HOME)/.aliases
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))gitconfig $(HOME)/.gitconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))gitattributes $(HOME)/.gitattributes
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))gitignore $(HOME)/.gitignore
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))tmux.conf $(HOME)/.tmux.conf
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))tmux-kube $(HOME)/.tmux-kube
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))tmux.new-session $(HOME)/.tmux.new-session

arch_link: \
	clean \
	link
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/gitconfig $(HOME)/.gitconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/xinitrc $(HOME)/.xinitrc
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/Xmodmap $(HOME)/.Xmodmap
	mkdir -p ${HOME}/.config/sway
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/sway.conf $(HOME)/.config/sway/config
	mkdir -p ${HOME}/.config/waybar
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/waybar.conf $(HOME)/.config/waybar/config
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/waybar.css $(HOME)/.config/waybar/style.css
	mkdir -p ${HOME}/.config/alacritty
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/alacritty.yml $(HOME)/.config/alacritty/alacritty.yml
	# mkdir -p ${HOME}/.config/rofi
	# ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/rofi/sidebar.rasi $(HOME)/.config/rofi/sidebar.rasi
	mkdir -p ${HOME}/.config/fcitx/conf
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/fcitx-classic-ui.config $(HOME)/.config/fcitx/conf/fcitx-classic-ui.config
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/ranger $(HOME)/.config/ranger
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/modules-load.d/bbr.conf /etc/modules-load.d/bbr.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/60-ioschedulers.rules /etc/udev/rules.d/60-ioschedulers.rules
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/sysctl.conf /etc/sysctl.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/limits.conf /etc/security/limits.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/suduers /etc/sudoers.d/kpango
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/NetworkManager.conf /etc/NetworkManager/NetworkManager.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/dnsmasq.conf /etc/NetworkManager/dnsmasq.d/dnsmasq.conf
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/nmcli-wifi-eth-autodetect.sh /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo chmod a+x /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	sudo chown root:root /etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh
	# sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/NetworkManager-dispatcher.service /etc/systemd/system/NetworkManager-dispatcher.service
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/resolv.dnsmasq.conf /etc/resolv.dnsmasq.conf
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/chrony.conf /etc/chrony.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/sway.sh /etc/profile.d/sway.sh
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/xinitrc /etc/profile.d/fcitx.sh
	mkdir -p /etc/docker
	mkdir -p ${HOME}/.docker
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/daemon.json /etc/docker/daemon.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/config.json /etc/docker/config.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/daemon.json $(HOME)/.docker/daemon.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/config.json $(HOME)/.docker/config.json
	sudo sysctl -p
	sudo systemctl daemon-reload

clean:
	# sed -e "/\[\ \-f\ \$HOME\/\.aliases\ \]\ \&\&\ source\ \$HOME\/\.aliases/d" ~/.bashrc
	# sed -e "/\[\ \-f\ \$HOME\/\.aliases\ \]\ \&\&\ source\ \$HOME\/\.aliases/d" ~/.zshrc
	sudo rm -rf $(HOME)/.Xdefaults \
		$(HOME)/.Xmodmap \
		$(HOME)/.aliases \
		$(HOME)/.config/alacritty \
		$(HOME)/.config/compton \
		$(HOME)/.config/fcitx \
		$(HOME)/.config/i3 \
		$(HOME)/.config/i3status \
		$(HOME)/.config/waybar \
		$(HOME)/.config/nvim \
		$(HOME)/.config/ranger \
		$(HOME)/.config/rofi \
		$(HOME)/.config/starship.toml \
		$(HOME)/.config/sway \
		$(HOME)/.docker/daemon.json \
		$(HOME)/.docker/config.json \
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
		/etc/NetworkManager/dnsmasq.d/dnsmasq.conf \
		/etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh \
		/etc/chrony.conf \
		/etc/dbus-1/system.d/pulseaudio-bluetooth.conf \
		/etc/docker/daemon.json \
		/etc/docker/config.json \
		/etc/lightdm \
		/etc/modules-load.d/bbr.conf \
		/etc/profile.d/fcitx.sh \
		/etc/profile.d/sway.sh \
		/etc/sudoers.d/kpango \
		/etc/sysctl.conf \
		/etc/systemd/system/NetworkManager-dispatcher.service \
		/etc/systemd/system/pulseaudio.service \
		/etc/udev/rules.d/60-ioschedulers.rules

zsh: link
	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc

bash: link
	[ -f $(HOME)/.bashrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.bashrc

build: \
	prod_build

docker_build:
	docker build --squash --network=host -t ${IMAGE_NAME}:latest -f ${DOCKERFILE} .

docker_push:
	docker push ${IMAGE_NAME}:latest

prod_build:
	@make DOCKERFILE="./Dockerfile" IMAGE_NAME="kpango/dev" docker_build

build_go:
	@make DOCKERFILE="./dockers/go.Dockerfile" IMAGE_NAME="kpango/go" docker_build

build_rust:
	@make DOCKERFILE="./dockers/rust.Dockerfile" IMAGE_NAME="kpango/rust" docker_build

build_nim:
	@make DOCKERFILE="./dockers/nim.Dockerfile" IMAGE_NAME="kpango/nim" docker_build

build_dart:
	@make DOCKERFILE="./dockers/dart.Dockerfile" IMAGE_NAME="kpango/dart" docker_build

build_docker:
	@make DOCKERFILE="./dockers/docker.Dockerfile" IMAGE_NAME="kpango/docker" docker_build

build_base:
	@make DOCKERFILE="./dockers/base.Dockerfile" IMAGE_NAME="kpango/dev-base" docker_build

build_env:
	@make DOCKERFILE="./dockers/env.Dockerfile" IMAGE_NAME="kpango/env" docker_build

build_gcloud:
	@make DOCKERFILE="./dockers/gcloud.Dockerfile" IMAGE_NAME="kpango/gcloud" docker_build

build_k8s:
	@make DOCKERFILE="./dockers/k8s.Dockerfile" IMAGE_NAME="kpango/kube" docker_build

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
	chmod -R 755 ./*
	chmod -R 755 ./.*
	chown -R 1000:985 ./*
	chown -R 1000:985 ./.*

git_push:
	git add -A
	git commit -m fix
	git push
