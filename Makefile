.PHONY: link zsh bash build run push pull

link:
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/alias $(HOME)/.aliases

zsh: link
	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc

bash: link
	[ -f $(HOME)/.bashrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.bashrc

build:
	docker build -t kpango/dev:latest .

run:
	source ./alias && devrun

push:
	docker push kpango/dev:latest

pull:
	docker pull kpango/dev:latest
