# Makefile DRY Macros Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract duplicated logic in `Makefile.d/install.mk` and `Makefile.d/docker.mk` into reusable DRY macros.

**Architecture:** Define `FIND_GO` in `install.mk` to abstract Go binary discovery. Define `DOCKER_BUILD_PARALLEL` in `docker.mk` to abstract xpanes/loop parallel image building. Replace duplicated implementations with macro calls.

**Tech Stack:** Makefile, Bash

---

### Task 1: Refactor FIND_GO macro in install.mk

**Files:**

- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Write the failing test**
      Run: `grep "define FIND_GO" Makefile.d/install.mk || echo "Missing"`
      Expected: Missing

- [ ] **Step 2: Write minimal implementation**
      Open `Makefile.d/install.mk` and insert the `FIND_GO` macro near the top, just below the `CLEAN_FUNC` macro.

```makefile
define FIND_GO
	_go=''; _root=''; \
	for _c in \
	    /usr/lib/go/bin/go \
	    /usr/local/go/bin/go \
	    /opt/homebrew/bin/go \
	    /opt/homebrew/opt/go/libexec/bin/go; \
	do \
	    [ -x "$$_c" ] || continue; \
	    _r="$$(dirname "$$(dirname "$$_c")")"; \
	    GOROOT="$$_r" "$$_c" version >/dev/null 2>&1 && { _go="$$_c"; _root="$$_r"; break; }; \
	done; \
	if [ -z "$$_go" ] && _c="$$(command -v go 2>/dev/null)" && [ -x "$$_c" ]; then \
	    _r="$$(env -u GOROOT "$$_c" env GOROOT 2>/dev/null)"; \
	    [ -n "$$_r" ] && GOROOT="$$_r" "$$_c" version >/dev/null 2>&1 \
	        && { _go="$$_c"; _root="$$_r"; }; \
	fi
endef
```

Then, locate `tmux/go/install:` target. Replace the duplicated block:

```makefile
	@_go=''; _root=''; \
	for _c in \
	    /usr/lib/go/bin/go \
...
	    [ -n "$$_r" ] && GOROOT="$$_r" "$$_c" version >/dev/null 2>&1 \
	        && { _go="$$_c"; _root="$$_r"; }; \
	fi; \
```

With:

```makefile
	@$(FIND_GO); \
```

Do the exact same replacement for the `tmux/go/update:` target.

- [ ] **Step 3: Run test to verify it passes**
      Run: `make -n tmux/go/install`
      Expected: Outputs a clean expanded script without syntax errors.

- [ ] **Step 4: Commit**

```bash
git add Makefile.d/install.mk
git commit -m "refactor(install): extract FIND_GO macro to remove DRY violations"
```

---

### Task 2: Refactor DOCKER_BUILD_PARALLEL macro in docker.mk

**Files:**

- Modify: `Makefile.d/docker.mk`

- [ ] **Step 1: Write the failing test**
      Run: `grep "define DOCKER_BUILD_PARALLEL" Makefile.d/docker.mk || echo "Missing"`
      Expected: Missing

- [ ] **Step 2: Write minimal implementation**
      Open `Makefile.d/docker.mk` and insert the `DOCKER_BUILD_PARALLEL` macro near the top, just below the aliases.

```makefile
define DOCKER_BUILD_PARALLEL
	@if command -v xpanes >/dev/null 2>&1; then \
		xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=\"$(1)\" -f $(ROOTDIR)/Makefile docker/build/{}" go docker rust dart k8s nim gcloud zig nix env vald; \
	else \
		for img in go docker rust dart k8s nim gcloud zig nix env vald; do \
			$(MAKE) DOCKER_EXTRA_OPTS=\"$(1)\" -f $(ROOTDIR)/Makefile docker/build/$$img & \
		done; wait; \
	fi
endef
```

Then, locate `docker/build:` target. Replace the duplicated block:

```makefile
	@if command -v xpanes >/dev/null 2>&1; then \
		xpanes -s -c "$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) -f $(ROOTDIR)/Makefile docker/build/{}" go docker rust dart k8s nim gcloud zig nix env vald; \
	else \
		for img in go docker rust dart k8s nim gcloud zig nix env vald; do \
			$(MAKE) DOCKER_EXTRA_OPTS=$(DOCKER_EXTRA_OPTS) -f $(ROOTDIR)/Makefile docker/build/$$img & \
		done; wait; \
	fi
```

With:

```makefile
	$(call DOCKER_BUILD_PARALLEL,$(DOCKER_EXTRA_OPTS))
```

Then, locate `docker/build/prod:` target. Replace the similar block (which passes `--no-cache`) with:

```makefile
	$(call DOCKER_BUILD_PARALLEL,--no-cache)
```

- [ ] **Step 3: Run test to verify it passes**
      Run: `make -n docker/build`
      Expected: Outputs a clean expanded script without syntax errors.

- [ ] **Step 4: Commit**

```bash
git add Makefile.d/docker.mk
git commit -m "refactor(docker): extract DOCKER_BUILD_PARALLEL macro to remove DRY violations"
```
