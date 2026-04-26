# Makefile Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the root `Makefile` into smaller, domain-specific modules inside a `make/` directory.

**Architecture:** A centralized `make/` directory containing `.mk` files that represent logical domains (e.g., docker, arch, macos). The root `Makefile` includes these modules. Variables are loaded first.

**Tech Stack:** GNU Make, Bash.

---

### Task 1: Create Variables Module

**Files:**

- Create: `make/variables.mk`
- Modify: `Makefile`

- [ ] **Step 1: Create the directory and variables file**

```bash
mkdir -p make
```

Create `make/variables.mk` with the global variables:

```makefile
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
```

- [ ] **Step 2: Update the root Makefile**

Remove the variables section from the top of `Makefile` (lines ~3 to ~32 and line ~199 for NIX_HOST_NAME) and insert this right after the `.PHONY:` declaration:

```makefile
include make/variables.mk
```

- [ ] **Step 3: Verify the changes**

Run: `make echo`
Expected: Output should print the `ROOTDIR` correctly, proving variables are loaded.

- [ ] **Step 4: Commit**

```bash
git add make/variables.mk Makefile
git commit -m "refactor: extract variables to make/variables.mk"
```

---

### Task 2: Create Dotfiles Module

**Files:**

- Create: `make/dotfiles.mk`
- Modify: `Makefile`

- [ ] **Step 1: Create the dotfiles module**

Create `make/dotfiles.mk` with the targets:

```makefile
echo:
	@echo $(ROOTDIR)

all: prod_build login push profile git_push

run:
	source $(ROOTDIR)/alias && devrun

copy:
	mkdir -p $(HOME)/.config/ghostty
	mkdir -p $(HOME)/.config/helix/themes
	mkdir -p $(HOME)/.config/sheldon
	mkdir -p $(HOME)/.config/ghostty
	mkdir -p $(HOME)/.config/TabNine
	mkdir -p $(HOME)/.docker
	mkdir -p $(HOME)/.gemini/policies
	mkdir -p $(HOME)/.gnupg
	sudo mkdir -p /etc/docker
	cp $(ROOTDIR)/alias $(HOME)/.aliases
	cp $(ROOTDIR)/arch/ghostty.conf $(HOME)/.config/ghostty/config
	cp $(ROOTDIR)/dockers/config.json $(HOME)/.docker/config.json
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	cp $(ROOTDIR)/editorconfig $(HOME)/.editorconfig
	cp $(ROOTDIR)/gemini/settings.json $(HOME)/.gemini/settings.json
	cp $(ROOTDIR)/gemini/policies/policy.toml $(HOME)/.gemini/policies/policy.toml
	cp $(ROOTDIR)/ghostty.conf $(HOME)/.config/ghostty/config
	cp $(ROOTDIR)/gitattributes $(HOME)/.gitattributes
	cp $(ROOTDIR)/gitconfig $(HOME)/.gitconfig
	cp $(ROOTDIR)/gitignore $(HOME)/.gitignore
	cp $(ROOTDIR)/gpg-agent.conf $(HOME)/.gnupg/gpg-agent.conf
	cp $(ROOTDIR)/helix/config.toml $(HOME)/.config/helix/config.toml
	cp $(ROOTDIR)/helix/languages.toml $(HOME)/.config/helix/languages.toml
	cp $(ROOTDIR)/helix/themes/zed_kpango.toml $(HOME)/.config/helix/themes/zed_kpango.toml
	cp $(ROOTDIR)/sheldon.toml $(HOME)/.config/sheldon/plugins.toml
	cp $(ROOTDIR)/starship.toml $(HOME)/.config/starship.toml
	cp $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	cp $(ROOTDIR)/tmux-kube $(HOME)/.tmux-kube
	cp $(ROOTDIR)/tmux.new-session $(HOME)/.tmux.new-session
	cp $(ROOTDIR)/zshrc $(HOME)/.zshrc
	sudo cp $(ROOTDIR)/dockers/config.json /etc/docker/config.json
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json

link:
	mkdir -p $(HOME)/.config/ghostty
	mkdir -p $(HOME)/.config/helix/themes
	mkdir -p $(HOME)/.config/sheldon
	mkdir -p $(HOME)/.config/ghostty
	mkdir -p $(HOME)/.config/TabNine
	mkdir -p $(HOME)/.docker
	mkdir -p $(HOME)/.gemini/policies
	mkdir -p $(HOME)/.gnupg
	ln -sfv $(ROOTDIR)/alias $(HOME)/.aliases
	ln -sfv $(ROOTDIR)/arch/ghostty.conf $(HOME)/.config/ghostty/config
	ln -sfv $(ROOTDIR)/dockers/config.json $(HOME)/.docker/config.json
	ln -sfv $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	ln -sfv $(ROOTDIR)/editorconfig $(HOME)/.editorconfig
	ln -sfv $(ROOTDIR)/gemini/settings.json $(HOME)/.gemini/settings.json
	ln -sfv $(ROOTDIR)/gemini/policies/policy.toml $(HOME)/.gemini/policies/policy.toml
	ln -sfv $(ROOTDIR)/ghostty.conf $(HOME)/.config/ghostty/config
	ln -sfv $(ROOTDIR)/gitattributes $(HOME)/.gitattributes
	ln -sfv $(ROOTDIR)/gitconfig $(HOME)/.gitconfig
	ln -sfv $(ROOTDIR)/gitignore $(HOME)/.gitignore
	ln -sfv $(ROOTDIR)/gpg-agent.conf $(HOME)/.gnupg/gpg-agent.conf
	ln -sfv $(ROOTDIR)/helix/config.toml $(HOME)/.config/helix/config.toml
	ln -sfv $(ROOTDIR)/helix/languages.toml $(HOME)/.config/helix/languages.toml
	ln -sfv $(ROOTDIR)/helix/themes/zed_kpango.toml $(HOME)/.config/helix/themes/zed_kpango.toml
	ln -sfv $(ROOTDIR)/sheldon.toml $(HOME)/.config/sheldon/plugins.toml
	ln -sfv $(ROOTDIR)/starship.toml $(HOME)/.config/starship.toml
	ln -sfv $(ROOTDIR)/tmux.conf $(HOME)/.tmux.conf
	ln -sfv $(ROOTDIR)/tmux-kube $(HOME)/.tmux-kube
	ln -sfv $(ROOTDIR)/tmux.new-session $(HOME)/.tmux.new-session
	ln -sfv $(ROOTDIR)/zshrc $(HOME)/.zshrc
	sudo mkdir -p /etc/docker
	sudo ln -sfv $(ROOTDIR)/dockers/config.json /etc/docker/config.json
	sudo ln -sfv $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json

clean: perm
	$(eval TMP_DIR := $(shell mktemp -d))
	jq . $(ROOTDIR)/arch/waybar.json > $(TMP_DIR)/waybar.json.tmp && mv $(TMP_DIR)/waybar.json.tmp $(ROOTDIR)/arch/waybar.json
	sudo rm -rf \
		$(HOME)/.aliases \
		$(HOME)/.config/compton \
		$(HOME)/.config/fcitx5/conf/classicui.conf \
		$(HOME)/.config/fcitx5/config \
		$(HOME)/.config/fcitx5/profile \
		$(HOME)/.config/ghostty \
		$(HOME)/.config/helix \
		$(HOME)/.config/i3 \
		$(HOME)/.config/i3status \
		$(HOME)/.config/nvim \
		$(HOME)/.config/ranger \
		$(HOME)/.config/sheldon \
		$(HOME)/.config/starship.toml \
		$(HOME)/.config/sway \
		$(HOME)/.config/waybar \
		$(HOME)/.config/wofi \
		$(HOME)/.config/workstyle \
		$(HOME)/.docker/config.json \
		$(HOME)/.docker/daemon.json \
		$(HOME)/.editorconfig \
		$(HOME)/.gemini/settings.json \
		$(HOME)/.gemini/policies/policy.toml \
		$(HOME)/.gitattributes \
		$(HOME)/.gitconfig \
		$(HOME)/.gitignore \
		$(HOME)/.gnupg/gpg-agent.conf \
		$(HOME)/Library/LaunchAgents/localhost.homebrew-autoupdate.plist \
		$(HOME)/Library/LaunchAgents/ulimit.plist \
		$(HOME)/.tmux.conf \
		$(HOME)/.tmux-kube \
		$(HOME)/.tmux.new-session \
		$(HOME)/.Xdefaults \
		$(HOME)/.xinitrc \
		$(HOME)/.Xmodmap \
		$(HOME)/.zshrc \
		/etc/chrony.conf \
		/etc/dbus-1/system.d/pulseaudio-bluetooth.conf \
		/etc/default/tlp \
		/etc/docker/config.json \
		/etc/docker/daemon.json \
		/etc/environment \
		/etc/lightdm \
		/etc/makepkg.conf \
		/etc/modprobe.d/bbswitch.conf \
		/etc/modprobe.d/nvidia-tweaks.conf \
		/etc/modprobe.d/thinkfan.conf \
		/etc/modules-load.d/bbr.conf \
		/etc/modules-load.d/nvidia-uvm.conf \
		/etc/NetworkManager/dispatcher.d/nmcli-bond-auto-connect.sh \
		/etc/NetworkManager/dispatcher.d/nmcli-wifi-eth-autodetect.sh \
		/etc/NetworkManager/dnsmasq.d/dnsmasq.conf \
		/etc/NetworkManager/NetworkManager.conf \
		/etc/pacman.conf \
		/etc/profile.d/fcitx.sh \
		/etc/profile.d/sway.sh \
		/etc/pulse/default.pa \
		/etc/resolv.dnsmasq.conf \
		/etc/resolv.pre-tailscale-backup.conf \
		/etc/sudoers.d/$(SYS_USER) \
		/etc/sysctl.conf \
		/etc/sysctl.d/99-sysctl.conf \
		/etc/systemd/system/NetworkManager-dispatcher.service \
		/etc/systemd/system/nvidia-disable-resume.service \
		/etc/systemd/system/nvidia-enable-power-off.service \
		/etc/systemd/system/pulseaudio.service \
		/etc/tlp.conf \
		/etc/udev/rules.d/60-ioschedulers.rules \
		/etc/udev/rules.d/60-nvidia.rules \
		/usr/share/applications/com.mitchellh.ghostty.desktop

zsh: link
	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc

bash: link
	[ -f $(HOME)/.bashrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.bashrc

perm:
	sudo chmod -R 755 $(ROOTDIR)/*
	sudo chmod -R 755 $(ROOTDIR)/.*
	sudo chown -R $(SYS_USER):$(GROUP_ID) $(ROOTDIR)/*
	sudo chown -R $(SYS_USER):$(GROUP_ID) $(ROOTDIR)/.*
	sudo chmod -R 644 $(ROOTDIR)/gpg-agent.conf
	sudo chmod -R 644 $(ROOTDIR)/arch/waybar.json
	\find $(ROOTDIR) -type d -name '.git' -prune -o -type f -not -name 'tmux.conf' -exec nkf -Lu -w --overwrite {} \;
```

- [ ] **Step 2: Update Makefile**

Remove these targets from `Makefile` and add `include make/dotfiles.mk` below `include make/variables.mk`.

- [ ] **Step 3: Verify**

Run: `make --dry-run zsh`
Expected: Output showing the link and zsh commands.

- [ ] **Step 4: Commit**

```bash
git add make/dotfiles.mk Makefile
git commit -m "refactor: extract dotfiles targets to make/dotfiles.mk"
```

---

### Task 3: Create Docker Module

**Files:**

- Create: `make/docker.mk`
- Modify: `Makefile`

- [ ] **Step 1: Create docker.mk**

Create `make/docker.mk` containing `build`, `prod`, `docker_build`, `init_buildx`, `create_buildx`, `add_nodes`, `remove_buildx`, `do_build`, `prod_build`, `build_%`, `merge_%`, `docker_merge`, `do_merge`, `profile`, `login`, `push`, `pull`. (Copy these verbatim from the original Makefile).

- [ ] **Step 2: Update Makefile**

Remove these targets from `Makefile` and add `include make/docker.mk`.

- [ ] **Step 3: Verify**

Run: `make --dry-run build`
Expected: Output showing the make calls for go, docker, rust, etc.

- [ ] **Step 4: Commit**

```bash
git add make/docker.mk Makefile
git commit -m "refactor: extract docker targets to make/docker.mk"
```

---

### Task 4: Create Arch Module

**Files:**

- Create: `make/arch.mk`
- Modify: `Makefile`

- [ ] **Step 1: Create arch.mk**

Create `make/arch.mk` containing `arch_link`, `arch_p1_link`, `arch_desk_link` verbatim from the original Makefile.

- [ ] **Step 2: Update Makefile**

Remove these targets from `Makefile` and add `include make/arch.mk`.

- [ ] **Step 3: Verify**

Run: `make --dry-run arch_link`

- [ ] **Step 4: Commit**

```bash
git add make/arch.mk Makefile
git commit -m "refactor: extract Arch targets to make/arch.mk"
```

---

### Task 5: Create macOS Module

**Files:**

- Create: `make/macos.mk`
- Modify: `Makefile`

- [ ] **Step 1: Create macos.mk**

Create `make/macos.mk` containing the `mac_link` target.

- [ ] **Step 2: Update Makefile**

Remove this target from `Makefile` and add `include make/macos.mk`.

- [ ] **Step 3: Verify**

Run: `make --dry-run mac_link`

- [ ] **Step 4: Commit**

```bash
git add make/macos.mk Makefile
git commit -m "refactor: extract macOS targets to make/macos.mk"
```

---

### Task 6: Create Nix Module

**Files:**

- Create: `make/nix.mk`
- Modify: `Makefile`

- [ ] **Step 1: Create nix.mk**

Create `make/nix.mk` containing the `nix/setup` target. Note: the `NIX_HOST_NAME` variable was already moved to `make/variables.mk`.

- [ ] **Step 2: Update Makefile**

Remove this target from `Makefile` and add `include make/nix.mk`.

- [ ] **Step 3: Verify**

Run: `make --dry-run nix/setup`

- [ ] **Step 4: Commit**

```bash
git add make/nix.mk Makefile
git commit -m "refactor: extract Nix targets to make/nix.mk"
```

---

### Task 7: Create Git Module

**Files:**

- Create: `make/git.mk`
- Modify: `Makefile`

- [ ] **Step 1: Create git.mk**

Create `make/git.mk` containing `github_check` and `git_push`.

- [ ] **Step 2: Update Makefile**

Remove these targets from `Makefile` and add `include make/git.mk`.

- [ ] **Step 3: Verify**

Run: `make --dry-run github_check`

- [ ] **Step 4: Commit**

```bash
git add make/git.mk Makefile
git commit -m "refactor: extract Git targets to make/git.mk"
```

---

### Task 8: Cleanup Root Makefile

**Files:**

- Modify: `Makefile`

- [ ] **Step 1: Finalize Makefile**

The `Makefile` should now just look like this:

```makefile
.PHONY: all link zsh bash build prod_build profile run push pull

include make/variables.mk
include make/dotfiles.mk
include make/docker.mk
include make/arch.mk
include make/macos.mk
include make/nix.mk
include make/git.mk
```

- [ ] **Step 2: Verify everything**

Run: `make --dry-run all`
Expected: It should parse successfully.

- [ ] **Step 3: Final Commit**

```bash
git add Makefile
git commit -m "refactor: finalize modular Makefile structure"
```
