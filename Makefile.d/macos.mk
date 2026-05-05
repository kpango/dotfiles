.PHONY: mac_link mac_copy

MACOS_LAUNCH_AGENTS = localhost.homebrew-autoupdate.plist ulimit.plist

define MAC_PREP
	sudo rm -rf \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
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
endef

mac_link: \
	link
	$(MAC_PREP)
	ln -sfv $(ROOTDIR)/macos/docker_config.json $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	sudo ln -sfv $(ROOTDIR)/macos/docker_config.json /etc/docker/config.json
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		sudo ln -sfv "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chown root:wheel "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua

mac_copy: \
	copy
	$(MAC_PREP)
	cp $(ROOTDIR)/macos/docker_config.json $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	sudo cp $(ROOTDIR)/macos/docker_config.json /etc/docker/config.json
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		sudo cp "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chown root:wheel "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua