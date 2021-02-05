.PHONY: install

ROOTDIR = $(eval ROOTDIR := $(shell git rev-parse --show-toplevel))$(ROOTDIR)

DISK=/dev/mmcblk0

install:
	# rm -rf install.sh
	# curl -fsSLO https://raw.githubusercontent.com/rancher/k3os/master/install.sh
	sudo sh ./install.sh --config config.yaml $(DISK) https://github.com/rancher/k3os/releases/download/v0.19.5-rc.1/k3os-arm64.iso
	rm -rf install.sh
