.PHONY: update \
	update/versions \
	update/versions/actions \
	update/versions/tools \
	up

# Retry settings for curl (separate from Docker-only CURL_RETRY in Dockerfiles)
UPDATE_CURL_RETRY       ?= 3
UPDATE_CURL_RETRY_DELAY ?= 2

# Fetch the latest GitHub release JSON for $$repo into $$RESP (uses $$GH_TOKEN if
# set) and leave a pass/fail verdict in $$FETCH_RC. Callers must check $$FETCH_RC
# before treating an empty/missing tag_name as a legitimate "no release" SKIP.
# HTTP status, not curl's own exit code, decides pass/fail here: curl -f alone
# turns every 4xx/5xx into the same exit code 22 -- verified empirically against
# the real API (401 "Bad credentials" and a real repo's 404 "no releases" both
# come back rc=22, indistinguishable from each other). `-o` to a temp file plus
# `-w '%{http_code}'` (rather than mixing the status into $$RESP via `-w
# '\nHTTPSTATUS:...'`) keeps -f's normal behavior (its own retry/error handling,
# and an empty body on a failed request instead of an error page) while still
# getting the real status code, and structurally avoids two problems an earlier
# version of this had: (1) a response body whose own last line happened to look
# like "HTTPSTATUS:<digits>" could be mistaken for the marker (grep -o matches
# every line, not just the last); (2) with -f removed, --retry-all-errors was
# retrying by re-sending the whole response (including failed attempts' error
# bodies) into the same $$RESP capture, which could prepend stale error-page
# text before the eventual successful body. -o writes each attempt to the same
# path fresh, so only the final attempt's body ends up in the file. Only 200 (a
# release exists) and 404 (repo has none, GitHub's documented response for
# that case) are treated as FETCH_RC=0, anything else (401/403/429/5xx/...) is
# a request failure.
# `-K -` (config from stdin), not `-H "Authorization: Bearer $$GH_TOKEN"`: the
# latter puts the token in curl's argv, visible to any other user on the same
# host via ps/procfs for the command's duration -- piped stdin never shows up
# in argv (same fix as git.mk's git/check).
define _gh_fetch_latest
		_FETCH_TMP=$$(mktemp); \
		if [ -z "$$_FETCH_TMP" ]; then \
			FETCH_RC=1; HTTP_STATUS=; RESP=; \
		else \
			if [ -n "$$GH_TOKEN" ]; then \
				HTTP_STATUS=$$(printf 'header = "Authorization: Bearer %s"\n' "$$GH_TOKEN" | curl -K - \
					--retry $(UPDATE_CURL_RETRY) \
					--retry-all-errors \
					--retry-delay $(UPDATE_CURL_RETRY_DELAY) \
					-fsSL \
					-o "$$_FETCH_TMP" \
					-w '%{http_code}' \
					"https://api.github.com/repos/$$repo/releases/latest" 2>/dev/null); \
			else \
				HTTP_STATUS=$$(curl \
					--retry $(UPDATE_CURL_RETRY) \
					--retry-all-errors \
					--retry-delay $(UPDATE_CURL_RETRY_DELAY) \
					-fsSL \
					-o "$$_FETCH_TMP" \
					-w '%{http_code}' \
					"https://api.github.com/repos/$$repo/releases/latest" 2>/dev/null); \
			fi; \
			RESP=$$(cat "$$_FETCH_TMP" 2>/dev/null); \
			rm -f "$$_FETCH_TMP"; \
			if [ "$$HTTP_STATUS" = "200" ] || [ "$$HTTP_STATUS" = "404" ]; then \
				FETCH_RC=0; \
			else \
				FETCH_RC=1; \
			fi; \
		fi
endef

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
# A GitHub token is fetched from `pass` (see variables.mk for why this happens
# at the shell level, not via a Make variable) when available, to avoid
# GitHub API rate limits.
# ─────────────────────────────────────────────────────────────────────────────

## Upgrade all locally-installed Go tools to their latest published versions.
## Currently: tmux-pane-info → github.com/kpango/dotfiles/tmux.conf.d/tmux-pane-info@latest
up: tmux/go/update

## Update all version pins (GitHub Actions, tools) and the nix flake.lock.
update: update/versions nix/update
	@echo ""
	@echo "==================================================="
	@echo " All versions updated."
	@echo " Review with: git diff"
	@echo "==================================================="

## update GitHub Actions pins + tool version strings (runs both sub-targets)
update/versions: update/versions/actions update/versions/tools

# ── GitHub Actions action versions ───────────────────────────────────────────
#
# Scans all .github/workflows/*.{yml,yaml} and .github/actions/**/*.{yml,yaml}
# files to discover every action and workflow reference, updates them to their
# latest releases/tags, and pins them to commit SHAs using pinact.
#
# Covers root actions (owner/repo@...), subdirectory actions (owner/repo/path@...),
# and external reusable workflows (owner/repo/.github/workflows/...@...).
# Preserves local relative paths (./...).
## scan .github/workflows and .github/actions for action and workflow references and update to latest versions
update/versions/actions:
	@echo "==================================================="
	@echo " update/versions/actions"
	@echo "==================================================="
	@if ! command -v pinact >/dev/null 2>&1; then \
		echo "pinact not found on PATH; installing via go install..."; \
		go install github.com/suzuki-shunsuke/pinact/cmd/pinact@latest || { \
			echo "ERROR: pinact is required but could not be installed. Please ensure Go is installed and on PATH." >&2; \
			exit 1; \
		}; \
	fi; \
	GITHUB_TOKEN="$${GITHUB_TOKEN:-$${GITHUB_ACCESS_TOKEN:-$$(gh auth token 2>/dev/null || pass github.api.ro.token 2>/dev/null || :)}}"; \
	export GITHUB_TOKEN; \
	DIRS=""; \
	[ -d "$(ROOTDIR)/.github/workflows" ] && DIRS="$$DIRS $(ROOTDIR)/.github/workflows"; \
	[ -d "$(ROOTDIR)/.github/actions" ] && DIRS="$$DIRS $(ROOTDIR)/.github/actions"; \
	if [ -z "$$DIRS" ]; then \
		echo "  No workflow or action directories found under $(ROOTDIR)/.github"; \
	else \
		TARGETS=$$(find $$DIRS -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort); \
		if [ -z "$$TARGETS" ]; then \
			echo "  No workflow or action files found under $(ROOTDIR)/.github"; \
		else \
			echo "$$TARGETS" | xargs pinact run -u || { \
				echo "  ERROR: pinact run -u failed. Check network or GitHub API token rate limits." >&2; \
				exit 1; \
			}; \
		fi; \
	fi
	@echo "  Done."

# ── Tool version strings in workflow files ────────────────────────────────────
#
# Each entry is "owner/repo|VAR_NAME" where VAR_NAME is the shell variable
# used in the workflow to hold the version (e.g. SHFMT_VER=v3.8.0).
# The full release tag is used (not major-only), since these are binary downloads.
#
# Pattern matched and replaced: VAR_NAME=v<semver>
## bump tool version env-vars (SHFMT_VER etc.) in workflow files to latest release
update/versions/tools:
	@echo "==================================================="
	@echo " update/versions/tools"
	@echo "==================================================="
	@GH_TOKEN="$${GITHUB_TOKEN:-$${GITHUB_ACCESS_TOKEN:-$$(gh auth token 2>/dev/null || pass github.api.ro.token 2>/dev/null || :)}}"; \
	FAILED=0; \
	for entry in \
		"mvdan/sh|SHFMT_VER" \
	; do \
		repo=$$(printf '%s' "$$entry" | cut -d'|' -f1); \
		var=$$(printf '%s' "$$entry" | cut -d'|' -f2); \
		$(call _gh_fetch_latest); \
		if [ "$$FETCH_RC" -ne 0 ]; then \
			printf "  WARNING: GitHub API request failed for %s (HTTP %s) — token invalid/rate-limited/network error?\n" "$$repo ($$var)" "$${HTTP_STATUS:-?}"; \
			FAILED=1; \
			continue; \
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
			| xargs $(SED_INPLACE) \
				"s/$${var}=v[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*/$${var}=$$TAG/g" \
			|| { printf "  WARNING: sed failed rewriting %s\n" "$$var"; FAILED=1; }; \
	done; \
	if [ "$$FAILED" -eq 1 ]; then \
		echo "  Done (with failures — some pins may not have been rewritten, see WARNING lines above)."; \
		exit 1; \
	fi
	@echo "  Done."
