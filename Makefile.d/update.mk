.PHONY: update \
	update/versions \
	update/versions/actions \
	update/versions/tools

# Retry settings for curl (separate from Docker-only CURL_RETRY in Dockerfiles)
UPDATE_CURL_RETRY       ?= 3
UPDATE_CURL_RETRY_DELAY ?= 2

# ─────────────────────────────────────────────────────────────────────────────
# update — bump every version pin in the repository
#
# Targets:
#   update                  — run all sub-targets (actions + tools + nix flake)
#   update/versions         — update version strings in source files
#   update/versions/actions — GitHub Actions @version pins in .github/workflows/
#   update/versions/tools   — tool version strings (shfmt, etc.) in workflows
#
# The nix flake.lock is updated via the existing nix/update target.
#
# GITHUB_ACCESS_TOKEN is used when available (read from `pass` in variables.mk)
# to avoid GitHub API rate limits.
# ─────────────────────────────────────────────────────────────────────────────

## Update all version pins (GitHub Actions, tools) and the nix flake.lock.
update: update/versions nix/update
	@echo ""
	@echo "==================================================="
	@echo " All versions updated."
	@echo " Review with: git diff"
	@echo "==================================================="

update/versions: update/versions/actions update/versions/tools

# ── GitHub Actions action versions ───────────────────────────────────────────
#
# Scans all .github/workflows/*.{yml,yaml} files to discover every
# "uses: owner/repo@..." pin, then fetches the latest release and rewrites
# each pin to the latest major version tag (e.g. v4.2.1 → v4).
#
# No manual list to maintain — new actions are picked up automatically.
update/versions/actions:
	@echo "==================================================="
	@echo " update/versions/actions"
	@echo "==================================================="
	@GH_TOKEN="$(GITHUB_ACCESS_TOKEN)"; \
	REPOS=$$(grep -rh 'uses:' "$(ROOTDIR)/.github/workflows" \
		| sed -n 's/.*uses:[[:space:]]*\([A-Za-z0-9_.-][A-Za-z0-9_.-]*\/[A-Za-z0-9_.-][A-Za-z0-9_.-]*\)@.*/\1/p' \
		| sort -u); \
	for repo in $$REPOS; do \
		if [ -n "$$GH_TOKEN" ]; then \
			RESP=$$(curl \
				--retry $(UPDATE_CURL_RETRY) \
				--retry-all-errors \
				--retry-delay $(UPDATE_CURL_RETRY_DELAY) \
				-fsSL \
				-H "Authorization: Bearer $$GH_TOKEN" \
				"https://api.github.com/repos/$$repo/releases/latest" 2>/dev/null); \
		else \
			RESP=$$(curl \
				--retry $(UPDATE_CURL_RETRY) \
				--retry-all-errors \
				--retry-delay $(UPDATE_CURL_RETRY_DELAY) \
				-fsSL \
				"https://api.github.com/repos/$$repo/releases/latest" 2>/dev/null); \
		fi; \
		TAG=$$(printf '%s' "$$RESP" \
			| grep '"tag_name"' \
			| sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
			| head -1); \
		if [ -z "$$TAG" ] || [ "$$TAG" = "null" ]; then \
			printf "  SKIP  %-55s (no release found)\n" "$$repo"; \
			continue; \
		fi; \
		MAJOR=$$(printf '%s' "$$TAG" | grep -oE 'v[0-9]+' | head -1); \
		VER="$${MAJOR:-$$TAG}"; \
		printf "  %-55s %s → %s\n" "$$repo" "$$TAG" "$$VER"; \
		find "$(ROOTDIR)/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) \
			| xargs sed -i -E \
				"s|(uses:[[:space:]]+$$repo)@[^[:space:]]+|\1@$$VER|g"; \
	done
	@echo "  Done."

# ── Tool version strings in workflow files ────────────────────────────────────
#
# Each entry is "owner/repo|VAR_NAME" where VAR_NAME is the shell variable
# used in the workflow to hold the version (e.g. SHFMT_VER=v3.8.0).
# The full release tag is used (not major-only), since these are binary downloads.
#
# Pattern matched and replaced: VAR_NAME=v<semver>
update/versions/tools:
	@echo "==================================================="
	@echo " update/versions/tools"
	@echo "==================================================="
	@GH_TOKEN="$(GITHUB_ACCESS_TOKEN)"; \
	for entry in \
		"mvdan/sh|SHFMT_VER" \
	; do \
		repo=$$(printf '%s' "$$entry" | cut -d'|' -f1); \
		var=$$(printf '%s' "$$entry" | cut -d'|' -f2); \
		if [ -n "$$GH_TOKEN" ]; then \
			RESP=$$(curl \
				--retry $(UPDATE_CURL_RETRY) \
				--retry-all-errors \
				--retry-delay $(UPDATE_CURL_RETRY_DELAY) \
				-fsSL \
				-H "Authorization: Bearer $$GH_TOKEN" \
				"https://api.github.com/repos/$$repo/releases/latest" 2>/dev/null); \
		else \
			RESP=$$(curl \
				--retry $(UPDATE_CURL_RETRY) \
				--retry-all-errors \
				--retry-delay $(UPDATE_CURL_RETRY_DELAY) \
				-fsSL \
				"https://api.github.com/repos/$$repo/releases/latest" 2>/dev/null); \
		fi; \
		TAG=$$(printf '%s' "$$RESP" \
			| grep '"tag_name"' \
			| sed 's/.*"tag_name": *"\([^"]*\)".*/\1/' \
			| head -1); \
		if [ -z "$$TAG" ] || [ "$$TAG" = "null" ]; then \
			printf "  SKIP  %-35s (no release found)\n" "$$repo ($$var)"; \
			continue; \
		fi; \
		printf "  %-35s %s\n" "$$repo ($$var)" "→ $$TAG"; \
		find "$(ROOTDIR)/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) \
			| xargs sed -i \
				"s/$${var}=v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/$${var}=$$TAG/g"; \
	done
	@echo "  Done."
