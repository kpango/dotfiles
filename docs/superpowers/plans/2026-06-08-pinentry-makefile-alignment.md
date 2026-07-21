# Pinentry Makefile Protocol Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the `pinentry-tmux` build targets in `Makefile.d/install.mk` to mirror the cross-platform `FIND_GO` approach used for `tmux-pane-info`.

**Architecture:** Rewrite the `pinentry/install` target to use `$(FIND_GO)` and introduce a `pinentry/update` target that fetches the latest module version and builds it. Both targets will `sudo install` the resulting binary to `/usr/local/bin/pinentry-tmux`.

**Tech Stack:** Makefile, shell scripting

---

### Task 1: Refactor pinentry/install

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Update the target in install.mk**

Replace the current `pinentry/install` block (around line 410):

```makefile
## build and install the Go pinentry-tmux binary to /usr/local/bin
pinentry/install:
	cd $(ROOTDIR)/pinentry/tmux && GOROOT=$(shell dirname $$(dirname $$(realpath $$(command -v go)))) GOEXPERIMENT=runtimesecret go build -trimpath -ldflags="-s -w" -o /tmp/pinentry-tmux .
	sudo install -m 755 /tmp/pinentry-tmux /usr/local/bin/pinentry-tmux
	rm -f /tmp/pinentry-tmux
```

With the new `FIND_GO`-based logic:

```makefile
## build and install the Go pinentry-tmux binary to /usr/local/bin
## Detects Go across Arch, macOS Homebrew, and PATH.
pinentry/install:
	@$(FIND_GO); \
	if [ -n "$$_go" ]; then \
	    cd $(ROOTDIR)/pinentry/tmux \
	    && GOROOT="$$_root" GOEXPERIMENT=runtimesecret "$$_go" build -trimpath -ldflags="-s -w" -buildvcs=false -o /tmp/pinentry-tmux . \
	    && sudo install -m 755 /tmp/pinentry-tmux /usr/local/bin/pinentry-tmux \
	    && rm -f /tmp/pinentry-tmux \
	    && echo "pinentry-tmux: installed /usr/local/bin/pinentry-tmux"; \
	else \
	    echo "pinentry-tmux: Go not found — cannot build"; \
	    exit 1; \
	fi
```

- [ ] **Step 2: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "build: align pinentry/install with tmux-pane-info FIND_GO protocol"
```

---

### Task 2: Implement pinentry/update

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Add the update target**

Directly below the `pinentry/install` target, add:

```makefile
## install or update pinentry-tmux from the published module (no local clone required)
pinentry/update:
	@$(FIND_GO); \
	if [ -n "$$_go" ]; then \
	    GOROOT="$$_root" GOEXPERIMENT=runtimesecret "$$_go" build -trimpath -ldflags="-s -w" -buildvcs=false -o /tmp/pinentry-tmux github.com/kpango/dotfiles/pinentry/tmux@latest \
	    && sudo install -m 755 /tmp/pinentry-tmux /usr/local/bin/pinentry-tmux \
	    && rm -f /tmp/pinentry-tmux \
	    && echo "pinentry-tmux: updated to latest at /usr/local/bin/pinentry-tmux"; \
	else \
	    echo "pinentry-tmux: Go not found — cannot update"; \
	    exit 1; \
	fi
```

- [ ] **Step 2: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "build: add pinentry/update target mirroring tmux/go/update"
```

---

### Task 3: Validation

**Files:**

- Test: Makefile targets

- [ ] **Step 1: Run pinentry/install**

Run: `make pinentry/install`
Expected: Output showing "pinentry-tmux: installed /usr/local/bin/pinentry-tmux"
