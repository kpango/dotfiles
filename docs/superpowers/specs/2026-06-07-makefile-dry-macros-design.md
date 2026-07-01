# Makefile DRY Macros Design

## Overview

Refactor the Makefiles (`install.mk` and `docker.mk`) to extract duplicated logic into reusable macros. This ensures adherence to the DRY (Don't Repeat Yourself) principle and makes the build system more maintainable.

## Architecture & Data Flow

1. **`Makefile.d/install.mk`**: The logic to detect the Go binary paths across different architectures and package managers is duplicated. We will extract this into a `FIND_GO` macro.
2. **`Makefile.d/docker.mk`**: The logic to run parallel Docker builds using `xpanes` or a shell fallback is duplicated with different `DOCKER_EXTRA_OPTS`. We will extract this into a `DOCKER_BUILD_PARALLEL` macro that accepts the options as a parameter.

## Implementation Details

### 1. `install.mk`

At the top of the file, define:

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

Replace the inline loops in `tmux/go/install` and `tmux/go/update` with `@$(FIND_GO); \`.

### 2. `docker.mk`

At the top of the file, define:

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

Replace the inline parallel execution in `docker/build` with `$(call DOCKER_BUILD_PARALLEL,$(DOCKER_EXTRA_OPTS))` and in `docker/build/prod` with `$(call DOCKER_BUILD_PARALLEL,--no-cache)`.

## Error Handling & Testing

- **Testing:** We will perform dry-run execution (`make -n`) on the affected targets (`tmux/go/install`, `tmux/go/update`, `docker/build`, `docker/build/prod`) to ensure that Bash string substitution happens correctly and without syntax errors.
