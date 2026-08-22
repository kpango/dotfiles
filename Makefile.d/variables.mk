ROOTDIR = $(eval ROOTDIR := $(or $(shell git rev-parse --show-toplevel 2>/dev/null),$(patsubst %/,%,$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))))$(ROOTDIR)
UNAME_S := $(shell uname -s)
# GNU sed (-i with no attached suffix = no backup) vs BSD/macOS sed (-i requires
# a mandatory suffix argument; '' means no backup). Detect by actual sed binary
# behavior, not $(UNAME_S) -- a GNU sed can shadow the BSD sed on macOS PATH
# (e.g. nix-darwin, Homebrew coreutils/gnu-sed), which would otherwise make
# "sed -i ''" pass the empty string as the script and treat the real script as
# a filename ("sed: can't read s/.../.../g: No such file or directory"). Use
# $(SED_INPLACE) instead of a bare "sed -i" anywhere a recipe edits a file in place.
ifeq ($(shell sed --version 2>/dev/null | grep -q 'GNU sed' && echo GNU),GNU)
SED_INPLACE := sed -i
else
SED_INPLACE := sed -i ''
endif
# root's home directory: macOS keeps it at /var/root, not /root.
ifeq ($(UNAME_S),Darwin)
ROOT_HOME := /var/root
else
ROOT_HOME := /root
endif
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

ifeq ($(UNAME_S),Darwin)
# vm_stat has no direct "available" figure like Linux's free(1); approximate
# it the same way Activity Monitor does (free + inactive pages are the ones
# reclaimable without swapping).
FREE_MEM_MB := $(shell vm_stat 2>/dev/null | awk '/page size of/{ps=$$8} /^Pages free/{f=$$3} /^Pages inactive/{i=$$3} END{gsub(/\./,"",f); gsub(/\./,"",i); if (ps>0) print int((f+i)*ps/1048576*0.8)}')
else
FREE_MEM_MB := $(shell free -m 2>/dev/null | awk '/^Mem:/{print int($$7 * 0.8)}')
endif
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
DOCKER_CACHE_MODE ?= max
DOCKER_BUILDX_WORKERS ?= 8
DOCKER_ATTEST ?= 1
DOCKER_PROVENANCE ?= max
DOCKER_COMPRESSION_LEVEL ?= 5

ifeq ($(DOCKER_ATTEST),1)
_ATTEST_FLAG := --attest type=sbom,generator=docker/buildkit-syft-scanner:edge
else
_ATTEST_FLAG :=
endif

ifeq ($(DOCKER_BUILDX_GC),true)
	BUILDKITD_FLAGS ?= "--oci-worker-gc=true --oci-worker-gc-keepstorage=$(DOCKER_BUILDX_KEEPSTORAGE) --oci-worker-snapshotter=stargz --oci-max-parallelism=$(DOCKER_BUILDX_WORKERS)"
else
	BUILDKITD_FLAGS ?= "--oci-worker-gc=false --oci-worker-snapshotter=stargz --oci-max-parallelism=$(DOCKER_BUILDX_WORKERS)"
endif

VERSION ?= nightly

ifneq ($(DOCKER_ARCH_SUFFIX),)
	DOCKER_TAG_VERSION = $(VERSION)-$(DOCKER_ARCH_SUFFIX)
else
	DOCKER_TAG_VERSION = $(VERSION)
endif

MAKELISTS := \
    $(ROOTDIR)/Makefile.d/install.mk \
    $(ROOTDIR)/Makefile.d/docker.mk \
    $(ROOTDIR)/Makefile.d/git.mk \
    $(ROOTDIR)/Makefile.d/nix.mk \
    $(ROOTDIR)/Makefile.d/format.mk \
    $(ROOTDIR)/Makefile.d/update.mk \
    $(ROOTDIR)/Makefile.d/lint.mk \
    $(ROOTDIR)/Makefile.d/devbox.mk \
    $(ROOTDIR)/Makefile.d/bench.mk \
    $(ROOTDIR)/Makefile.d/help.mk \
    $(ROOTDIR)/Makefile.d/variables.mk
