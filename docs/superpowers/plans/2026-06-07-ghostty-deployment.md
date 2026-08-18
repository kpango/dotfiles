# Ghostty Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure Ghostty themes and shaders are correctly deployed to the user's host machine.

**Architecture:** Modify the `DOTFILES_MAP` variable in `Makefile.d/install.mk` to include mappings for the missing Ghostty directories.

**Tech Stack:** Makefile, Bash

---

### Task 1: Update DOTFILES_MAP

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Verify the failing state (Test)**

Run: `ls -la ~/.config/ghostty/themes ~/.config/ghostty/shaders 2>/dev/null || echo "Missing"`
Expected: Missing (or files not linked from the dotfiles repo).

- [ ] **Step 2: Write minimal implementation**

Modify `Makefile.d/install.mk` by adding the mappings for Ghostty themes and shaders.

```makefile
ghostty/themes .config/ghostty/themes
ghostty/shaders .config/ghostty/shaders
```

Insert these lines immediately after the existing `ghostty.conf .config/ghostty/config` entry in `DOTFILES_MAP`.

- [ ] **Step 3: Run the deployment (Make it pass)**

Run: `make dotfiles/install MODE=link ROOTDIR=$(pwd)`
Expected: The `make` command completes successfully and creates the symlinks.

- [ ] **Step 4: Verify the passing state (Verify)**

Run: `ls -la ~/.config/ghostty/themes ~/.config/ghostty/shaders`
Expected: The directories exist and are symlinked to the dotfiles repository.

- [ ] **Step 5: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "fix(install): add ghostty themes and shaders to dotfiles map"
```
