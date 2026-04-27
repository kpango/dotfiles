.PHONY: format format/zsh format/dockerfile format/nix format/yaml format/go format/rust format/json format/md

FORMAT_ZSH_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.zsh" -o -name "zshrc" -o -name ".zshrc")
FORMAT_DOCKER_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.Dockerfile" -o -name "Dockerfile")
FORMAT_NIX_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.nix")
FORMAT_YAML_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.yaml" -o -name "*.yml")
FORMAT_GO_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.go")
FORMAT_RUST_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.rs")
FORMAT_JSON_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.json")
FORMAT_MD_FILES ?= $(shell find $(ROOTDIR) -type f -name "*.md")

format: \
	format/zsh \
	format/dockerfile \
	format/nix \
	format/yaml \
	format/go \
	format/rust \
	format/json \
	format/md

format/zsh:
	@if [ -n "$(FORMAT_ZSH_FILES)" ]; then \
		echo "Formatting zsh files..."; \
		if command -v shfmt >/dev/null 2>&1; then \
			shfmt -w $(FORMAT_ZSH_FILES); \
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
