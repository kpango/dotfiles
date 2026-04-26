# Cleanup Legacy Alias References Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove all residual references to the legacy `alias` and `.aliases` files from the repository to complete the migration.

**Architecture:** We will modify `Makefile.d/dotfiles.mk` to remove `.aliases` mapping and cleanup `zshrc` injection, and we will update `nix/modules/home/dotfiles/shared.nix` and `nix/modules/home/programs/zsh.nix` to drop the references to `.aliases`.

**Tech Stack:** GNU Make, Nix, Zsh.

---

### Task 1: Clean up `Makefile.d/dotfiles.mk`

**Files:**

- Modify: `Makefile.d/dotfiles.mk`

- [ ] **Step 1: Write a conceptual failing test**
      Run: `grep -q 'alias .aliases' Makefile.d/dotfiles.mk && echo "Found"`
      Expected: Output `Found`.

- [ ] **Step 2: Remove `.aliases` from `DOTFILES_MAP`**
      Delete the line exactly matching `alias .aliases` from the `DOTFILES_MAP` definition.

- [ ] **Step 3: Update `run:` target**
      Change:

```makefile
run:
	source $(ROOTDIR)/alias && devrun
```

To:

```makefile
run:
	source $(ROOTDIR)/zsh/20-docker.zsh && devrun
```

- [ ] **Step 4: Remove `.zshrc` append operations**
      Delete the line `	[ -f $(HOME)/.zshrc ] && echo "[ -f $$HOME/.aliases ] && source $$HOME/.aliases" >> $(HOME)/.zshrc` from BOTH the `copy:` and `link:` targets.

- [ ] **Step 5: Verify cleanup**
      Run: `grep -q '.aliases' Makefile.d/dotfiles.mk || echo "Cleaned"`
      Expected: Output `Cleaned`.

- [ ] **Step 6: Commit changes**

```bash
git add Makefile.d/dotfiles.mk
git commit -m "refactor(make): remove legacy alias logic from dotfiles module"
```

---

### Task 2: Clean up Nix configurations

**Files:**

- Modify: `nix/modules/home/dotfiles/shared.nix`
- Modify: `nix/modules/home/programs/zsh.nix`

- [ ] **Step 1: Write a conceptual failing test**
      Run: `grep -q '\.aliases' nix/modules/home/dotfiles/shared.nix && echo "Found"`
      Expected: Output `Found`.

- [ ] **Step 2: Clean up `shared.nix`**
      Remove the line `    ".aliases".source = /. + "${dotfilesPath}/alias";` from `nix/modules/home/dotfiles/shared.nix`.

- [ ] **Step 3: Clean up `zsh.nix`**
      Remove these lines from `nix/modules/home/programs/zsh.nix` under `initExtra`:

```nix
      # Source aliases
      source ~/.aliases
```

- [ ] **Step 4: Verify cleanup**
      Run: `grep -q '\.aliases' nix/modules/home/dotfiles/shared.nix || echo "Cleaned"`
      Expected: Output `Cleaned`.

- [ ] **Step 5: Commit changes**

```bash
git add nix/modules/home/dotfiles/shared.nix nix/modules/home/programs/zsh.nix
git commit -m "refactor(nix): remove legacy alias file mapping and sourcing"
```
