# Antigravity CLI (agy) and Gemini CLI Configuration Synchronization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the line-continuation bugs in the dotfiles install Makefile, restore the broken Gemini CLI symlinks, and link the Antigravity CLI (`agy`) configuration directory to Gemini's to enable full synchronization of superpowers, settings, and credentials.

**Architecture:**

1. Fix the `Makefile.d/install.mk` line-continuation syntax errors.
2. Direct all `~/.gemini` settings and policies to point to `agy/` in the repository instead of the non-existent `gemini/` path.
3. Link `~/.agy` directly to `~/.gemini` to allow both clients to seamlessly share logs, extensions, custom skills, and authentication states.

**Tech Stack:** Bash, GNU Make, Symlinks.

---

### Task 1: Fix Makefile Line-Continuation Syntax Bug

**Files:**

- Modify: `Makefile.d/install.mk` (Lines 71-74)

- [ ] **Step 1: Locate the syntax error lines**
      Identify the lines under `define DOTFILES_MAP` with redundant backslashes:

```makefile
agy/policies/policy.toml .agy/policies/rules.toml \
agy/settings.json .agy/settings.json \
ghostty.conf .config/ghostty/config
```

- [ ] **Step 2: Apply the correction to `Makefile.d/install.mk`**
      Remove the ` \` at the end of both lines so each file map entry stands on its own line:

```makefile
agy/policies/policy.toml .agy/policies/rules.toml
agy/settings.json .agy/settings.json
ghostty.conf .config/ghostty/config
```

- [ ] **Step 3: Run GNU Make in dry-run mode to verify**
      Execute the Makefile install in dry-run mode to confirm no syntax or line merging errors exist.
      Run: `make -C ~/go/src/github.com/kpango/dotfiles/ -n dotfiles/install`
      Expected Output: Print clean, separate directory creation and symlinking operations for `agy/policies/rules.toml`, `agy/settings.json`, and `ghostty.conf`.

- [ ] **Step 4: Commit the Makefile correction**
      Run:

```bash
git add Makefile.d/install.mk
git commit -m "fix: resolve line-continuation syntax bug in install.mk DOTFILES_MAP"
```

---

### Task 2: Restore and Align `~/.gemini` Symlinks

**Files:**

- Modify: `~/.gemini/settings.json` (Symlink)
- Modify: `~/.gemini/policies/policy.toml` (Symlink)
- Modify: `~/.gemini/policies/rules.toml` (Symlink)

- [ ] **Step 1: Clean up broken symlinks**
      Remove the existing broken symlinks pointing to `dotfiles/gemini/...`.
      Run:

```bash
rm -f ~/.gemini/settings.json ~/.gemini/policies/policy.toml ~/.gemini/policies/rules.toml
```

- [ ] **Step 2: Create correct symlinks pointing to `agy/`**
      Re-create the symlinks pointing to the current, valid `agy/` folders in the workspace:
      Run:

```bash
ln -sfvn ~/go/src/github.com/kpango/dotfiles/agy/settings.json ~/.gemini/settings.json
ln -sfvn ~/go/src/github.com/kpango/dotfiles/agy/policies/policy.toml ~/.gemini/policies/policy.toml
ln -sfvn ~/go/src/github.com/kpango/dotfiles/agy/policies/policy.toml ~/.gemini/policies/rules.toml
```

- [ ] **Step 3: Verify the links are valid and active**
      Run: `ls -la ~/.gemini ~/.gemini/policies/`
      Expected Output: Confirm that the links point to `/home/kpango/go/src/github.com/kpango/dotfiles/agy/...` and that running `cat ~/.gemini/settings.json` outputs the configuration successfully.

---

### Task 3: Sync Antigravity CLI (`~/.agy`) with Gemini CLI (`~/.gemini`)

**Files:**

- Create: `~/.agy` (Symlink to `~/.gemini`)

- [ ] **Step 1: Check and back up existing `~/.agy`**
      Check if `~/.agy` exists as a directory or symlink. If it does, back it up.
      Run:

```bash
if [ -e ~/.agy ] || [ -L ~/.agy ]; then
  mv ~/.agy ~/.agy.bak
fi
```

- [ ] **Step 2: Symlink `~/.agy` to `~/.gemini`**
      Create a symbolic link from `~/.agy` pointing directly to `~/.gemini`. This syncs all configurations, extensions (such as superpowers skills), credentials, and history.
      Run:

```bash
ln -s ~/.gemini ~/.agy
```

- [ ] **Step 3: Verify the synchronized environment**
      Check if `~/.agy` is correctly resolved as a symbolic link pointing to `~/.gemini`.
      Run: `ls -ld ~/.agy`
      Expected Output: `lrwxrwxrwx ... /home/kpango/.agy -> /home/kpango/.gemini`

- [ ] **Step 4: Run `agy` version and basic verification**
      Run the `agy` CLI to ensure it boots cleanly and reads the synced policies.
      Run: `agy --version`
      Expected Output: `1.1.15` (and no configuration reading or permissions errors).
