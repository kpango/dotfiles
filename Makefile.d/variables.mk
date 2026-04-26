ROOTDIR = $(eval ROOTDIR := $(shell git rev-parse --show-toplevel))$(ROOTDIR)
SYS_USER ?= $(shell whoami)
USER ?= $(SYS_USER)
USER_ID ?= $(shell id -u $(SYS_USER))
GROUP_ID ?= $(shell id -g $(SYS_USER))
GROUP_IDS ?= $(shell id -G $(SYS_USER))
GITHUB_ACCESS_TOKEN ?= $(eval GITHUB_ACCESS_TOKEN := $(shell pass github.api.ro.token))$(GITHUB_ACCESS_TOKEN)
GITHUB_SHA := $(eval GITHUB_SHA := $(shell git rev-parse HEAD))$(GITHUB_SHA)
GITHUB_URL := https://github.com/kpango/dotfiles
EMAIL := kpango@vdaas.org

DOCKER_EXTRA_OPTS ?=
DOCKER_ARCH_SUFFIX ?=
GHCR_USER ?= $(USER)
DOCKER_PUSH ?= true
DOCKER_BUILDER_NAME ?= "kpango-builder"
DOCKER_BUILDER_DRIVER ?= "docker-container"
DOCKER_BUILDER_PLATFORM ?= "linux/amd64,linux/arm64/v8"
DOCKER_CACHE_REPO ?= $(USER)/$(NAME):buildcache
DOCKER_BUILD_CACHE_DIR ?= $(HOME)/.docker/buildcache
DOCKER_MEMORY_LIMIT ?= 32G

VERSION ?= nightly

ifneq ($(DOCKER_ARCH_SUFFIX),)
	DOCKER_TAG_VERSION = $(VERSION)-$(DOCKER_ARCH_SUFFIX)
else
	DOCKER_TAG_VERSION = $(VERSION)
endif

NIX_HOST_NAME ?= macbook
