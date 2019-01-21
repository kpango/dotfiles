.PHONY: zsh bash build push

link:
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/alias $(HOME)/.aliases

zsh: link
	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc

bash: link
	[ -f $(HOME)/.bashrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.bashrc

build:
	docker build -t kpango/dev:latest .

push:
	docker push kpango/dev:latest
