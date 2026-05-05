include Makefile.d/variables.mk
include Makefile.d/dotfiles.mk
include Makefile.d/docker.mk
include Makefile.d/arch.mk
include Makefile.d/macos.mk
include Makefile.d/nix.mk
include Makefile.d/git.mk
include Makefile.d/devbox.mk
include Makefile.d/format.mk
include Makefile.d/update.mk

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@printf "\nUsage: make <target> [VAR=value ...]\n\n"
	@printf "Key variables:\n"
	@printf "  NIX_HOST_NAME   NixOS host to build/test (default: tr)\n"
	@printf "  NIX_TEST_HOSTS  Space-separated list of hosts for nix/test/eval\n"
	@printf "  NIX_DOCKER_IMAGE  Container image used when nix is not installed\n\n"
	@printf "Nix targets:\n"
	@grep -E '^## ' $(ROOTDIR)/Makefile.d/nix.mk | sed 's/^## /  /'
	@printf "\n"
