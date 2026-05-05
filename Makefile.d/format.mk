.PHONY: format format/zsh format/dockerfile format/nix format/yaml format/go format/rust format/json format/md format/makefile format/conf format/convert-to-zsh

FORMAT_ZSH_FILES ?= $(shell find $(ROOTDIR) -type f \( -name "*.zsh" -o -name "zshrc" -o -name ".zshrc" \) -not -path "*/.git/*")
FORMAT_DOCKER_FILES ?= $(shell find $(ROOTDIR) -type f \( -name "*.Dockerfile" -o -name "Dockerfile" \) -not -path "*/.git/*")
FORMAT_NIX_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.nix" -not -path "*/.git/*")
FORMAT_YAML_FILES ?= $(shell find $(ROOTDIR) -type f \( -name "*.yaml" -o -name "*.yml" \) -not -path "*/.git/*")
FORMAT_GO_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.go" -not -path "*/.git/*")
FORMAT_RUST_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.rs" -not -path "*/.git/*")
FORMAT_JSON_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.json" -not -path "*/.git/*")
FORMAT_MD_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.md" -not -path "*/.git/*")
FORMAT_MAKEFILE_FILES ?= $(shell find $(ROOTDIR) -type f \( -name "Makefile" -o -name "*.mk" \) -not -path "*/.git/*")
FORMAT_CONF_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.conf" -not -path "*/.git/*")
# Scripts excluded from bash→zsh conversion.
# Two categories, both matched as *<suffix> against the full path:
#   - Must stay bash: run inside Docker/container environments where zsh is absent
#   - Must stay /bin/sh: run in chroot/early-boot where only POSIX sh is guaranteed
BASH_KEEP_SCRIPTS ?= \
    nix/scripts/nix-run.sh \
    arch/install.sh \
    arch/install_desk.sh \
    arch/install_p1.sh \
    arch/chroot.sh \
    arch/chroot_desk.sh \
    arch/chroot_p1.sh \
    arch/user-init.sh \
    macos/install.sh

format: \
	format/zsh \
	format/dockerfile \
	format/nix \
	format/yaml \
	format/go \
	format/rust \
	format/json \
	format/md \
	format/makefile \
	format/conf

format/zsh:
	@if [ -n "$(FORMAT_ZSH_FILES)" ]; then \
		echo "Formatting zsh files..."; \
		if command -v shfmt >/dev/null 2>&1; then \
			shfmt -ln bash -w $(FORMAT_ZSH_FILES); \
			for _f in $(FORMAT_ZSH_FILES); do sed -i 's/ - /-/g' "$$_f"; done; \
			for _f in $(FORMAT_ZSH_FILES); do sed -i 's/ + /+/g' "$$_f"; done; \
		elif command -v beautysh >/dev/null 2>&1; then \
			beautysh $(FORMAT_ZSH_FILES); \
		else \
			echo "No zsh formatter found (shfmt or beautysh)"; \
		fi \
	fi

format/dockerfile:
	@if [ -n "$(FORMAT_DOCKER_FILES)" ]; then \
		echo "Skipping Dockerfiles formatting since dockfmt breaks BuildKit --mount syntax"; \
	fi

format/nix:
	@if [ -n "$(FORMAT_NIX_FILES)" ]; then \
		echo "Formatting Nix files..."; \
		if command -v nixpkgs-fmt >/dev/null 2>&1; then \
			nixpkgs-fmt $(FORMAT_NIX_FILES); \
		else \
			echo "No Nix formatter found (nixpkgs-fmt)"; \
		fi \
	fi

format/yaml:
	@if [ -n "$(FORMAT_YAML_FILES)" ]; then \
		echo "Formatting YAML files..."; \
		if command -v prettier >/dev/null 2>&1; then \
			prettier --write $(FORMAT_YAML_FILES); \
		elif command -v yamlfmt >/dev/null 2>&1; then \
			yamlfmt $(FORMAT_YAML_FILES); \
		else \
			echo "No YAML formatter found (prettier or yamlfmt)"; \
		fi \
	fi

format/go:
	@if [ -n "$(FORMAT_GO_FILES)" ]; then \
		echo "Formatting Go files..."; \
		if command -v gofmt >/dev/null 2>&1; then \
			gofmt -w $(FORMAT_GO_FILES); \
		else \
			echo "No Go formatter found (gofmt)"; \
		fi \
	fi

format/rust:
	@if [ -n "$(FORMAT_RUST_FILES)" ]; then \
		echo "Formatting Rust files..."; \
		if command -v rustfmt >/dev/null 2>&1; then \
			rustfmt $(FORMAT_RUST_FILES); \
		else \
			echo "No Rust formatter found (rustfmt)"; \
		fi \
	fi

format/json:
	@if [ -n "$(FORMAT_JSON_FILES)" ]; then \
		echo "Formatting JSON files..."; \
		if command -v prettier >/dev/null 2>&1; then \
			prettier --write $(FORMAT_JSON_FILES); \
		elif command -v jq >/dev/null 2>&1; then \
			for f in $(FORMAT_JSON_FILES); do jq . $$f > $$f.tmp && mv $$f.tmp $$f; done; \
		else \
			echo "No JSON formatter found (prettier or jq)"; \
		fi \
	fi

format/md:
	@if [ -n "$(FORMAT_MD_FILES)" ]; then \
		echo "Formatting Markdown files..."; \
		if command -v prettier >/dev/null 2>&1; then \
			prettier --write $(FORMAT_MD_FILES); \
		else \
			echo "No Markdown formatter found (prettier)"; \
		fi \
	fi

# Makefiles have no standard auto-formatter; recipe lines require literal tabs.
# Strip trailing whitespace only — safe and idempotent.
format/makefile:
	@if [ -n "$(FORMAT_MAKEFILE_FILES)" ]; then \
		echo "Stripping trailing whitespace from Makefiles..."; \
		for f in $(FORMAT_MAKEFILE_FILES); do \
			sed -i 's/[[:space:]]*$$//' "$$f"; \
		done; \
	fi

# One-shot migration: rewrite bash shebangs to zsh and reformat.
# Skips BASH_KEEP_SCRIPTS (Docker/container scripts where zsh is unavailable).
# Does NOT rename .sh files — callers reference them by name.
format/convert-to-zsh:
	@echo "Converting bash scripts to zsh..."
	@find "$(ROOTDIR)" -not -path "*/.git/*" -name "*.sh" -type f | \
	while IFS= read -r f; do \
		skip=0; \
		for excl in $(BASH_KEEP_SCRIPTS); do \
			case "$$f" in *$$excl) skip=1; break ;; esac; \
		done; \
		[ "$$skip" = "1" ] && continue; \
		first=$$(head -1 "$$f" 2>/dev/null); \
		case "$$first" in \
			'#!/bin/bash'*|'#!/usr/bin/bash'*|'#!/usr/bin/env bash'*) \
				echo "  $$f"; \
				sed -i \
					-e '1s|#!/bin/bash|#!/usr/bin/env zsh|' \
					-e '1s|#!/usr/bin/bash|#!/usr/bin/env zsh|' \
					-e '1s|#!/usr/bin/env bash|#!/usr/bin/env zsh|' \
					"$$f"; \
				if command -v shfmt >/dev/null 2>&1; then \
					shfmt -ln bash -w "$$f"; \
				fi ;; \
		esac; \
	done; \
	echo "  Done. Review changes before committing."

# conf files: apply shfmt -ln bash to shell-sourced confs (any #!/*sh or #!/hint/* shebang),
# strip trailing whitespace from all others (INI, custom formats, etc.).
format/conf:
	@if [ -n "$(FORMAT_CONF_FILES)" ]; then \
		echo "Formatting conf files..."; \
		for f in $(FORMAT_CONF_FILES); do \
			first=$$(head -1 "$$f" 2>/dev/null); \
			case "$$first" in \
				'#!/bin/zsh'*|'#!/usr/bin/zsh'*|'#!/usr/bin/env zsh'*|\
				'#!/bin/bash'*|'#!/usr/bin/bash'*|'#!/usr/bin/env bash'*|'#!/hint/bash'*|\
				'#!/bin/sh'*|'#!/usr/bin/env sh'*|'#!/hint/sh'*) \
					if command -v shfmt >/dev/null 2>&1; then \
						shfmt -ln bash -w "$$f"; \
					else \
						sed -i 's/[[:space:]]*$$//' "$$f"; \
					fi ;; \
				*) \
					sed -i 's/[[:space:]]*$$//' "$$f" ;; \
			esac; \
		done; \
	fi
