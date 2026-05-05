.PHONY: build prod docker_build init_buildx create_buildx add_nodes remove_buildx do_build prod_build docker_merge do_merge profile login push pull

build: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx \
	build_base
	@xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) -f $(ROOTDIR)/Makefile build_{}" go docker rust dart k8s nim gcloud zig nix env vald
	@$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) build_tools

prod: \
	login \
	remove_buildx \
	init_buildx \
	create_buildx \
	build_base
	@xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=\"--no-cache\" -f $(ROOTDIR)/Makefile build_{}" go docker rust dart k8s nim gcloud zig nix env vald
	@$(MAKE) DOCKER_EXTRA_OPTS="--no-cache" build_tools
	@$(MAKE) DOCKER_EXTRA_OPTS="--no-cache" prod_build

docker_build:
	@$(eval TMP_DIR := $(shell mktemp -d))
	@$(file > $(TMP_DIR)/gat,$(GITHUB_ACCESS_TOKEN))
	@chmod 600 $(TMP_DIR)/gat
	DOCKER_BUILDKIT=1 docker buildx build \
		$(DOCKER_EXTRA_OPTS) \
		--builder "$(DOCKER_BUILDER_NAME)" \
		--platform "$(DOCKER_BUILDER_PLATFORM)" \
		--allow "network.host" \
		--attest type=sbom,generator=docker/buildkit-syft-scanner:edge \
		--build-arg BUILDKIT_MULTI_PLATFORM=1 \
		--build-arg EMAIL="$(EMAIL)" \
		--build-arg GROUP_ID="$(GROUP_ID)" \
		--build-arg GROUP_IDS="$(GROUP_IDS)" \
		--build-arg HOME="/home/$(USER)" \
		--build-arg USER="$(USER)" \
		--build-arg USER_ID="$(USER_ID)" \
		--build-arg WHOAMI="$(SYS_USER)" \
		--cache-from type=gha,scope=$(NAME)-$(DOCKER_TAG_VERSION) \
		--cache-from "ghcr.io/$(GHCR_USER)/$(NAME):$(DOCKER_TAG_VERSION)" \
		--cache-to type=gha,mode=max,scope=$(NAME)-$(DOCKER_TAG_VERSION) \
		--label org.opencontainers.image.revision="$(GITHUB_SHA)" \
		--label org.opencontainers.image.source="$(GITHUB_URL)" \
		--label org.opencontainers.image.title="$(USER)/$(NAME)" \
		--label org.opencontainers.image.url="$(GITHUB_URL)" \
		--label org.opencontainers.image.version="$(VERSION)" \
		--memory $(DOCKER_MEMORY_LIMIT) \
		--memory-swap $(DOCKER_MEMORY_LIMIT) \
		--network=host \
		--output type=registry,oci-mediatypes=true,compression=zstd,compression-level=5,force-compression=true,push=$(DOCKER_PUSH) \
		--provenance=mode=max \
		--secret id=gat,src="$(TMP_DIR)/gat" \
		-t "docker.io/$(USER)/$(NAME):$(DOCKER_TAG_VERSION)" \
		-t "ghcr.io/$(GHCR_USER)/$(NAME):$(DOCKER_TAG_VERSION)" \
		-f $(DOCKERFILE) $(ROOTDIR)
	@rm -rf $(TMP_DIR)

init_buildx:
	docker run \
		--network=host \
		--privileged \
		--rm tonistiigi/binfmt:master \
		--install $(DOCKER_BUILDER_PLATFORM)

create_buildx:
	docker buildx create --use \
		--name $(DOCKER_BUILDER_NAME) \
		--driver $(DOCKER_BUILDER_DRIVER) \
		--driver-opt=image=moby/buildkit:master \
		--driver-opt=network=host \
		--driver-opt=memory=$(DOCKER_MEMORY_LIMIT) \
		--buildkitd-flags=$(BUILDKITD_FLAGS) \
		--platform $(DOCKER_BUILDER_PLATFORM) \
		--bootstrap
	docker buildx ls
	docker buildx inspect --bootstrap $(DOCKER_BUILDER_NAME)

add_nodes:
	@echo $(DOCKER_BUILDER_PLATFORM) | tr ',' '\n' | while read platform; do \
		node_name=$$(echo $$platform | tr '/' '_' | tr -d '[:space:]'); \
		echo "Adding node to $(DOCKER_BUILDER_NAME) for $$platform as $$node_name..."; \
		docker buildx create --append --name $(DOCKER_BUILDER_NAME) --node $${DOCKER_BUILDER_NAME}-$$node_name --platform $$platform; \
	done

remove_buildx:
	docker buildx rm --force --all-inactive
	sudo rm -rf $$HOME/.docker/buildx
	docker buildx ls

do_build:
	@$(MAKE) DOCKERFILE="$(ROOTDIR)/dockers/$(NAME).Dockerfile" \
		NAME="$(NAME)" \
		DOCKER_BUILDER_NAME="$(DOCKER_BUILDER_NAME)" \
		DOCKER_BUILDER_PLATFORM="$(DOCKER_BUILDER_PLATFORM)" \
		DOCKER_MEMORY_LIMIT=$(DOCKER_MEMORY_LIMIT) \
		docker_build

build_%:
	@$(MAKE) NAME="$*" do_build

merge_%:
	@$(MAKE) NAME="$*" do_merge

docker_merge:
	docker buildx imagetools create -t "$(USER)/$(NAME):$(VERSION)" \
		"$(USER)/$(NAME):$(VERSION)-amd64" \
		"$(USER)/$(NAME):$(VERSION)-arm64"
	docker buildx imagetools create -t "ghcr.io/$(GHCR_USER)/$(NAME):$(VERSION)" \
		"ghcr.io/$(GHCR_USER)/$(NAME):$(VERSION)-amd64" \
		"ghcr.io/$(GHCR_USER)/$(NAME):$(VERSION)-arm64"

do_merge:
	@$(MAKE) NAME="$(NAME)" docker_merge

profile:
	rm -f analyze.txt
	type dlayer >/dev/null 2>&1 && docker save kpango/dev:$(VERSION) | dlayer >> analyze.txt

login:
	rm -rf $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/config.json $(HOME)/.docker/config.json
	docker login

push:
	docker push kpango/dev:$(VERSION)

pull:
	docker pull kpango/dev:$(VERSION)
