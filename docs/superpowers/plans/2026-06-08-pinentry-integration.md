# Pinentry Environment Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix macOS, NixOS, Docker, and general Makefile configurations to properly install, compile, or replace `pinentry-tmux` across all environments.

**Architecture:** We will update `nix/modules/home/dotfiles/darwin.nix` and `Makefile.d/install.mk` to correctly target `/usr/local/bin/pinentry-tmux` for macOS replacements. We will add `pinentry/install` to the `dotfiles/compile` target, and add `pinentry/tmux@latest` to `dockers/go.tools`.

**Tech Stack:** Makefile, Nix, Docker

---

### Task 1: Fix macOS Replacement Strings

**Files:**

- Modify: `nix/modules/home/dotfiles/darwin.nix`
- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Update darwin.nix**

In `nix/modules/home/dotfiles/darwin.nix`, change `/usr/bin/pinentry-tty` to `/usr/local/bin/pinentry-tmux`:

```nix
      builtins.replaceStrings [ "/usr/local/bin/pinentry-tmux" ] [ "/opt/homebrew/bin/pinentry-mac" ]
```

- [ ] **Step 2: Update Makefile.d/install.mk sed command**

In `Makefile.d/install.mk`, around line 244 under the `macos/install` target, change `/usr/bin/pinentry-tty` to `/usr/local/bin/pinentry-tmux`:

```makefile
	sed -i.bak 's|/usr/local/bin/pinentry-tmux|/opt/homebrew/bin/pinentry-mac|g' $(HOME)/.gnupg/gpg-agent.conf
```

- [ ] **Step 3: Commit**

```bash
git add nix/modules/home/dotfiles/darwin.nix Makefile.d/install.mk
git commit -m "fix: update macOS gpg-agent replacement strings for pinentry-tmux"
```

---

### Task 2: Fix dotfiles/compile Target

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Update dotfiles/compile**

In `Makefile.d/install.mk`, append `pinentry/install` to the `dotfiles/compile` dependency list (around line 300):

```makefile
## install tmux powerline glyph scripts and Go-compiled status helpers to ~/.zcache
dotfiles/compile: tmux/go/install pinentry/install
```

- [ ] **Step 2: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "build: add pinentry/install to dotfiles/compile dependencies"
```

---

### Task 3: Integrate with Docker Tools

**Files:**

- Modify: `dockers/go.tools`

- [ ] **Step 1: Add pinentry-tmux to go.tools**

Append `github.com/kpango/dotfiles/pinentry/tmux@latest` to the bottom of `dockers/go.tools`:

```text
github.com/kpango/dotfiles/pinentry/tmux@latest
```

- [ ] **Step 2: Commit**

```bash
git add dockers/go.tools
git commit -m "build: add pinentry-tmux to docker go.tools"
```

---

### Task 4: Validation

**Files:**

- Test: Makefile compilation

- [ ] **Step 1: Verify compilation triggers both**

Run: `make -n dotfiles/compile`
Expected: Output showing the make sequence invoking both `tmux/go/install` and `pinentry/install`.
