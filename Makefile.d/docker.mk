.PHONY: docker/build docker/build/prod docker/build/image docker/build/dev \
        docker/builder/init docker/builder/create docker/builder/remove docker/builder/add-nodes \
        docker/merge docker/login docker/push docker/pull docker/profile \
        build prod login push pull prod_build init_buildx create_buildx remove_buildx docker_build profile

define DOCKER_BUILD_PARALLEL
	@if command -v xpanes >/dev/null 2>&1; then \
		xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=\"$(1)\" -f $(ROOTDIR)/Makefile docker/build/{}" go docker rust dart k8s nim gcloud zig nix env vald; \
	else \
		for img in go docker rust dart k8s nim gcloud zig nix env vald; do \
			$(MAKE) DOCKER_EXTRA_OPTS=\"$(1)\" -f $(ROOTDIR)/Makefile docker/build/$$img & \
		done; wait; \
	fi
endef

## build all docker images in parallel (login → builder reset → base → images)
docker/build: \
	docker/login \
	docker/builder/remove \
	docker/builder/init \
	docker/builder/create \
	docker/build/base
	$(call DOCKER_BUILD_PARALLEL,$(DOCKER_EXTRA_OPTS))
	@$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) docker/build/tools

## build all production images with --no-cache
docker/build/prod: \
	docker/login \
	docker/builder/remove \
	docker/builder/init \
	docker/builder/create \
	docker/build/base
	$(call DOCKER_BUILD_PARALLEL,--no-cache)
	@$(MAKE) DOCKER_EXTRA_OPTS="--no-cache" docker/build/tools
	@$(MAKE) DOCKER_EXTRA_OPTS="--no-cache" docker/build/dev

## generic buildx build helper (called by docker/build/% and docker/build/dev)
docker/build/image:
	@$(eval TMP_DIR := $(shell mktemp -d))
	@$(file > $(TMP_DIR)/gat,$(GITHUB_ACCESS_TOKEN))
	@chmod 600 $(TMP_DIR)/gat
	DOCKER_BUILDKIT=1 docker buildx build \
		$(DOCKER_EXTRA_OPTS) \
		--builder "$(DOCKER_BUILDER_NAME)" \
		--platform "$(DOCKER_BUILDER_PLATFORM)" \
		--allow "network.host" \
		$(_ATTEST_FLAG) \
		--build-arg BUILDKIT_MULTI_PLATFORM=1 \
		--build-arg EMAIL="$(EMAIL)" \
		--build-arg GROUP_ID="$(GROUP_ID)" \
		--build-arg GROUP_IDS="$(GROUP_IDS)" \
		--build-arg HOME="/home/$(USER)" \
		--build-arg USER="$(USER)" \
		--build-arg USER_ID="$(USER_ID)" \
		--build-arg WHOAMI="$(SYS_USER)" \
		--cache-from type=gha,scope=$(NAME)-$(DOCKER_TAG_VERSION) \
		--cache-from type=registry,ref=ghcr.io/$(GHCR_USER)/$(NAME):$(DOCKER_TAG_VERSION)-cache \
		--cache-from "ghcr.io/$(GHCR_USER)/$(NAME):$(DOCKER_TAG_VERSION)" \
		--cache-to type=gha,mode=$(DOCKER_CACHE_MODE),scope=$(NAME)-$(DOCKER_TAG_VERSION) \
		--cache-to type=registry,ref=ghcr.io/$(GHCR_USER)/$(NAME):$(DOCKER_TAG_VERSION)-cache,mode=$(DOCKER_CACHE_MODE) \
		--label org.opencontainers.image.revision="$(GITHUB_SHA)" \
		--label org.opencontainers.image.source="$(GITHUB_URL)" \
		--label org.opencontainers.image.title="$(USER)/$(NAME)" \
		--label org.opencontainers.image.url="$(GITHUB_URL)" \
		--label org.opencontainers.image.version="$(VERSION)" \
		--memory $(DOCKER_MEMORY_LIMIT) \
		--memory-swap -1 \
		--network=host \
		--output type=registry,oci-mediatypes=true,compression=zstd,compression-level=$(DOCKER_COMPRESSION_LEVEL),force-compression=true,push=$(DOCKER_PUSH) \
		--provenance=mode=$(DOCKER_PROVENANCE) \
		--secret id=gat,src="$(TMP_DIR)/gat" \
		-t "docker.io/$(USER)/$(NAME):$(DOCKER_TAG_VERSION)" \
		-t "ghcr.io/$(GHCR_USER)/$(NAME):$(DOCKER_TAG_VERSION)" \
		-f $(DOCKERFILE) $(ROOTDIR)
	@rm -rf $(TMP_DIR)

## build contexts for dev: 9 source images provided as external registry references.
## BuildKit resolves only the layers needed for each COPY --link, reducing peak disk use.
_DEV_CTXS = \
	--build-context dart=docker-image://docker.io/$(USER)/dart:$(VERSION) \
	--build-context docker=docker-image://docker.io/$(USER)/docker:$(VERSION) \
	--build-context gcloud=docker-image://docker.io/$(USER)/gcloud:$(VERSION) \
	--build-context go=docker-image://docker.io/$(USER)/go:$(VERSION) \
	--build-context kube=docker-image://docker.io/$(USER)/k8s:$(VERSION) \
	--build-context nim=docker-image://docker.io/$(USER)/nim:$(VERSION) \
	--build-context nix=docker-image://docker.io/$(USER)/nix:$(VERSION) \
	--build-context rust=docker-image://docker.io/$(USER)/rust:$(VERSION) \
	--build-context zig=docker-image://docker.io/$(USER)/zig:$(VERSION)

## build the dev image with --no-cache and external build contexts for source images
docker/build/dev:
	@$(MAKE) NAME=dev \
		DOCKERFILE="$(ROOTDIR)/dockers/dev.Dockerfile" \
		DOCKER_EXTRA_OPTS="--no-cache $(_DEV_CTXS)" \
		docker/build/image

## build a single docker image (dockers/%.Dockerfile)
docker/build/%:
	@$(MAKE) NAME="$*" \
		DOCKERFILE="$(ROOTDIR)/dockers/$*.Dockerfile" \
		DOCKER_BUILDER_NAME="$(DOCKER_BUILDER_NAME)" \
		DOCKER_BUILDER_PLATFORM="$(DOCKER_BUILDER_PLATFORM)" \
		DOCKER_MEMORY_LIMIT=$(DOCKER_MEMORY_LIMIT) \
		docker/build/image

## install binfmt emulators required for multi-platform (amd64 + arm64) builds
docker/builder/init:
	docker run \
		--network=host \
		--privileged \
		--rm tonistiigi/binfmt:master \
		--install $(DOCKER_BUILDER_PLATFORM)

## create and bootstrap the buildx builder instance
docker/builder/create:
	docker buildx create --use \
		--name $(DOCKER_BUILDER_NAME) \
		--driver $(DOCKER_BUILDER_DRIVER) \
		--driver-opt=image=moby/buildkit:master \
		--driver-opt=network=host \
		--driver-opt=memory=$(DOCKER_MEMORY_LIMIT) \
		--driver-opt=memory-swap=-1 \
		--buildkitd-flags=$(BUILDKITD_FLAGS) \
		--platform $(DOCKER_BUILDER_PLATFORM) \
		--bootstrap
	docker buildx ls
	docker buildx inspect --bootstrap $(DOCKER_BUILDER_NAME)

## append platform-specific nodes to the existing buildx builder
docker/builder/add-nodes:
	@echo $(DOCKER_BUILDER_PLATFORM) | tr ',' '\n' | while read platform; do \
		node_name=$$(echo $$platform | tr '/' '_' | tr -d '[:space:]'); \
		echo "Adding node to $(DOCKER_BUILDER_NAME) for $$platform as $$node_name..."; \
		docker buildx create --append --name $(DOCKER_BUILDER_NAME) --node $${DOCKER_BUILDER_NAME}-$$node_name --platform $$platform; \
	done

## force-remove all inactive buildx builders and wipe local buildx state
docker/builder/remove:
	docker buildx rm --force --all-inactive
	sudo rm -rf $$HOME/.docker/buildx
	docker buildx ls

## merge amd64 and arm64 single-arch images into a multi-arch manifest for NAME
docker/merge:
	docker buildx imagetools create -t "$(USER)/$(NAME):$(VERSION)" \
		"$(USER)/$(NAME):$(VERSION)-amd64" \
		"$(USER)/$(NAME):$(VERSION)-arm64"
	docker buildx imagetools create -t "ghcr.io/$(GHCR_USER)/$(NAME):$(VERSION)" \
		"ghcr.io/$(GHCR_USER)/$(NAME):$(VERSION)-amd64" \
		"ghcr.io/$(GHCR_USER)/$(NAME):$(VERSION)-arm64"

## merge multi-arch manifests for a single named image
docker/merge/%:
	@$(MAKE) NAME="$*" docker/merge

## install docker config.json and run docker login
docker/login:
	rm -rf $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/config.json $(HOME)/.docker/config.json
	docker login

## push the dev image to Docker Hub and GHCR
docker/push:
	docker push kpango/dev:$(VERSION)

## pull the dev image from the registry
docker/pull:
	docker pull kpango/dev:$(VERSION)

## analyse image layers with dlayer and write analyze.txt
docker/profile:
	rm -f analyze.txt
	type dlayer >/dev/null 2>&1 && docker save kpango/dev:$(VERSION) | dlayer >> analyze.txt

# ── Backward-compat aliases ───────────────────────────────────────────────────

build:         ; @$(MAKE) docker/build
prod:          ; @$(MAKE) docker/build/prod
login:         ; @$(MAKE) docker/login
push:          ; @$(MAKE) docker/push
pull:          ; @$(MAKE) docker/pull
prod_build:    ; @$(MAKE) docker/build/dev
init_buildx:   ; @$(MAKE) docker/builder/init
create_buildx: ; @$(MAKE) docker/builder/create
remove_buildx: ; @$(MAKE) docker/builder/remove
docker_build:  ; @$(MAKE) docker/build/image
profile:       ; @$(MAKE) docker/profile
