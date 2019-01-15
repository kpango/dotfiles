.PHONY: zsh bash build push

zsh:
	ln -sfv ./alias $(HOME)/.zsh_aliases

bash:
	ln -sfv ./alias $(HOME)/.bash_aliases

build:
	docker build -t kpango/dev:latest .

push:
	docker push kpango/dev:latest
