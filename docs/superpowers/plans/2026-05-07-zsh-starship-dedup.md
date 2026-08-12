# zsh Starship Deduplication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the redundant synchronous `eval "$(starship init zsh)"` from `zsh.nix` so starship is only initialised once, via sheldon's cached+deferred path.

**Architecture:** Single-line removal from `nix/modules/home/programs/zsh.nix`. Sheldon's `[plugins.starship]` inline plugin in `sheldon.toml` already handles starship initialisation with `_zcache_eval` (cached) and `zsh-defer` (deferred), making the `initContent` call redundant and slower.

**Tech Stack:** Nix/home-manager, zsh

---

### Task 1: Remove redundant starship init from zsh.nix

**Files:**

- Modify: `nix/modules/home/programs/zsh.nix`

- [ ] **Step 1: Read the current file to confirm content**

```bash
cat nix/modules/home/programs/zsh.nix
```

Confirm `initContent` contains both `eval "$(sheldon source)"` and `eval "$(starship init zsh)"`.

- [ ] **Step 2: Remove the starship init line and its comment**

Find:

```nix
    initContent = ''
      # Init Sheldon
      eval "$(sheldon source)"

      # Init Starship
      eval "$(starship init zsh)"

      # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
      source ${dotfilesPath}/zshrc
    '';
```

Replace with:

```nix
    initContent = ''
      # Init Sheldon
      eval "$(sheldon source)"

      # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
      source ${dotfilesPath}/zshrc
    '';
```

- [ ] **Step 3: Verify no other starship references in zsh.nix**

```bash
grep -n "starship" nix/modules/home/programs/zsh.nix
```

Expected: no output (the line has been removed).

- [ ] **Step 4: Confirm sheldon.toml still handles starship**

```bash
grep -A 12 '\[plugins.starship\]' sheldon.toml
```

Expected: shows the `_zcache_eval starship` inline plugin — confirms starship initialisation is still present via the cached path.

- [ ] **Step 5: Commit**

```bash
git add nix/modules/home/programs/zsh.nix
git commit -m "fix: remove redundant synchronous starship init from zsh.nix, sheldon handles it"
```
