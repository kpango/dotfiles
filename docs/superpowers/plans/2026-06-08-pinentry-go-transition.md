# Pinentry Go Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the legacy shell script and transition exclusively to the Go binary for `pinentry-tmux`.

**Architecture:** The shell script is deleted and the symlink generation step in `Makefile.d/install.mk` is removed so that the Go binary built via the Makefile target is directly used.

**Tech Stack:** Go, Shell, Makefile

---

### Task 1: Remove legacy shell script

**Files:**

- Delete: `zfunc/pinentry-tmux`

- [ ] **Step 1: Delete file**

Run: `rm -f zfunc/pinentry-tmux`

- [ ] **Step 2: Commit**

```bash
git rm zfunc/pinentry-tmux
git commit -m "chore: remove legacy pinentry shell script"
```

### Task 2: Remove Makefile symlink step

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Edit Makefile**

Remove the line `zfunc/pinentry-tmux /usr/local/bin/pinentry-tmux` from the `ARCH_SUDO_LINK_MAP` section.

- [ ] **Step 2: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "chore: remove pinentry shell script symlink mapping"
```

### Task 3: Verify the Go binary target

**Files:**

- Test: Build and test target

- [ ] **Step 1: Run build**

Run: `make pinentry/install`

- [ ] **Step 2: Verify binary exists**

Run: `ls -la /usr/local/bin/pinentry-tmux`
Expected: Exists and is executable.
