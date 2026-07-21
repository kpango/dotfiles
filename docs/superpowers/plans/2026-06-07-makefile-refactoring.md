# Makefile Refactoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the Makefile `link`, `copy`, and `clean` logic using macro functions to adhere to SOLID principles.

**Architecture:** We extract the repetitive inline bash conditionals evaluating `MODE` into `DEPLOY_FUNC` and `CLEAN_FUNC` macros. These macros are then invoked inside deployment targets, and the `clean` targets are refactored to iterate over the existing maps instead of a static `CLEAN_FILES` array.

**Tech Stack:** Makefile, Bash

---

### Task 1: Define Reusable Macros

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Write the failing test**
      Run: `grep "DEPLOY_FUNC" Makefile.d/install.mk || echo "Missing"`
      Expected: Missing

- [ ] **Step 2: Write minimal implementation**
      Open `Makefile.d/install.mk` and insert the macro definitions near the top, just below the `MODE ?= link` declaration.

```makefile
define DEPLOY_FUNC
	[ -z "$(1)" ] || { \
		$(3) mkdir -p "$$(dirname "$(2)")"; \
		$(if $(filter copy,$(MODE)), \
			$(3) rm -rf "$(2)" && $(3) cp -r "$(1)" "$(2)", \
			$(3) ln -sfvn "$(1)" "$(2)" \
		); \
	}
endef

define CLEAN_FUNC
	[ -z "$(1)" ] || $(2) rm -rf "$(1)"
endef
```

- [ ] **Step 3: Run test to verify it passes**
      Run: `grep "DEPLOY_FUNC" Makefile.d/install.mk`
      Expected: Output showing the macro definition.

- [ ] **Step 4: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "refactor(install): define DEPLOY_FUNC and CLEAN_FUNC macros"
```

---

### Task 2: Refactor dotfiles/install loops and direct calls

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Write the minimal implementation**
      In `Makefile.d/install.mk`, locate the `dotfiles/install:` target. Replace the loop and direct calls to use `DEPLOY_FUNC`.

Change:

```makefile
dotfiles/install:
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		mkdir -p "$$(dirname "$(HOME)/$$dest")"; \
		$(if $(filter copy,$(MODE)),rm -rf "$(HOME)/$$dest" && cp -r "$(ROOTDIR)/$$src" "$(HOME)/$$dest",ln -sfvn "$(ROOTDIR)/$$src" "$(HOME)/$$dest"); \
	done
	sudo mkdir -p /etc/docker
	$(if $(filter copy,$(MODE)),sudo rm -f "/etc/docker/config.json" && sudo cp "$(ROOTDIR)/dockers/config.json" "/etc/docker/config.json",sudo ln -sfvn "$(ROOTDIR)/dockers/config.json" "/etc/docker/config.json")
	$(if $(filter copy,$(MODE)),sudo rm -f "/etc/docker/daemon.json" && sudo cp "$(ROOTDIR)/dockers/daemon.json" "/etc/docker/daemon.json",sudo ln -sfvn "$(ROOTDIR)/dockers/daemon.json" "/etc/docker/daemon.json")
	sudo mkdir -p /etc/containerd
	$(if $(filter copy,$(MODE)),sudo rm -f "/etc/containerd/config.toml" && sudo cp "$(ROOTDIR)/arch/containerd.toml" "/etc/containerd/config.toml",sudo ln -sfvn "$(ROOTDIR)/arch/containerd.toml" "/etc/containerd/config.toml")
```

To:

```makefile
dotfiles/install:
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); \
	done
	@$(call DEPLOY_FUNC,$(ROOTDIR)/dockers/config.json,/etc/docker/config.json,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/dockers/daemon.json,/etc/docker/daemon.json,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/containerd.toml,/etc/containerd/config.toml,sudo)
```

- [ ] **Step 2: Run test to verify it passes**
      Run: `make dotfiles/install MODE=link ROOTDIR=$(pwd)`
      Expected: Execution finishes cleanly without syntax errors, creating links.

- [ ] **Step 3: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "refactor(install): use DEPLOY_FUNC in dotfiles/install target"
```

---

### Task 3: Refactor arch/install loops and direct calls

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Write the minimal implementation**
      In `Makefile.d/install.mk`, locate the `arch/install:` target.

Change:

```makefile
arch/install: dotfiles/install
	$(ARCH_PREP)
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		$(if $(filter copy,$(MODE)),cp -r "$(ROOTDIR)/$$src" "$(HOME)/$$dest",ln -sfvn "$(ROOTDIR)/$$src" "$(HOME)/$$dest"); \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		$(if $(filter copy,$(MODE)),sudo cp "$(ROOTDIR)/$$src" "$$dest",sudo ln -sfvn "$(ROOTDIR)/$$src" "$$dest"); \
	done
	$(ARCH_POST)
```

To:

```makefile
arch/install: dotfiles/install
	$(ARCH_PREP)
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo cp "$(ROOTDIR)/$$src" "$$dest"; \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$$dest,sudo); \
	done
	$(ARCH_POST)
```

And locate `NVIDIA_INSTALL` block.
Change:

```makefile
define NVIDIA_INSTALL
	$(if $(filter copy,$(MODE)),sudo cp "$(ROOTDIR)/nvidia/nvidia-tweaks.conf" "/etc/modprobe.d/nvidia-tweaks.conf",sudo ln -sfvn "$(ROOTDIR)/nvidia/nvidia-tweaks.conf" "/etc/modprobe.d/nvidia-tweaks.conf")
	$(if $(filter copy,$(MODE)),sudo cp "$(ROOTDIR)/nvidia/nvidia-uvm.conf" "/etc/modules-load.d/nvidia-uvm.conf",sudo ln -sfvn "$(ROOTDIR)/nvidia/nvidia-uvm.conf" "/etc/modules-load.d/nvidia-uvm.conf")
	$(if $(filter copy,$(MODE)),sudo cp "$(ROOTDIR)/nvidia/60-nvidia.rules" "/etc/udev/rules.d/60-nvidia.rules",sudo ln -sfvn "$(ROOTDIR)/nvidia/60-nvidia.rules" "/etc/udev/rules.d/60-nvidia.rules")
endef
```

To:

```makefile
define NVIDIA_INSTALL
	@$(call DEPLOY_FUNC,$(ROOTDIR)/nvidia/nvidia-tweaks.conf,/etc/modprobe.d/nvidia-tweaks.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/nvidia/nvidia-uvm.conf,/etc/modules-load.d/nvidia-uvm.conf,sudo)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/nvidia/60-nvidia.rules,/etc/udev/rules.d/60-nvidia.rules,sudo)
endef
```

And locate `arch/p1/install`:
Change:

```makefile
	$(if $(filter copy,$(MODE)),cp "$(ROOTDIR)/arch/waybar_p1.css" "$(HOME)/.config/waybar/style.css",ln -sfvn "$(ROOTDIR)/arch/waybar_p1.css" "$(HOME)/.config/waybar/style.css")
```

To:

```makefile
	@$(call DEPLOY_FUNC,$(ROOTDIR)/arch/waybar_p1.css,$(HOME)/.config/waybar/style.css,)
```

And locate `arch/desk/install`:
Change:

```makefile
	$(if $(filter copy,$(MODE)),sudo cp "$(ROOTDIR)/network/nm/desk/70-persistent-network.rules" "/etc/udev/rules.d/70-persistent-network.rules",sudo ln -sfvn "$(ROOTDIR)/network/nm/desk/70-persistent-network.rules" "/etc/udev/rules.d/70-persistent-network.rules")
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		$(if $(filter copy,$(MODE)),sudo cp "$(ROOTDIR)/$$src" "$$dest",sudo ln -sfvn "$(ROOTDIR)/$$src" "$$dest"); \
	done
```

To:

```makefile
	@$(call DEPLOY_FUNC,$(ROOTDIR)/network/nm/desk/70-persistent-network.rules,/etc/udev/rules.d/70-persistent-network.rules,sudo)
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$$dest,sudo); \
	done
```

- [ ] **Step 2: Run test to verify it passes**
      Run: `make arch/install MODE=link ROOTDIR=$(pwd)`
      Expected: Execution finishes cleanly.

- [ ] **Step 3: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "refactor(install): use DEPLOY_FUNC in arch install targets"
```

---

### Task 4: Refactor mac/install loops and direct calls

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Write the minimal implementation**
      In `Makefile.d/install.mk`, locate the `mac/install:` target.

Change:

```makefile
mac/install: dotfiles/install
	$(MAC_PREP)
	$(if $(filter copy,$(MODE)),cp "$(ROOTDIR)/macos/docker_config.json" "$(HOME)/.docker/config.json",ln -sfvn "$(ROOTDIR)/macos/docker_config.json" "$(HOME)/.docker/config.json")
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	$(if $(filter copy,$(MODE)),sudo cp "$(ROOTDIR)/macos/docker_config.json" "/etc/docker/config.json",sudo ln -sfvn "$(ROOTDIR)/macos/docker_config.json" "/etc/docker/config.json")
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		sudo ln -sfvn "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chown root:wheel "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua
```

To:

```makefile
mac/install: dotfiles/install
	$(MAC_PREP)
	@$(call DEPLOY_FUNC,$(ROOTDIR)/macos/docker_config.json,$(HOME)/.docker/config.json,)
	cp $(ROOTDIR)/dockers/daemon.json $(HOME)/.docker/daemon.json
	@$(call DEPLOY_FUNC,$(ROOTDIR)/macos/docker_config.json,/etc/docker/config.json,sudo)
	sudo cp $(ROOTDIR)/dockers/daemon.json /etc/docker/daemon.json
	for agent in $(MACOS_LAUNCH_AGENTS); do \
		sudo ln -sfvn "$(ROOTDIR)/macos/$$agent" "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chmod 600 "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo chown root:wheel "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo plutil -lint "$(HOME)/Library/LaunchAgents/$$agent"; \
		sudo launchctl load -w "$(HOME)/Library/LaunchAgents/$$agent"; \
	done
	sudo rm -rf $(ROOTDIR)/nvim/lua/lua
```

- [ ] **Step 2: Run test to verify it passes**
      Run: `make mac/install MODE=link ROOTDIR=$(pwd)` (Will fail on non-Mac, but syntax parsing can be checked with `make -n mac/install`)
      Expected: Dry run succeeds parsing.

- [ ] **Step 3: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "refactor(install): use DEPLOY_FUNC in mac install targets"
```

---

### Task 5: Refactor Cleaning Logic

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Write the minimal implementation**
      In `Makefile.d/install.mk`, delete the entire `CLEAN_FILES = \ ...` block.
      Modify `dotfiles/clean` target to iterate maps instead.

Change `dotfiles/clean`:

```makefile
dotfiles/clean: dotfiles/perm
	$(eval TMP_DIR := $(shell mktemp -d))
	jq . $(ROOTDIR)/arch/waybar.json > $(TMP_DIR)/waybar.json.tmp && mv $(TMP_DIR)/waybar.json.tmp $(ROOTDIR)/arch/waybar.json
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		[ -z "$$src" ] && continue; \
		sudo rm -rf "$(HOME)/$$dest"; \
	done
	sudo rm -rf $(CLEAN_FILES)
```

To:

```makefile
dotfiles/clean: dotfiles/perm
	$(eval TMP_DIR := $(shell mktemp -d))
	jq . $(ROOTDIR)/arch/waybar.json > $(TMP_DIR)/waybar.json.tmp && mv $(TMP_DIR)/waybar.json.tmp $(ROOTDIR)/arch/waybar.json
	@echo "$$DOTFILES_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$(HOME)/$$dest,sudo); \
	done
	@$(call CLEAN_FUNC,/etc/docker/config.json,sudo)
	@$(call CLEAN_FUNC,/etc/docker/daemon.json,sudo)
	@$(call CLEAN_FUNC,/etc/containerd/config.toml,sudo)
```

Add `arch/clean` target right below `arch/desk/install`:

```makefile
arch/clean:
	@echo "$$ARCH_LINK_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$(HOME)/$$dest,sudo); \
	done
	@echo "$$ARCH_SUDO_CP_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$$dest,sudo); \
	done
	@echo "$$ARCH_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$$dest,sudo); \
	done
	@echo "$$ARCH_DESK_SUDO_LINK_MAP" | while read -r src dest; do \
		$(call CLEAN_FUNC,$$dest,sudo); \
	done
	@$(call CLEAN_FUNC,/etc/modprobe.d/nvidia-tweaks.conf,sudo)
	@$(call CLEAN_FUNC,/etc/modules-load.d/nvidia-uvm.conf,sudo)
	@$(call CLEAN_FUNC,/etc/udev/rules.d/60-nvidia.rules,sudo)
	@$(call CLEAN_FUNC,$(HOME)/.config/waybar/style.css,sudo)
	@$(call CLEAN_FUNC,/etc/udev/rules.d/70-persistent-network.rules,sudo)
```

Add `mac/clean` target below `mac/install`:

```makefile
mac/clean:
	@$(call CLEAN_FUNC,$(HOME)/.docker/config.json,sudo)
	@$(call CLEAN_FUNC,/etc/docker/config.json,sudo)
```

Update `clean` alias at the bottom:
Change:

```makefile
clean:          ; @$(MAKE) dotfiles/clean
```

To:

```makefile
clean:          ; @$(MAKE) dotfiles/clean
```

(No change needed to the alias itself as `dotfiles/clean` handles the common cleanup, but developers can manually run `make arch/clean` or `make mac/clean`).

- [ ] **Step 2: Run test to verify it passes**
      Run: `make dotfiles/clean`
      Expected: Cleaning executes dynamically over the map successfully.

- [ ] **Step 3: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "refactor(install): dynamically clean files via CLEAN_FUNC and maps"
```
