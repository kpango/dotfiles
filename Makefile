include Makefile.d/variables.mk
include Makefile.d/install.mk
include Makefile.d/docker.mk
include Makefile.d/nix.mk
include Makefile.d/git.mk
include Makefile.d/devbox.mk
include Makefile.d/format.mk
include Makefile.d/update.mk
include Makefile.d/lint.mk
include Makefile.d/bench.mk
include Makefile.d/help.mk

.DEFAULT_GOAL := help

.PHONY: help all

all: docker/build/dev docker/login docker/push docker/profile git/push
