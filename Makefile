.PHONY: link zsh bash build prod_build profile run push pull

run:
	source ./alias && devrun

link:
	ln -sfv $(dir $(abspath $(lastword $(MAKEFILE_LIST))))/alias $(HOME)/.aliases

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

prod_build:
	type minid >/dev/null 2>&1 && minid | docker build -t kpango/dev:latest -f - .

profile:
	type dlayer >/dev/null 2>&1 && docker save kpango/dev:latest | dlayer >> analyze.txt

push:
	docker push kpango/dev:latest

pull:
	docker pull kpango/dev:latest
