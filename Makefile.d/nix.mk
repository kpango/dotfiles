.PHONY: nix/setup

define NIX_SETUP_DARWIN
	if [ ! -f /Applications/Container.app/Contents/MacOS/Container ] && [ ! -d /Applications/Container.app ]; then \
		echo "=> Installing Apple Container..."; \
		curl -LO https://github.com/apple/container/releases/download/0.4.1/container-0.4.1-installer-signed.pkg; \
		sudo installer -pkg container-0.4.1-installer-signed.pkg -target /; \
		rm -f container-0.4.1-installer-signed.pkg; \
		echo "=> Apple Container installed successfully."; \
	else \
		echo "=> Apple Container is already installed."; \
	fi; \
	echo "=> Extracting macOS defaults to all-defaults.nix..."; \
	if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then \
		. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; \
	fi; \
	$$(which nix) run github:joshryandavis/defaults2nix -- -all -filter dates,state,uuids -out ./all-defaults.nix; \
	if [ -n "$$SUDO_USER" ]; then sudo chown $$SUDO_USER ./all-defaults.nix || true; fi; \
	if [ ! -s ./all-defaults.nix ]; then \
		echo "Warning: defaults2nix failed or returned empty. Creating an empty fallback."; \
		echo "{}" > ./all-defaults.nix; \
	fi
endef

define NIX_BUILD_NIXOS
	echo "=> NixOS detected. Updating channels and flakes..."; \
	sudo nix-channel --update; \
	nix flake update ./nix; \
	if [ -f /mnt/etc/nixos/configuration.nix ]; then \
		echo "=> Installing NixOS to /mnt..."; \
		sudo nixos-install --root /mnt --flake ./nix#$(NIX_HOST_NAME); \
	else \
		echo "=> Rebuilding NixOS..."; \
		sudo nixos-rebuild switch --flake ./nix#$(NIX_HOST_NAME); \
	fi
endef

nix/setup:
	@echo "=========================================================="
	@echo " Starting Nix Development Environment Setup"
	@echo " User: $$(whoami), Hostname: $(NIX_HOST_NAME), OS: $$(uname -s)"
	@echo "=========================================================="
	@if ! command -v nix >/dev/null 2>&1; then \
		echo "=> Installing Nix (Determinate Systems)..."; \
		curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm; \
	else \
		echo "=> Nix is already installed."; \
	fi
	@if [ "$$(uname -s)" = "Darwin" ]; then \
		$(NIX_SETUP_DARWIN); \
	fi
	@echo "=> Initializing Git repository (Flakes require files to be tracked by Git)..."
	@if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		if [ -n "$$SUDO_USER" ]; then sudo -u $$SUDO_USER git init; else git init; fi; \
	fi
	@echo "=> Injecting absolute dotfiles path from git..."
	@sed -i -e '/dotfilesDir = {/,/};/s|linux = ".*";|linux = "$(ROOTDIR)";|g' nix/core/settings.nix
	@sed -i -e '/dotfilesDir = {/,/};/s|darwin = ".*";|darwin = "$(ROOTDIR)";|g' nix/core/settings.nix
	@if [ -n "$$SUDO_USER" ]; then \
		sudo -u $$SUDO_USER git add .; \
		if ! sudo -u $$SUDO_USER git config user.name >/dev/null 2>&1; then sudo -u $$SUDO_USER git config user.name "$$SUDO_USER"; fi; \
		if ! sudo -u $$SUDO_USER git config user.email >/dev/null 2>&1; then sudo -u $$SUDO_USER git config user.email "$$SUDO_USER@localhost"; fi; \
		sudo -u $$SUDO_USER git commit -m "Initial commit for Nix configuration" || true; \
	else \
		git add .; \
		if ! git config user.name >/dev/null 2>&1; then git config user.name "$$(whoami)"; fi; \
		if ! git config user.email >/dev/null 2>&1; then git config user.email "$$(whoami)@localhost"; fi; \
		git commit -m "Initial commit for Nix configuration" || true; \
	fi
	@echo "=> Running initial nix build for host: $(NIX_HOST_NAME)..."
	@if [ "$$(uname -s)" = "Darwin" ]; then \
		echo "=> Note: Running nix-darwin switch as root."; \
		echo "=> (nix-darwin now requires root for system activation)"; \
		if [ -n "$$SUDO_USER" ]; then \
			if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; fi; sudo -u $$SUDO_USER sh -c "cd '$$PWD' && sudo nix run nix-darwin -- switch --flake ./nix#$(NIX_HOST_NAME)"; \
		else \
			if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; fi; sudo nix run nix-darwin -- switch --flake ./nix#$(NIX_HOST_NAME); \
		fi; \
	elif grep -q "NixOS" /etc/os-release >/dev/null 2>&1 || [ -f /etc/NIXOS ]; then \
		$(NIX_BUILD_NIXOS); \
	else \
		if command -v nixos-rebuild >/dev/null 2>&1; then \
			if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh; fi; sudo nixos-rebuild switch --flake ./nix#$(NIX_HOST_NAME); \
		else \
			echo "=> nixos-rebuild not found, assuming non-NixOS Linux. Skipping NixOS rebuild."; \
		fi; \
	fi
	@echo "=========================================================="
	@echo " Setup complete! Please open a new terminal or run 'exec zsh'"
	@echo "=========================================================="
