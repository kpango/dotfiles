ROOTDIR = $(eval ROOTDIR := $(or $(shell git rev-parse --show-toplevel 2>/dev/null),$(patsubst %/,%,$(dir $(abspath $(firstword $(MAKEFILE_LIST)))))))$(ROOTDIR)
UNAME_S := $(eval UNAME_S := $(or $(UNAME_S),$(shell uname -s)))$(UNAME_S)
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
# GitHub token: each consuming recipe (docker.mk/update.mk/git.mk) reads
# `${GITHUB_ACCESS_TOKEN:-$$(pass github.api.ro.token)}` at the shell level
# instead of a Make variable defined here. Two reasons combined:
#   1. A Make variable's value gets embedded as literal text into the recipe
#      line Make prints -- including under `make -n`, which would leak the
#      real token to stdout for any recipe that referenced it. A shell
#      command substitution deferred with `$$(...)` is never evaluated by
#      `-n` (no shell runs), so the token is only fetched when the recipe
#      actually executes.
#   2. CI (.github/actions/docker/action.yaml, update-actions.yaml) supplies
#      the token as `GITHUB_ACCESS_TOKEN` -- a Make command-line override or
#      an exported env var -- since GitHub-hosted runners have no `pass`/GPG.
#      Make auto-exports both forms to each recipe's shell environment
#      (verified empirically), so `${GITHUB_ACCESS_TOKEN:-...}` picks up
#      CI's value for free and only falls back to `pass` for local dev.
GITHUB_SHA := $(eval GITHUB_SHA := $(shell git rev-parse HEAD))$(GITHUB_SHA)
GITHUB_URL := https://github.com/kpango/dotfiles
EMAIL := kpango@vdaas.org

DOCKER_EXTRA_OPTS ?=
DOCKER_ARCH_SUFFIX ?=
GHCR_USER ?= $(USER)
DOCKER_PUSH ?= true
DOCKER_BUILDER_NAME ?= kpango-builder
DOCKER_BUILDER_DRIVER ?= docker-container
DOCKER_BUILDER_PLATFORM ?= linux/amd64,linux/arm64/v8
DOCKER_BUILD_CACHE_DIR ?= $(HOME)/.docker/buildcache

ifeq ($(UNAME_S),Darwin)
FREE_MEM_MB := $(eval FREE_MEM_MB := $(or $(FREE_MEM_MB),$(shell vm_stat 2>/dev/null | awk '/page size of/{ps=$$8} /^Pages free/{f=$$3} /^Pages inactive/{i=$$3} END{gsub(/\./,"",f); gsub(/\./,"",i); if (ps>0) print int((f+i)*ps/1048576*0.8)}'),32768))$(FREE_MEM_MB)
else
FREE_MEM_MB := $(eval FREE_MEM_MB := $(or $(FREE_MEM_MB),$(shell free -m 2>/dev/null | awk '/^Mem:/{print int($$7 * 0.8)}'),32768))$(FREE_MEM_MB)
endif

FREE_DISK_MB := $(eval FREE_DISK_MB := $(or $(FREE_DISK_MB),$(shell df -m / 2>/dev/null | awk 'NR==2 {print int($$4 * 0.9)}'),32768))$(FREE_DISK_MB)

DOCKER_BUILDX_KEEPSTORAGE ?= $(FREE_DISK_MB)

MEM_LIMIT_MB := $(eval MEM_LIMIT_MB := $(or $(MEM_LIMIT_MB),$(shell awk -v mem=$(FREE_MEM_MB) -v disk=$(DOCKER_BUILDX_KEEPSTORAGE) 'BEGIN {print (mem > disk ? disk : mem)}'),32768))$(MEM_LIMIT_MB)

DOCKER_MEMORY_LIMIT ?= $(MEM_LIMIT_MB)m

DOCKER_BUILDX_GC ?= false
DOCKER_CACHE_MODE ?= max
DOCKER_BUILDX_WORKERS ?= 8
DOCKER_ATTEST ?= 1
DOCKER_PROVENANCE ?= min
DOCKER_COMPRESSION_LEVEL ?= 3

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
    $(ROOTDIR)/Makefile.d/game.mk \
    $(ROOTDIR)/Makefile.d/bench.mk \
    $(ROOTDIR)/Makefile.d/help.mk \
    $(ROOTDIR)/Makefile.d/variables.mk
