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

arch_link: link
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/gitconfig $(HOME)/.gitconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/xinitrc $(HOME)/.xinitrc
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/Xmodmap $(HOME)/.Xmodmap
	mkdir -p ${HOME}/.config/sway
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/sway.conf $(HOME)/.config/sway/config
	mkdir -p ${HOME}/.config/i3
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/i3.conf $(HOME)/.config/i3/config
	mkdir -p ${HOME}/.config/i3status
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/i3status.conf $(HOME)/.config/i3status/config
	mkdir -p ${HOME}/.config/rofi
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/rofi/sidebar.rasi $(HOME)/.config/rofi/sidebar.rasi
	mkdir -p ${HOME}/.config/picom
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/picom.conf $(HOME)/.config/picom/picom.conf
	mkdir -p ${HOME}/.config/fcitx/conf
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/fcitx-classic-ui.config $(HOME)/.config/fcitx/conf/fcitx-classic-ui.config
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/ranger $(HOME)/.config/ranger
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/Xdefaults $(HOME)/.Xdefaults
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/modules-load.d/bbr.conf /etc/modules-load.d/bbr.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))network/sysctl.conf /etc/sysctl.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/resolv.conf /etc/resolv.conf
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/pulseaudio-bluetooth.conf /etc/dbus-1/system.d/pulseaudio-bluetooth.conf
	mkdir -p /etc/docker
	mkdir -p ${HOME}/.docker
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/daemon.json /etc/docker/daemon.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))dockers/daemon.json $(HOME)/.docker/daemon.json
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/lightdm.conf /etc/lightdm/lightdm.conf
	sudo cp $(dir $(abspath $(lastword $(MAKEFILE_LIST))))arch/pulseaudio.service /etc/systemd/system/pulseaudio.service
	sudo systemctl daemon-reload
	sudo systemctl enable pulseaudio
	sudo systemctl start pulseaudio
	sudo systemctl status pulseaudio
	sudo journalctl | grep pulseaudio

clean:
	sed -e "/\[\ \-f\ \$HOME\/\.aliases\ \]\ \&\&\ source\ \$HOME\/\.aliases/d" ~/.bashrc
	sed -e "/\[\ \-f\ \$HOME\/\.aliases\ \]\ \&\&\ source\ \$HOME\/\.aliases/d" ~/.zshrc
	rm $(HOME)/.aliases

zsh: link
	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc

bash: link
	[ -f $(HOME)/.bashrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.bashrc

build:
	docker build -t kpango/dev:latest .

docker_build:
	docker build --squash -t ${IMAGE_NAME}:latest -f ${DOCKERFILE} .

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

build_glibc:
	@make DOCKERFILE="./dockers/glibc.Dockerfile" IMAGE_NAME="kpango/glibc" docker_build

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

push_glibc:
	@make IMAGE_NAME="kpango/glibc" docker_push

build_all: \
	build_base \
	build_env \
	build_dart \
	build_docker \
	build_gcloud \
	build_glibc \
	build_go \
	build_k8s \
	build_nim \
	build_rust \
	prod_build
	echo "done"

push_all: \
	push_base \
	push_env \
	push_dart \
	push_docker \
	push_gcloud \
	push_glibc \
	push_go \
	push_k8s \
	push_nim \
	push_rust \
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

git_push:
	git add -A
	git commit -m fix
	git push
