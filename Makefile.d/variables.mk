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

FREE_MEM_MB := $(shell free -m 2>/dev/null | awk '/^Mem:/{print int($$7 * 0.8)}')
ifeq ($(FREE_MEM_MB),)
FREE_MEM_MB := 32768
endif

FREE_DISK_MB := $(shell df -m / 2>/dev/null | awk 'NR==2 {print int($$4 * 0.9)}')
ifeq ($(FREE_DISK_MB),)
FREE_DISK_MB := 32768
endif

DOCKER_BUILDX_KEEPSTORAGE ?= $(FREE_DISK_MB)

MEM_LIMIT_MB := $(shell awk -v mem=$(FREE_MEM_MB) -v disk=$(DOCKER_BUILDX_KEEPSTORAGE) 'BEGIN {print (mem > disk ? disk : mem)}')

DOCKER_MEMORY_LIMIT ?= $(MEM_LIMIT_MB)m

DOCKER_BUILDX_GC ?= false

ifeq ($(DOCKER_BUILDX_GC),true)
	BUILDKITD_FLAGS ?= "--oci-worker-gc=true --oci-worker-gc-keepstorage=$(DOCKER_BUILDX_KEEPSTORAGE) --oci-worker-snapshotter=stargz"
else
	BUILDKITD_FLAGS ?= "--oci-worker-gc=false --oci-worker-snapshotter=stargz"
endif

VERSION ?= nightly

ifneq ($(DOCKER_ARCH_SUFFIX),)
	DOCKER_TAG_VERSION = $(VERSION)-$(DOCKER_ARCH_SUFFIX)
else
	DOCKER_TAG_VERSION = $(VERSION)
endif

# NixOS configuration name to build/test.
# During Arch→NixOS transition the Arch hostname may differ from the NixOS config
# name, so we pick a sensible per-OS default and let the user override.
#   - Linux  → "tr"   (ThreadRipper desktop, the primary migration target)
#   - Darwin → "macbook-pro-m3"  (adjust if needed)
# Override per-invocation: make nix/test NIX_HOST_NAME=p1
NIX_HOST_NAME ?= $(if $(filter Darwin,$(shell uname -s)),macbook-pro-m3,tr)
