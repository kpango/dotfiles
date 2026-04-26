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
	sudo $$(which nix) run github:joshryandavis/defaults2nix -- -all -filter dates,state,uuids -o ./all-defaults.nix; \
	sudo chown $$(whoami) ./all-defaults.nix || true; \
	if [ ! -s ./all-defaults.nix ]; then \
		echo "Warning: defaults2nix failed or returned empty. Creating an empty fallback."; \
		echo "{}" > ./all-defaults.nix; \
	fi
endef

define NIX_BUILD_NIXOS
	echo "=> NixOS detected. Updating channels and flakes..."; \
	sudo nix-channel --update; \
	nix flake update; \
	if [ -f /mnt/etc/nixos/configuration.nix ]; then \
		echo "=> Installing NixOS to /mnt..."; \
		sudo nixos-install --root /mnt --flake .#$(NIX_HOST_NAME); \
	else \
		echo "=> Rebuilding NixOS..."; \
		sudo nixos-rebuild switch --flake .#$(NIX_HOST_NAME); \
	fi
endef

nix/setup:
	@echo "=========================================================="
	@echo " Starting Nix Development Environment Setup"
	@echo " User: $$(whoami), Hostname: $(NIX_HOST_NAME), OS: $$(uname -s)"
	@echo "=========================================================="
	@if ! command -v nix >/dev/null 2>&1; then \
		echo "=> Installing Nix (Determinate Systems)..."; \
		curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install; \
	else \
		echo "=> Nix is already installed."; \
	fi
	@if [ "$$(uname -s)" = "Darwin" ]; then \
		$(NIX_SETUP_DARWIN); \
	fi
	@echo "=> Initializing Git repository (Flakes require files to be tracked by Git)..."
	@if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		git init; \
	fi
	@echo "=> Injecting absolute dotfiles path from git..."
	@sed -i -e '/dotfilesDir = {/,/};/s|linux = ".*";|linux = "$(ROOTDIR)";|g' nix/core/settings.nix
	@sed -i -e '/dotfilesDir = {/,/};/s|darwin = ".*";|darwin = "$(ROOTDIR)";|g' nix/core/settings.nix
	@git add .
	@git commit -m "Initial commit for Nix configuration" || true
	@echo "=> Running initial nix build for host: $(NIX_HOST_NAME)..."
	@if [ "$$(uname -s)" = "Darwin" ]; then \
		echo "=> Note: Running nix-darwin switch as a regular user to avoid Home Manager conflicts."; \
		echo "=> (sudo permissions will be automatically requested during the build process if needed)"; \
		. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && nix run nix-darwin -- switch --flake .#$(NIX_HOST_NAME); \
	elif grep -q "NixOS" /etc/os-release >/dev/null 2>&1 || [ -f /etc/NIXOS ]; then \
		$(NIX_BUILD_NIXOS); \
	else \
		. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && sudo nixos-rebuild switch --flake .#$(NIX_HOST_NAME); \
	fi
	@echo "=========================================================="
	@echo " Setup complete! Please open a new terminal or run 'exec zsh'"
	@echo "=========================================================="
