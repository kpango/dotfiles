.PHONY: all link zsh bash build prod_build profile run push pull

all: prod_build login push profile git_push

run:
	source ./alias && devrun

link:
	mkdir -p ${HOME}/.config/nvim/colors
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/init.vim $(HOME)/.config/nvim/init.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/efm-lsp-conf.yaml $(HOME)/.config/nvim/efm-lsp-conf.yaml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/coc-settings.json $(HOME)/.config/nvim/coc-settings.json
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/monokai.vim $(HOME)/.config/nvim/colors/monokai.vim
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/efm-lsp-conf.yaml $(HOME)/.config/nvim/efm-lsp-conf.yaml
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/zshrc $(HOME)/.zshrc
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/alias $(HOME)/.aliases
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/gitconfig $(HOME)/.gitconfig
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/gitattributes $(HOME)/.gitattributes
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/gitignore $(HOME)/.gitignore
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/tmux.conf $(HOME)/.tmux.conf
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/tmux-kube $(HOME)/.tmux-kube
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/tmux.new-session $(HOME)/.tmux.new-session

arch_link:
	mkdir -p ${HOME}/.config/sway
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/arch/sway.conf $(HOME)/.config/sway/config
	sudo ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/arch/tmux.service /etc/systemd/system/tmux@.service

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
	type minid >/dev/null 2>&1 && minid -f ${DOCKERFILE} | docker build -t ${IMAGE_NAME}:latest -f - .

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

build_all: build_base build_env build_go build_rust build_go build_nim build_dart build_docker build_gcloud build_k8s build_glibc prod_build
	echo "done"

push_all: push_base push_env push_go push_rust push_go push_nim push_dart push_docker push_gcloud push_k8s push_glibc prod_push
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
