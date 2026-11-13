GAME_DOCKER_IMAGE ?= kpango/steam-ac7:latest
GAME_DIR := $(ROOTDIR)/game

.PHONY: game/build game/run game/ac7 game/tune game/clean

## Build Steam & Proton gaming container image
game/build:
	@docker build -t $(GAME_DOCKER_IMAGE) $(GAME_DIR)

## Run Steam client in Docker container with GPU and Audio passthrough
game/run:
	@$(GAME_DIR)/scripts/run.sh

## Launch ACE COMBAT 7 (AppID 502500) directly inside Docker container
game/ac7:
	@$(GAME_DIR)/scripts/run.sh --ac7

## Apply performance tuning & HOTAS configuration to ACE COMBAT 7 Proton prefix
game/tune:
	@$(GAME_DIR)/scripts/ac7-tuning.sh

## Remove Steam gaming container instance if stopped
game/clean:
	@docker container rm -f steam-ac7 2>/dev/null || true
