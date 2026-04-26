# Devbox Makefile & Zsh Aliases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create Makefile targets for common Devbox workflows and register global Zsh aliases to run those make targets from anywhere.

**Architecture:** A new modular Makefile `Makefile.d/devbox.mk` will be created with targets for `devbox/install`, `devbox/shell`, `devbox/setup`, `devbox/update`, and `devbox/clean`. This file will be included in the root `Makefile`. Then, global aliases using the dotfiles' `$rcpath` variable will be appended to `zsh/20-dev.zsh` to execute these commands globally.

**Tech Stack:** GNU Make, Zsh, Devbox.

---

### Task 1: Create `Makefile.d/devbox.mk` and update `Makefile`

**Files:**

- Create: `Makefile.d/devbox.mk`
- Modify: `Makefile`

- [ ] **Step 1: Write the conceptual failing test**
      Run: `make devbox/shell`
      Expected: `make: *** No rule to make target 'devbox/shell'.  Stop.`

- [ ] **Step 2: Create the `devbox.mk` file**
      Create `Makefile.d/devbox.mk` with the following content:

```makefile
.PHONY: devbox/install devbox/shell devbox/setup devbox/update devbox/clean

devbox/install:
	@if ! command -v devbox >/dev/null 2>&1; then \
		echo "=> Installing Devbox..."; \
		curl -fsSL https://get.jetpack.io/devbox | bash; \
	else \
		echo "=> Devbox is already installed."; \
	fi
	devbox run true

devbox/shell: devbox/install
	devbox shell

devbox/setup: devbox/install
	devbox run setup
	devbox run update_tools

devbox/update:
	devbox update

devbox/clean:
	rm -rf .devbox
	echo "=> Devbox state cleaned."
```

- [ ] **Step 3: Include the new module in the main `Makefile`**
      Append `include Makefile.d/devbox.mk` to `Makefile`.

- [ ] **Step 4: Verify the make target exists**
      Run: `make -n devbox/shell` (dry run)
      Expected: Prints the commands associated with the target without errors.

- [ ] **Step 5: Commit changes**

```bash
git add Makefile Makefile.d/devbox.mk
git commit -m "feat(devbox): add Makefile targets for devbox lifecycle"
```

---

### Task 2: Add Zsh aliases for Devbox

**Files:**

- Modify: `zsh/20-dev.zsh`

- [ ] **Step 1: Write the conceptual failing test**
      Run: `zsh -c 'source zsh/20-dev.zsh; type dbox'`
      Expected: `dbox not found`

- [ ] **Step 2: Append aliases to `zsh/20-dev.zsh`**
      Append the following content to `zsh/20-dev.zsh`:

```zsh

# Devbox aliases
alias dbox="make -C \$rcpath devbox/shell"
alias dbox-install="make -C \$rcpath devbox/install"
alias dbox-setup="make -C \$rcpath devbox/setup"
alias dbox-update="make -C \$rcpath devbox/update"
alias dbox-clean="make -C \$rcpath devbox/clean"
```

- [ ] **Step 3: Verify the alias exists**
      Run: `zsh -c 'source zsh/20-dev.zsh; type dbox'`
      Expected: `dbox is an alias for make -C $rcpath devbox/shell`

- [ ] **Step 4: Commit changes**

```bash
git add zsh/20-dev.zsh
git commit -m "feat(zsh): add global aliases for devbox make commands"
```
