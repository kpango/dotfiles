# Design: Centralized Tool Downloader (`Makefile.d/download.mk`)

**Date**: 2026-05-07
**Status**: Approved

## Problem

Multiple `dockers/*.Dockerfile` files contain duplicated, fragile inline shell
scripts that independently handle GitHub API version resolution, archive
downloading, extraction, and binary placement. This causes:

- GitHub API rate limit exhaustion (same repo queried N times per build)
- Inconsistent error handling across tools
- Poor Docker layer cache utilization (`COPY` of scripts invalidates downstream layers)
- High maintenance cost — adding a tool means copying and editing ~15 lines of boilerplate
- An existing `dockers/scripts/gh_release.sh` partial abstraction that is still
  a `.sh` file and still requires a bind-mount per Dockerfile stage

## Goal

Replace all inline curl/unzip boilerplate and `gh_release.sh` with a single
`Makefile.d/download.mk`. No external shell scripts. Dockerfiles mount the
`Makefile.d/` directory via BuildKit bind mount (zero layer cost) and invoke
`make install-tool` with per-tool parameters.

---

## Architecture Decisions

### A. Per-tool build stages are preserved

Each tool keeps its own `FROM ... AS <name>` stage. This preserves BuildKit's
parallel stage execution. Tools within a stage that have multiple binaries from
the same repo use `BINS='bin1 bin2'` in a single `make` invocation.

### B. `URL_TEMPLATE` override + parameterized grammar (not named presets)

Archive filenames follow a canonical 5-slot grammar (see Section 3). A small
set of orthogonal parameters covers ~85% of tools without needing
`URL_TEMPLATE`. For the remaining ~15%, `URL_TEMPLATE` is the escape hatch —
it accepts Make variable references (`$(VERSION)`, `$(OS)`, `$(ARCH)`, etc.)
expanded at parse time, plus `{BIN}` expanded per-iteration in the shell loop.

### C. `APP_NAME` as the single source of truth

`APP_NAME` is always the first parameter. `REPO`, `BIN`, `BINS`,
`URL_TEMPLATE`, `BIN_SUBDIR` all reference `$(APP_NAME)` so the tool name
appears exactly once per call site.

### D. HEAD-first adaptive download

Before every binary download, a `curl --head` probe retrieves
`Content-Length` and the final redirected URL in one round-trip. Connection
count scales with file size (1→2→4→8→16). `axel` is used for files ≥1 MB;
`curl` for smaller files and all API calls.

### E. No external shell scripts

`dockers/scripts/gh_release.sh` is deleted. Its two functions are replaced by
`get-version` and `get-stable-version` Make targets.

---

## Section 1: `Makefile.d/download.mk` Interface

### 1.1 Variable Interface

```makefile
# ── Root identity ─────────────────────────────────────────────────────────────
APP_NAME      ?=                         # canonical tool name — single source of truth

# ── Derived defaults (override when they differ from APP_NAME) ────────────────
REPO          ?= $(APP_NAME)/$(APP_NAME) # owner/repo; default org==name (dagger, pulumi…)
BIN           ?= $(APP_NAME)             # installed binary name
BINS          ?= $(BIN)                  # space-sep list for multi-binary stages

# ── Archive grammar parameters ────────────────────────────────────────────────
EXT           ?= .tar.gz    # .tar.gz | .tar.xz | .zip | (empty = raw binary)
SEP           ?= -          # primary separator: - or _
OS_ARCH_SEP   ?= $(SEP)     # OS→ARCH separator; override for fzf-style (- name/ver, _ os/arch)
VER_TAG       ?=            # v prefix in archive name: v for dagger/kubectx, empty for most
URL_VER_TAG   ?= v          # v prefix in URL release path: empty for istio/helix
VER_IN_NAME   ?= 1          # 0 = no version in archive name: k9s, k3d, kubebuilder, skaffold
INCLUDE_ARCH  ?= 1          # 0 = no arch in archive name: kubebox, kubectl-style
OS_ALIAS      ?= $(OS)      # $(OS_CAP) for k9s/kubefwd/conftest/helm-docs
ARCH_ALIAS    ?= $(ARCH)    # $(XARCH) | $(XARCH_PROTOC) | $(ARCH_X64) for arch variants

# ── URL override ──────────────────────────────────────────────────────────────
DL_BASE_URL   ?= $(GITHUB)/$(REPO)/$(RELEASE_DL)/$(URL_VER_TAG)$(VERSION)
                            # override for non-GitHub: helm.sh, GCS, etc.
URL_TEMPLATE  ?=            # full URL override; supports Make vars + {BIN} shell placeholder

# ── Binary location ───────────────────────────────────────────────────────────
BIN_SUBDIR    ?=            # subdir in archive containing binary; resolved as $(BIN_SUBDIR)/$(BIN)
                            # if empty: find -name $(BIN) -type f -perm /111

# ── Extra files (e.g. protoc headers) ────────────────────────────────────────
EXTRA_GLOB    ?=            # shell glob of paths to copy from extracted archive
EXTRA_DEST    ?= $(LOCAL)   # destination for EXTRA_GLOB files

# ── Post-install ──────────────────────────────────────────────────────────────
UPX           ?= 0          # 1 = compress installed binary with upx --best
DEST          ?= $(BIN_PATH) # install destination (default: /usr/local/bin via ENV)

# ── Version source ────────────────────────────────────────────────────────────
RELEASE_TYPE  ?= latest     # latest | stable (for linkerd-style stable-X.Y.Z tags)
VERSION_URL   ?=            # fetch version from arbitrary URL (for kubectl from GCS)
```

### 1.2 Archive Name Grammar

Every archive filename is composed from the same 5 slots:

```
{BIN} {SEP}{VER_TAG}{VERSION} {SEP}{OS_ALIAS} {OS_ARCH_SEP}{ARCH_ALIAS} {EXT}
  ①         ②  (opt)  ②           ③                  ④  (opt)  ④            ⑤
```

- Slot ② suppressed when `VER_IN_NAME=0`
- Slot ④ suppressed when `INCLUDE_ARCH=0`
- `URL_TEMPLATE` remains the escape hatch for truly irregular patterns

Makefile derivation:

```makefile
_VER_PART    := $(if $(filter 0,$(VER_IN_NAME)),,$(SEP)$(VER_TAG)$(VERSION))
_ARCH_PART   := $(if $(filter 0,$(INCLUDE_ARCH)),,$(OS_ARCH_SEP)$(ARCH_ALIAS))
_ARCHIVE     := $(BIN)$(_VER_PART)$(SEP)$(OS_ALIAS)$(_ARCH_PART)
_DEFAULT_URL := $(DL_BASE_URL)/$(_ARCHIVE)$(EXT)
_URL         := $(or $(URL_TEMPLATE),$(_DEFAULT_URL))
```

### 1.3 OS / Architecture Normalization

```makefile
_RAW_ARCH    := $(or $(TARGETARCH),$(ARCH),$(shell uname -m))
_RAW_OS      := $(or $(TARGETOS),$(OS),$(shell uname -s | tr '[:upper:]' '[:lower:]'))
ARCH         := $(subst x86_64,amd64,$(subst aarch64,arm64,$(_RAW_ARCH)))
OS           := $(_RAW_OS)

# Alias table — all usable in ARCH_ALIAS, OS_ALIAS, URL_TEMPLATE, BIN_SUBDIR
XARCH        := $(subst amd64,x86_64,$(subst arm64,aarch64,$(ARCH)))
XARCH_PROTOC := $(subst amd64,x86_64,$(subst arm64,aarch_64,$(ARCH)))
ARCH_X64     := $(subst amd64,x64,$(ARCH))
OS_CAP       := $(shell printf '%s' '$(OS)' | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')
```

### 1.4 Memoized Version Fetch

```makefile
_REPO_KEY := $(subst -,_,$(subst /,_,$(REPO)))

# Latest release (default)
$(if $(filter undefined,$(origin _VER_$(_REPO_KEY))),$(eval _VER_$(_REPO_KEY) := $(shell \
    GAT=$$(cat /run/secrets/gat 2>/dev/null || true); \
    if [ -n "$$GAT" ]; then \
        $(_CURL) -H "Authorization: Bearer $$GAT" \
            "$(API_GITHUB)/$(REPO)/$(RELEASE_LATEST)" 2>/dev/null \
        || $(_CURL) "$(API_GITHUB)/$(REPO)/$(RELEASE_LATEST)"; \
    else \
        $(_CURL) "$(API_GITHUB)/$(REPO)/$(RELEASE_LATEST)"; \
    fi | jq -r '.tag_name // empty' | sed 's/^v//'\
)))

# Stable release (only fetched when RELEASE_TYPE=stable)
$(if $(filter stable,$(RELEASE_TYPE)),\
  $(if $(filter undefined,$(origin _STABLE_$(_REPO_KEY))),$(eval _STABLE_$(_REPO_KEY) := $(shell \
    GAT=$$(cat /run/secrets/gat 2>/dev/null || true); \
    if [ -n "$$GAT" ]; then \
        $(_CURL) -H "Authorization: Bearer $$GAT" \
            "$(API_GITHUB)/$(REPO)/releases?per_page=100" 2>/dev/null \
        || $(_CURL) "$(API_GITHUB)/$(REPO)/releases?per_page=100"; \
    else \
        $(_CURL) "$(API_GITHUB)/$(REPO)/releases?per_page=100"; \
    fi | jq -r '[.[] | select(.tag_name | startswith("stable"))][0].tag_name // empty' \
       | sed 's/^stable-//'\
  ))\
)

# VERSION_URL path (arbitrary source — kubectl, etc.)
$(if $(VERSION_URL),\
  $(eval VERSION := $(shell $(_CURL) '$(VERSION_URL)' | tr -d '[:space:]' | sed 's/^v//'))\
,\
  $(eval VERSION := $(if $(filter stable,$(RELEASE_TYPE)),$(_STABLE_$(_REPO_KEY)),$(_VER_$(_REPO_KEY))))\
)

ifeq ($(strip $(VERSION)),)
$(error [download.mk] Empty version for REPO=$(REPO). Check network / GitHub API.)
endif
ifeq ($(VERSION),null)
$(error [download.mk] Null version for REPO=$(REPO). GitHub API returned null.)
endif
```

**Rationale**: `$(if $(filter undefined,$(origin ...)))` checks whether the
version was already fetched in this Make session. For `BINS='kubectx kubens'`
(two binaries, same repo), the GitHub API is called exactly once. The `$(eval)`
writes the result into the Make session immediately; subsequent references hit
the cache.

### 1.5 `curl` / `axel` Configuration

```makefile
CURL_RETRY       ?= 5
CURL_RETRY_DELAY ?= 3
_CURL = curl --compressed --retry $(CURL_RETRY) --retry-connrefused \
             --retry-delay $(CURL_RETRY_DELAY) -fsSL
```

`_CURL` is used exclusively for lightweight API calls. Binary downloads use the
HEAD-first adaptive strategy (see §1.6).

### 1.6 `install-tool` Recipe — HEAD-First Adaptive Download

```makefile
.PHONY: install-tool

install-tool:
	@[ -n '$(APP_NAME)' ] \
		|| { printf 'Error: APP_NAME is required\n' >&2; exit 1; }
	@set -euo pipefail; \
	_TMPDIR="$$(mktemp -d)"; \
	trap 'rm -rf "$$_TMPDIR"' EXIT; \
	cd "$$_TMPDIR"; \
	for _BIN in $(BINS); do \
	  _URL_ITER="$$(printf '%s' '$(_URL)' | sed "s|{BIN}|$$_BIN|g")"; \
	  \
	  printf '[download.mk] %s v$(VERSION) — probing %s\n' "$$_BIN" "$$_URL_ITER"; \
	  _META="$$(curl -fsS --head -L --max-time 10 \
	              --retry 2 --retry-connrefused --retry-delay 1 \
	              -D /dev/null -o /dev/null \
	              -w '%{content_length}|%{url_effective}' \
	              "$$_URL_ITER" 2>/dev/null || true)"; \
	  _FILE_SIZE="$$(printf '%s' "$$_META" | cut -d'|' -f1)"; \
	  _FINAL_URL="$$(printf '%s' "$$_META" | cut -d'|' -f2-)"; \
	  [ -n "$$_FINAL_URL" ] && _DL_URL="$$_FINAL_URL" || _DL_URL="$$_URL_ITER"; \
	  \
	  _N=1; \
	  if [ -n "$$_FILE_SIZE" ] && [ "$$_FILE_SIZE" -gt 0 ] 2>/dev/null; then \
	    _MB=$$(( _FILE_SIZE / 1048576 )); \
	    printf '[download.mk] size=%dMB ' "$$_MB"; \
	    if   [ "$$_MB" -ge 50 ]; then _N=16; \
	    elif [ "$$_MB" -ge 20 ]; then _N=8; \
	    elif [ "$$_MB" -ge 5  ]; then _N=4; \
	    elif [ "$$_MB" -ge 1  ]; then _N=2; \
	    fi; \
	  fi; \
	  printf 'connections=%d\n' "$$_N"; \
	  \
	  if [ -n '$(EXT)' ]; then \
	    if command -v axel >/dev/null 2>&1 && [ "$$_N" -gt 1 ]; then \
	      axel -n "$$_N" -q -o "dl$(EXT)" "$$_DL_URL"; \
	    else \
	      $(_CURL) -o "dl$(EXT)" "$$_DL_URL"; \
	    fi; \
	    case '$(EXT)' in \
	      .tar.gz|.tgz) tar -xzf "dl$(EXT)" ;; \
	      .tar.xz)      tar -xJf "dl$(EXT)" ;; \
	      .zip)         unzip -q  "dl$(EXT)" ;; \
	    esac; \
	    rm -f "dl$(EXT)"; \
	    if [ -n '$(BIN_SUBDIR)' ]; then \
	      _SRC='$(BIN_SUBDIR)'/$$_BIN; \
	    else \
	      _SRC="$$(find . -name "$$_BIN" -type f -perm /111 | head -1)"; \
	      [ -n "$$_SRC" ] \
	        || { printf 'Error: %s not found in archive\n' "$$_BIN" >&2; exit 1; }; \
	    fi; \
	    install -m 755 "$$_SRC" '$(DEST)'/; \
	    $(if $(EXTRA_GLOB),cp -r $(EXTRA_GLOB) '$(EXTRA_DEST)'/;) \
	    find . -mindepth 1 -delete; \
	  else \
	    if command -v axel >/dev/null 2>&1 && [ "$$_N" -gt 1 ]; then \
	      axel -n "$$_N" -q -o '$(DEST)'/$$_BIN "$$_DL_URL"; \
	    else \
	      $(_CURL) -o '$(DEST)'/$$_BIN "$$_DL_URL"; \
	    fi; \
	    chmod 755 '$(DEST)'/$$_BIN; \
	  fi; \
	  $(if $(filter 1,$(UPX)),upx --best '$(DEST)'/$$_BIN 2>/dev/null || true;) \
	  printf '[download.mk] installed: %s -> $(DEST)\n' "$$_BIN"; \
	done
```

**HEAD probe rationale**:

- `-D /dev/null -o /dev/null -w '%{content_length}|%{url_effective}'` — one
  request returns both file size and the final CDN URL after all redirects
- `_DL_URL` is the resolved CDN URL passed directly to axel — axel skips its
  own redirect chain
- `_FILE_SIZE -gt 0` guards handle `-1` (chunked, no Content-Length) and empty
  (HEAD not supported) gracefully, falling back to `_N=1`
- `$(if $(filter 1,$(UPX)),...)` — Make-level conditional; zero shell overhead
  when UPX is disabled

### 1.7 Version-Probe Targets (replacing `gh_release.sh`)

```makefile
.PHONY: get-version get-stable-version

# Replaces: . /tmp/gh_release.sh && VERSION=$(gh_latest_version "$REPO")
# Usage:    VERSION=$(make --no-print-directory -f /mk/download.mk get-version REPO=owner/repo)
get-version:
	@[ -n '$(REPO)$(VERSION_URL)' ] \
		|| { printf 'Error: REPO or VERSION_URL is required\n' >&2; exit 1; }
	@[ -n '$(VERSION)' ] \
		|| { printf 'Error: could not resolve version for $(REPO)\n' >&2; exit 1; }
	@printf '%s\n' '$(VERSION)'

# Replaces: . /tmp/gh_release.sh && VERSION=$(gh_stable_version "$REPO")
# Usage:    VERSION=$(make --no-print-directory -f /mk/download.mk get-stable-version REPO=owner/repo)
get-stable-version:
	@[ -n '$(REPO)' ] \
		|| { printf 'Error: REPO is required\n' >&2; exit 1; }
	@[ -n '$(VERSION)' ] \
		|| { printf 'Error: could not resolve stable version for $(REPO)\n' >&2; exit 1; }
	@printf '%s\n' '$(VERSION)'
```

`get-stable-version` is identical to `get-version` at the target level — the
difference is that the caller passes `RELEASE_TYPE=stable`, which triggers the
stable-version fetch at parse time. Internally the same `$(VERSION)` variable
is used throughout.

---

## Section 2: Dockerfile Refactoring

### 2.1 Bind Mount Pattern

```dockerfile
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=<name> [parameters...]
```

**Why `/mk` not `/tmp/Makefile.d`**: avoids conflict with
`--mount=type=tmpfs,target=/tmp` used in some stages.

**Why `--no-print-directory`**: suppresses Make's `Entering/Leaving directory`
noise — critical when using `$(make get-version ...)` in a shell `$()` subshell.

### 2.2 Call-Site Patterns by Category

#### Zero extra parameters (org == name, default archive pattern)

```dockerfile
FROM go-base AS dagger
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=dagger SEP=_ VER_TAG=v DEST=$(GOBIN) UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/$(APP_NAME)_v$(VERSION)_$(OS)_$(ARCH).tar.gz'
```

#### Default archive pattern — no URL_TEMPLATE needed

```dockerfile
# golangci-lint: default pattern covers it exactly
FROM go-base AS golangci-lint
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=golangci-lint REPO='golangci/$(APP_NAME)' DEST=$(GOBIN) UPX=1
```

#### SEP / OS_ARCH_SEP / ARCH_ALIAS override

```dockerfile
FROM go-base AS fzf
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=fzf REPO='junegunn/$(APP_NAME)' OS_ARCH_SEP=_ DEST=$(GOBIN)

FROM go-base AS pulumi
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=pulumi DEST=$(GOBIN) UPX=1 VER_TAG=v \
        ARCH_ALIAS='$(ARCH_X64)' BIN_SUBDIR='$(APP_NAME)'
```

#### Capitalized OS / x86_64 arch (VER_IN_NAME=0)

```dockerfile
FROM k8s-base AS k9s
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=k9s REPO='derailed/$(APP_NAME)' \
        SEP=_ VER_IN_NAME=0 OS_ALIAS='$(OS_CAP)' UPX=1

FROM k8s-base AS kubefwd
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubefwd REPO='txn2/$(APP_NAME)' \
        SEP=_ VER_IN_NAME=0 OS_ALIAS='$(OS_CAP)' ARCH_ALIAS='$(XARCH)' UPX=1
```

#### Multi-binary, same repo (`BINS` + `{BIN}` placeholder)

```dockerfile
FROM k8s-base AS kubectx
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubectx REPO='ahmetb/$(APP_NAME)' \
        BINS='$(APP_NAME) kubens' SEP=_ VER_TAG=v \
        ARCH_ALIAS='$(XARCH)' UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/{BIN}_v$(VERSION)_$(OS)_$(XARCH).tar.gz'
```

#### Extra files alongside binary (`EXTRA_GLOB`)

```dockerfile
FROM tools-base AS protoc
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=protoc REPO=protocolbuffers/protobuf EXT=.zip \
        ARCH_ALIAS='$(XARCH_PROTOC)' BIN_SUBDIR=bin \
        EXTRA_GLOB='include/*' EXTRA_DEST=$(LOCAL)
```

#### Non-GitHub base URL (`DL_BASE_URL`)

```dockerfile
FROM k8s-base AS helm
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=helm REPO='helm/$(APP_NAME)' VER_TAG=v \
        DL_BASE_URL='https://get.helm.sh' BIN_SUBDIR='$(OS)-$(ARCH)' UPX=1

FROM k8s-base AS skaffold
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=skaffold REPO='GoogleContainerTools/$(APP_NAME)' \
        DL_BASE_URL='$(GOOGLE)/skaffold/releases' VER_IN_NAME=0 UPX=1
```

#### Version from external URL (`VERSION_URL`)

```dockerfile
FROM k8s-base AS kubectl
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kubectl \
        VERSION_URL='$(GOOGLE)/kubernetes-release/release/stable.txt' \
        DL_BASE_URL='$(GOOGLE)/kubernetes-release/release/v$(VERSION)/bin/$(OS)/$(ARCH)' \
        VER_IN_NAME=0 INCLUDE_ARCH=0
```

#### Stable release tags (`RELEASE_TYPE=stable`)

```dockerfile
FROM k8s-base AS linkerd
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=linkerd REPO=linkerd/linkerd2 RELEASE_TYPE=stable UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/stable-$(VERSION)/linkerd2-cli-stable-$(VERSION)-$(OS)-$(ARCH)'
```

#### No v-prefix in URL path (`URL_VER_TAG=`)

```dockerfile
FROM k8s-base AS istio
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=istio BIN=istioctl REPO='istio/$(APP_NAME)' URL_VER_TAG= UPX=1
```

#### Post-install shell step (kube-linter dual-name)

```dockerfile
FROM k8s-base AS kube-linter
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=kube-linter REPO='stackrox/$(APP_NAME)' UPX=1 \
        URL_TEMPLATE='$(GITHUB)/$(REPO)/$(RELEASE_DL)/v$(VERSION)/$(APP_NAME)-$(OS)$(if $(filter arm64,$(ARCH)),_arm64,).tar.gz' \
    && cp $(BIN_PATH)/kube-linter $(BIN_PATH)/kubectl-lint
```

### 2.3 `gh_release.sh` Migration Pattern

Before:

```dockerfile
RUN --mount=type=bind,source=dockers/scripts/gh_release.sh,target=/tmp/gh_release.sh,ro \
    --mount=type=secret,id=gat \
    set -x && REPO="helm/helm" \
    && . /tmp/gh_release.sh && VERSION=$(gh_latest_version "${REPO}") \
    && ...build URL manually...
```

After:

```dockerfile
RUN --mount=type=bind,source=Makefile.d,target=/mk,ro \
    --mount=type=secret,id=gat \
    make --no-print-directory -f /mk/download.mk install-tool \
        APP_NAME=helm REPO='helm/$(APP_NAME)' ...
```

For stages that still need version resolution in shell (edge cases):

```bash
VERSION=$(make --no-print-directory -f /mk/download.mk get-version REPO=owner/repo)
VERSION=$(make --no-print-directory -f /mk/download.mk get-stable-version REPO=linkerd/linkerd2)
```

---

## Section 3: Parameter Coverage Table

| Tool               | Params beyond APP_NAME                                                                                      | URL_TEMPLATE?                               |
| ------------------ | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------- |
| `golangci-lint`    | `REPO='golangci/$(APP_NAME)'`                                                                               | No — default pattern                        |
| `stern`            | `SEP=_`                                                                                                     | No                                          |
| `gh`               | `REPO=cli/cli SEP=_`                                                                                        | No                                          |
| `fzf`              | `REPO='junegunn/$(APP_NAME)' OS_ARCH_SEP=_`                                                                 | No                                          |
| `dagger`           | `SEP=_ VER_TAG=v`                                                                                           | No                                          |
| `kubectl-tree`     | `REPO='ahmetb/$(APP_NAME)' SEP=_ VER_TAG=v`                                                                 | No                                          |
| `pulumi`           | `VER_TAG=v ARCH_ALIAS='$(ARCH_X64)' BIN_SUBDIR='$(APP_NAME)'`                                               | No                                          |
| `tinygo`           | —                                                                                                           | Yes — no separator between name and version |
| `k9s`              | `REPO='derailed/$(APP_NAME)' SEP=_ VER_IN_NAME=0 OS_ALIAS='$(OS_CAP)'`                                      | No                                          |
| `kubefwd`          | `REPO='txn2/$(APP_NAME)' SEP=_ VER_IN_NAME=0 OS_ALIAS='$(OS_CAP)' ARCH_ALIAS='$(XARCH)'`                    | No                                          |
| `conftest`         | `SEP=_ OS_ALIAS='$(OS_CAP)' ARCH_ALIAS='$(XARCH)'`                                                          | No                                          |
| `helm-docs`        | `SEP=_ OS_ALIAS='$(OS_CAP)' ARCH_ALIAS='$(XARCH)'`                                                          | No                                          |
| `k3d`              | `REPO='k3d-io/$(APP_NAME)' VER_IN_NAME=0`                                                                   | No                                          |
| `telepresence`     | `REPO='telepresenceio/$(APP_NAME)' VER_IN_NAME=0`                                                           | No                                          |
| `kubebuilder`      | `REPO='kubernetes-sigs/$(APP_NAME)' SEP=_ VER_IN_NAME=0`                                                    | No                                          |
| `protoc`           | `REPO=protocolbuffers/protobuf EXT=.zip ARCH_ALIAS='$(XARCH_PROTOC)' BIN_SUBDIR=bin EXTRA_GLOB='include/*'` | No                                          |
| `helm`             | `DL_BASE_URL='https://get.helm.sh' VER_TAG=v BIN_SUBDIR='$(OS)-$(ARCH)'`                                    | No                                          |
| `skaffold`         | `DL_BASE_URL='$(GOOGLE)/skaffold/releases' VER_IN_NAME=0`                                                   | No                                          |
| `kubectl`          | `VERSION_URL=... DL_BASE_URL=... VER_IN_NAME=0 INCLUDE_ARCH=0`                                              | No                                          |
| `istio`            | `BIN=istioctl REPO='istio/$(APP_NAME)' URL_VER_TAG=`                                                        | No                                          |
| `kubectl-gadget`   | —                                                                                                           | Yes — version appears after OS-ARCH         |
| `linkerd`          | `RELEASE_TYPE=stable`                                                                                       | Yes — stable-prefix URL structure           |
| `kube-linter`      | —                                                                                                           | Yes — conditional `_arm64` suffix           |
| `kubectx`+`kubens` | `BINS='$(APP_NAME) kubens' SEP=_ VER_TAG=v ARCH_ALIAS='$(XARCH)'`                                           | Yes — {BIN} in archive name                 |

**Result**: `URL_TEMPLATE` required for only 4 tools with truly irregular patterns.

---

## Section 4: Migration Checklist

| File                            | Action                                                                                          |
| ------------------------------- | ----------------------------------------------------------------------------------------------- |
| `Makefile.d/download.mk`        | **Create**                                                                                      |
| `dockers/tools.Dockerfile`      | Refactor `protoc` stage                                                                         |
| `dockers/go.Dockerfile`         | Refactor `dagger`, `fzf`, `gh`, `golangci-lint`, `pulumi`, `tinygo` stages                      |
| `dockers/k8s.Dockerfile`        | Refactor all tool stages                                                                        |
| `dockers/docker.Dockerfile`     | Refactor `buildx`, credential helpers, `containerd`, `slim`, `dockfmt`, `docker-compose` stages |
| `dockers/scripts/gh_release.sh` | **Delete** — superseded by `get-version` / `get-stable-version` targets                         |
