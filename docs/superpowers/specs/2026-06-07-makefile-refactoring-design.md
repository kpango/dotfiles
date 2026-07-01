# Makefile Refactoring Design

## Overview

Refactor the deployment logic (`link`, `copy`, and `clean` functionalities) in the Makefiles to follow SOLID principles (Single Responsibility, DRY) and provide a unified, maintainable implementation.

## Architecture & Data Flow

Currently, `Makefile.d/install.mk` repeats an inline conditional statement `$(if $(filter copy,$(MODE)), ...)` for both single file deployments and map-based iterations. It also maintains a separate `CLEAN_FILES` array that duplicates the destination paths of files deployed via maps.

We will extract the core logic into reusable Makefile macros:

1. `DEPLOY_FUNC`: Handles creation of destination directories and logic for copying vs. linking based on the `MODE` variable.
2. `CLEAN_FUNC`: Handles removal of destination files/directories.

These macros will be invoked directly inside deployment targets for single files and within `while read` loops for map-based deployments.

The `clean` logic will be decoupled from a static array and will instead dynamically iterate over the existing maps (`DOTFILES_MAP`, `ARCH_LINK_MAP`, etc.) to guarantee that what is deployed is exactly what gets cleaned.

## Implementation Details

**1. Macro Definitions (in `Makefile.d/install.mk`)**

```makefile
define DEPLOY_FUNC
	[ -z "$(1)" ] || { \
		$(3) mkdir -p "$$(dirname "$(2)")"; \
		$(if $(filter copy,$(MODE)), \
			$(3) rm -rf "$(2)" && $(3) cp -r "$(1)" "$(2)", \
			$(3) ln -sfvn "$(1)" "$(2)" \
		); \
	}
endef

define CLEAN_FUNC
	[ -z "$(1)" ] || $(2) rm -rf "$(1)"
endef
```

**2. Loop Refactoring**
Update all `while read -r src dest` loops. For example:

```makefile
@echo "$$DOTFILES_MAP" | while read -r src dest; do \
	$(call DEPLOY_FUNC,$(ROOTDIR)/$$src,$(HOME)/$$dest,); \
done
```

**3. Direct Command Refactoring**
Replace direct command calls. For example:

```makefile
$(call DEPLOY_FUNC,$(ROOTDIR)/dockers/config.json,/etc/docker/config.json,sudo)
```

**4. Cleaning Refactoring**
Remove `CLEAN_FILES`.
Create granular clean targets:

- `dotfiles/clean`: iterates over `DOTFILES_MAP` to clean.
- `arch/clean`: iterates over Arch-specific maps to clean.
- `mac/clean`: iterates over Mac-specific files to clean.
  Update the global `clean` target (if one exists) to run these specific clean targets, maintaining high cohesion.

## Error Handling & Testing

- **Testing:** Run `make dotfiles/install MODE=link`, verify the macros expand properly in the shell. Run `make dotfiles/clean` to verify dynamic cleaning works.
- **Edge cases:** Bash variables in `$(call ...)` need to be evaluated gracefully without syntactic breaking, which is why we pass them as strings like `$(HOME)/$$dest` in the call.
