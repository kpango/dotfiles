.PHONY: nix/setup \
	nix/test nix/test/eval nix/test/eval/darwin nix/test/check \
	nix/test/dry-run nix/test/dry-run/darwin \
	nix/test/build nix/test/build/darwin \
	nix/test/vm nix/test/vm/build \
	nix/test/docker \
	nix/fmt nix/fmt/check \
	nix/update nix/pull

# ─────────────────────────────────────────────────────────────────────────────
# Variables
# ─────────────────────────────────────────────────────────────────────────────

# Default host for single-host build/vm targets (override: make nix/test/build NIX_HOST_NAME=tr)
NIX_HOST_NAME ?= tr

# Hosts evaluated in nix/test/eval (space-separated)
NIX_TEST_HOSTS ?= tr p1 x1 g2

# Darwin hosts evaluated in nix/test/eval/darwin and nix/test/dry-run/darwin
# (space-separated). Must match nix/flake.nix's darwinConfigurations attribute
# names. Unlike NIX_TEST_HOSTS these are checked unconditionally (fixed small
# set, no per-host override needed) so a plain `make nix/test` catches darwin
# regressions from Linux without waiting on the macos-14 CI runner.
NIX_TEST_DARWIN_HOSTS ?= macbook-air-m1 macbook-pro-m3 macbook-pro-m1

# NixOS container image used when nix is not installed natively
NIX_DOCKER_IMAGE ?= ghcr.io/nixos/nix:latest

# Script that dispatches nix commands to native nix or the NixOS container
# (uses named Docker volume NIX_VOLUME_NAME for persistent nix store)
NIX_RUN := DOTFILES_ROOT="$(ROOTDIR)" \
           NIX_DOCKER_IMAGE="$(NIX_DOCKER_IMAGE)" \
           $(ROOTDIR)/nix/scripts/nix-run.sh

# Flags for test/check targets: use pinned lock file, never update it accidentally
NIX_FLAGS ?= --no-update-lock-file --show-trace \
             --extra-experimental-features 'nix-command flakes'

# Flags for flake update: allow writing flake.lock
NIX_UPDATE_FLAGS ?= --show-trace \
                    --extra-experimental-features 'nix-command flakes'

# ─────────────────────────────────────────────────────────────────────────────
# nix/setup — install Nix (Determinate), initialise git and build the config
# ─────────────────────────────────────────────────────────────────────────────

define NIX_SETUP_DARWIN
	echo "=> Apple Container is managed by nix-darwin now (modules/darwin/containerization.nix, inputs.nix-apple-container) — no ad-hoc pkg-installer bootstrap needed here."; \
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

## install Nix (Determinate), init git, and build the NixOS/nix-darwin config for NIX_HOST_NAME
nix/setup:
	@echo "=========================================================="
	@echo " Starting Nix Development Environment Setup"
	@echo " User: $$(whoami), Hostname: $(NIX_HOST_NAME), OS: $$(uname -s)"
	@echo "=========================================================="
	@if ! command -v nix >/dev/null 2>&1; then \
		echo "=> Installing Nix (Determinate Systems)..."; \
		curl --retry 3 --retry-all-errors --retry-delay 3 --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm; \
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

# ─────────────────────────────────────────────────────────────────────────────
# nix/update — update flake.lock
# ─────────────────────────────────────────────────────────────────────────────

## update flake.lock to the latest input revisions
nix/update:
	@echo "=> Updating flake.lock..."
	@NIX_WRITABLE=1 $(NIX_RUN) flake update $(NIX_UPDATE_FLAGS)

# ─────────────────────────────────────────────────────────────────────────────
# nix/pull — pre-fetch the NixOS container image
# ─────────────────────────────────────────────────────────────────────────────

## pull the NixOS container image (NIX_DOCKER_IMAGE) used on non-NixOS hosts
nix/pull:
	@echo "=> Pulling NixOS container image: $(NIX_DOCKER_IMAGE)"
	@docker pull "$(NIX_DOCKER_IMAGE)"

# ─────────────────────────────────────────────────────────────────────────────
# nix/test targets
#
# Hierarchy:
#   nix/test                 — eval + eval/darwin + flake-check + dry-run + dry-run/darwin (default CI gate)
#   nix/test/eval            — fast: evaluate every NixOS host config (no derivation builds)
#   nix/test/eval/darwin     — fast: evaluate every darwin host config (no derivation builds)
#   nix/test/check           — nix flake check --no-build (type-checks all outputs)
#   nix/test/dry-run         — resolve NixOS derivation graph (NIX_HOST_NAME) without building binaries
#   nix/test/dry-run/darwin  — resolve every darwin host's derivation graph, same way
#   nix/test/build           — full NixOS system closure build (slow; useful before switch)
#   nix/test/vm              — build & boot a QEMU VM for interactive smoke-testing
#
# nix/test/eval/darwin and nix/test/dry-run/darwin run entirely on Linux: attribute
# evaluation and --dry-run derivation-graph resolution need no aarch64-darwin
# builder (they only read the flake and query substituters), so they catch the
# same class of regression that used to be visible only via the darwin-build CI
# job on a real macos-14 runner (see nix/test/build/darwin) — several minutes
# there vs. seconds here, and they run on every push/PR instead of needing a
# scarcer macOS runner slot.
#
# All targets work on Arch Linux / macOS (via Docker) and on NixOS (native nix).
# ─────────────────────────────────────────────────────────────────────────────

## Evaluate every NixOS host configuration (no build, catches attribute/type errors).
## Fast (~seconds per host using binary cache for eval).
nix/test/eval:
	@echo "==================================================="
	@echo " nix/test/eval  — evaluating $(words $(NIX_TEST_HOSTS)) host(s)"
	@echo "==================================================="
	@failed=0; \
	for host in $(NIX_TEST_HOSTS); do \
		printf "  %-30s " "$$host"; \
		if $(NIX_RUN) eval \
			".#nixosConfigurations.$$host.config.system.stateVersion" \
			$(NIX_FLAGS) >/dev/null 2>&1; then \
			echo "OK"; \
		else \
			echo "FAILED"; \
			$(NIX_RUN) eval \
				".#nixosConfigurations.$$host.config.system.stateVersion" \
				$(NIX_FLAGS) 2>&1 | sed 's/^/    /'; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo ""; \
		echo "  $$failed host(s) failed evaluation."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "  All hosts evaluated successfully."

## Evaluate every darwin host configuration (no build, catches attribute/type
## errors). Runs on Linux: darwinSystem's `system = aarch64-darwin` is only
## metadata at this attribute, so no aarch64-darwin builder is required.
nix/test/eval/darwin:
	@echo "==================================================="
	@echo " nix/test/eval/darwin  — evaluating $(words $(NIX_TEST_DARWIN_HOSTS)) host(s)"
	@echo "==================================================="
	@failed=0; \
	for host in $(NIX_TEST_DARWIN_HOSTS); do \
		printf "  %-30s " "$$host"; \
		if $(NIX_RUN) eval \
			".#darwinConfigurations.$$host.config.system.stateVersion" \
			$(NIX_FLAGS) >/dev/null 2>&1; then \
			echo "OK"; \
		else \
			echo "FAILED"; \
			$(NIX_RUN) eval \
				".#darwinConfigurations.$$host.config.system.stateVersion" \
				$(NIX_FLAGS) 2>&1 | sed 's/^/    /'; \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo ""; \
		echo "  $$failed host(s) failed evaluation."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "  All darwin hosts evaluated successfully."

## nix flake check --no-build: type-checks all flake outputs without building.
nix/test/check:
	@echo "==================================================="
	@echo " nix/test/check — nix flake check"
	@echo "==================================================="
	@$(NIX_RUN) flake check --no-build $(NIX_FLAGS)
	@echo "  flake check passed."

## Dry-run build: fully resolve the derivation graph for NIX_HOST_NAME without
## downloading/compiling anything. Catches missing packages and hash mismatches.
nix/test/dry-run:
	@echo "==================================================="
	@echo " nix/test/dry-run — $(NIX_HOST_NAME)"
	@echo "==================================================="
	@$(NIX_RUN) build \
		".#nixosConfigurations.$(NIX_HOST_NAME).config.system.build.toplevel" \
		--dry-run $(NIX_FLAGS)
	@echo "  dry-run passed."

## Dry-run build for every darwin host (NIX_TEST_DARWIN_HOSTS): fully resolve
## each derivation graph without downloading/compiling anything. Catches
## missing packages and hash mismatches (e.g. the `lumen` regression this
## target exists to catch locally, before it reaches darwin-build CI) from
## Linux, no aarch64-darwin builder required.
nix/test/dry-run/darwin:
	@echo "==================================================="
	@echo " nix/test/dry-run/darwin — $(words $(NIX_TEST_DARWIN_HOSTS)) host(s)"
	@echo "==================================================="
	@failed=0; \
	for host in $(NIX_TEST_DARWIN_HOSTS); do \
		echo "  -- $$host --"; \
		if ! $(NIX_RUN) build \
			".#darwinConfigurations.$$host.system" \
			--dry-run $(NIX_FLAGS); then \
			failed=$$((failed + 1)); \
		fi; \
	done; \
	if [ $$failed -gt 0 ]; then \
		echo ""; \
		echo "  $$failed darwin host(s) failed dry-run."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "  All darwin hosts dry-run passed."

## Full system build: compile the entire NixOS system closure for NIX_HOST_NAME.
## This is slow but produces an artifact that nixos-rebuild switch can activate.
## Override host with: make nix/test/build NIX_HOST_NAME=p1
nix/test/build:
	@echo "==================================================="
	@echo " nix/test/build — $(NIX_HOST_NAME)"
	@echo "==================================================="
	@$(NIX_RUN) build \
		".#nixosConfigurations.$(NIX_HOST_NAME).config.system.build.toplevel" \
		-j auto $(NIX_FLAGS)
	@echo "  build complete: ./result"

## Build nix-darwin system closure (macOS only).
## Override host: make nix/test/build/darwin NIX_HOST_NAME=macbook-air-m1
nix/test/build/darwin:
	@echo "==================================================="
	@echo " nix/test/build/darwin — $(NIX_HOST_NAME)"
	@echo "==================================================="
	@. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true; \
	cd "$(ROOTDIR)/nix" && \
	nix build \
		".#darwinConfigurations.$(NIX_HOST_NAME).system" \
		$(NIX_FLAGS) && \
	echo "  Darwin build complete: ./result"

## Evaluate a NixOS config inside the NixOS Docker container (no native nix required).
## Mirrors the nix-run.sh Docker fallback path used on non-NixOS hosts.
nix/test/docker:
	@echo "==================================================="
	@echo " nix/test/docker — $(NIX_HOST_NAME) via $(NIX_DOCKER_IMAGE)"
	@echo "==================================================="
	@docker volume inspect nix-store-dotfiles >/dev/null 2>&1 \
		|| docker volume create nix-store-dotfiles >/dev/null
	@docker run --rm \
		--workdir /dotfiles/nix \
		--volume "$(ROOTDIR):/dotfiles:ro" \
		--volume "nix-store-dotfiles:/nix" \
		--env "NIX_CONFIG=$(printf '%s\n' \
			'extra-experimental-features = nix-command flakes' \
			'trusted-users = root' \
			'substituters = https://cache.nixos.org/' \
			'trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=')" \
		"$(NIX_DOCKER_IMAGE)" \
		sh -c 'git config --global --add safe.directory /dotfiles && nix eval \
			".#nixosConfigurations.$(NIX_HOST_NAME).config.system.stateVersion" \
			--no-update-lock-file \
			--extra-experimental-features "nix-command flakes"'
	@echo "  Docker eval passed."

## Build a QEMU VM image for NIX_HOST_NAME without launching it.
## Suitable for CI: the image is at ./result/bin/run-$(NIX_HOST_NAME)-vm.
## Override host: make nix/test/vm/build NIX_HOST_NAME=x1
nix/test/vm/build:
	@echo "==================================================="
	@echo " nix/test/vm/build — $(NIX_HOST_NAME)"
	@echo "==================================================="
	@. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true; \
	if ! command -v nix >/dev/null 2>&1; then \
		echo "Error: 'nix' must be installed natively to build VM images."; \
		exit 1; \
	fi; \
	cd "$(ROOTDIR)/nix" && \
	nix build \
		".#nixosConfigurations.$(NIX_HOST_NAME).config.system.build.vm" \
		$(NIX_FLAGS) && \
	REAL_VM=$$(ls ./result/bin/run-*-vm 2>/dev/null | head -1) && \
	if [ -z "$$REAL_VM" ]; then \
		echo "Error: no run-*-vm binary found in ./result/bin/ after nix build"; \
		ls -la ./result/bin/ 2>/dev/null || echo "  (result/bin/ does not exist)"; \
		exit 1; \
	fi && \
	ln -sfvn "$$(realpath "$$REAL_VM")" "./run-$(NIX_HOST_NAME)-vm" && \
	echo "  Symlinked: ./nix/run-$(NIX_HOST_NAME)-vm -> $$(realpath "$$REAL_VM")" && \
	echo "  VM image ready: ./run-$(NIX_HOST_NAME)-vm"

## Build a QEMU VM image for NIX_HOST_NAME and launch it interactively.
##
## Requirements:
##   - nix must be installed natively (KVM devices cannot be passed into Docker)
##   - KVM kernel module loaded: modprobe kvm_amd (or kvm_intel)
##   - Port 2222 free on host (forwarded to VM SSH :22)
##
## Controls:
##   Ctrl-A X   quit QEMU
##   ssh -p 2222 kpango@localhost   SSH into the running VM
##
## Override host with: make nix/test/vm NIX_HOST_NAME=x1
nix/test/vm:
	@echo "==================================================="
	@echo " nix/test/vm — $(NIX_HOST_NAME)"
	@echo "==================================================="
	@. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true; \
	if ! command -v nix >/dev/null 2>&1; then \
		echo "Error: 'nix' must be installed natively to start VMs."; \
		echo "       KVM device nodes (/dev/kvm) cannot be exposed inside Docker."; \
		echo "       Run 'make nix/setup' first, then retry."; \
		exit 1; \
	fi; \
	if [ ! -c /dev/kvm ]; then \
		echo "Error: /dev/kvm not found. Load the KVM module first:"; \
		echo "       sudo modprobe kvm_amd   # for AMD CPUs"; \
		echo "       sudo modprobe kvm_intel  # for Intel CPUs"; \
		exit 1; \
	fi; \
	cd "$(ROOTDIR)/nix" && \
	echo "=> Building VM image..." && \
	nix build \
		".#nixosConfigurations.$(NIX_HOST_NAME).config.system.build.vm" \
		$(NIX_FLAGS) && \
	REAL_VM=$$(ls ./result/bin/run-*-vm 2>/dev/null | head -1) && \
	if [ -z "$$REAL_VM" ]; then \
		echo "Error: no run-*-vm binary found in ./result/bin/ after nix build"; \
		exit 1; \
	fi && \
	ln -sfvn "$$(realpath "$$REAL_VM")" "./run-$(NIX_HOST_NAME)-vm" && \
	echo "=> VM ready. SSH: ssh -p 2222 kpango@localhost  |  Quit: Ctrl-A X" && \
	QEMU_NET_OPTS="hostfwd=tcp::2222-:22" \
	QEMU_OPTS="-m 4096 -smp 4 -enable-kvm" \
	./run-$(NIX_HOST_NAME)-vm

## Default CI test gate: eval + eval/darwin + flake check + dry-run + dry-run/darwin.
## Override host with: make nix/test NIX_HOST_NAME=p1
nix/test: nix/test/eval nix/test/eval/darwin nix/test/check nix/test/dry-run nix/test/dry-run/darwin
	@echo ""
	@echo "==================================================="
	@echo " All nix tests passed for $(NIX_HOST_NAME)."
	@echo "==================================================="

# ─────────────────────────────────────────────────────────────────────────────
# nix/fmt — formatting
# ─────────────────────────────────────────────────────────────────────────────

## Check that all .nix files are formatted with nixfmt.
nix/fmt/check:
	@echo "=> Checking Nix file formatting..."
	@$(NIX_RUN) run $(NIX_FLAGS) nixpkgs#nixfmt-rfc-style -- --check "$(ROOTDIR)/nix"

## Auto-format all .nix files with nixfmt.
nix/fmt:
	@echo "=> Formatting Nix files..."
	@NIX_WRITABLE=1 $(NIX_RUN) run $(NIX_FLAGS) nixpkgs#nixfmt-rfc-style -- "$(ROOTDIR)/nix"
