# Pinentry Go Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the `pinentry-tmux` Go binary to use modern Go standard libraries (like `clear()` and `context`) and securely handle memory via `runtime/secret`.

**Architecture:** Modifying `pinentry/tmux/main.go` and its associated Makefile target to incorporate `GOEXPERIMENT=runtimesecret`.

**Tech Stack:** Go 1.24+ (1.26 target)

---

### Task 1: Update the Makefile build target

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Add GOEXPERIMENT**

Update the `pinentry/install` target line to include `GOEXPERIMENT=runtimesecret` before the `go build` command.

- [ ] **Step 2: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "build: add runtimesecret experiment for pinentry"
```

### Task 2: Refactor pinentry Go code

**Files:**

- Modify: `pinentry/tmux/main.go`

- [ ] **Step 1: Add modern standard library functions**

- Use `clear()` instead of looping to zero `stBytes` and `pinBytes`.
- Use `signal.NotifyContext` and `exec.CommandContext`.
- Wrap sensitive passphrase operations in `secret.Do(func() { ... })`.

- [ ] **Step 2: Commit**

```bash
git add pinentry/tmux/main.go
git commit -m "refactor: modernize pinentry to use runtime/secret and contexts"
```

### Task 3: Verify the Build

**Files:**

- Test: Build the binary

- [ ] **Step 1: Run build**

Run: `make pinentry/install`

- [ ] **Step 2: Verify binary exists**

Expected: Exists and is executable, compiles successfully.
