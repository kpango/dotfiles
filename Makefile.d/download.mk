.PHONY: install-tool get-version get-stable-version

# ── OS / arch normalization ────────────────────────────────────────────────────
_RAW_ARCH    := $(or $(TARGETARCH),$(ARCH),$(shell uname -m))
_RAW_OS      := $(or $(TARGETOS),$(OS),$(shell uname -s | tr '[:upper:]' '[:lower:]'))
ARCH         := $(subst x86_64,amd64,$(subst aarch64,arm64,$(_RAW_ARCH)))
OS           := $(_RAW_OS)

XARCH        := $(subst amd64,x86_64,$(subst arm64,aarch64,$(ARCH)))
XARCH_PROTOC := $(subst amd64,x86_64,$(subst arm64,aarch_64,$(ARCH)))
ARCH_X64     := $(subst amd64,x64,$(ARCH))
# x86_64 for amd64, arm64 unchanged — for Go tools that use Linux native naming on x86 but Docker naming on ARM
ARCH_X86     := $(subst amd64,x86_64,$(ARCH))
OS_CAP       := $(shell printf '%s' '$(OS)' | awk '{print toupper(substr($$0,1,1)) substr($$0,2)}')

# ── Well-known base URLs (match base.Dockerfile ENV) ──────────────────────────
GITHUB       ?= https://github.com
API_GITHUB   ?= https://api.github.com/repos
GOOGLE       ?= https://storage.googleapis.com
RELEASE_DL   ?= releases/download
RELEASE_LATEST ?= releases/latest
BIN_PATH     ?= /usr/local/bin
LOCAL        ?= /usr/local

# ── curl configuration ────────────────────────────────────────────────────────
CURL_RETRY       ?= 5
CURL_RETRY_DELAY ?= 3
_CURL = curl --compressed --retry $(CURL_RETRY) --retry-connrefused \
             --retry-delay $(CURL_RETRY_DELAY) -fsSL

# ── Root identity ─────────────────────────────────────────────────────────────
APP_NAME      ?=

# ── Derived defaults ──────────────────────────────────────────────────────────
REPO          ?= $(APP_NAME)/$(APP_NAME)
BIN           ?= $(APP_NAME)
BINS          ?= $(BIN)

# ── Archive grammar ───────────────────────────────────────────────────────────
EXT           ?= .tar.gz
SEP           ?= -
OS_ARCH_SEP   ?= $(SEP)
VER_TAG       ?=
URL_VER_TAG   ?= v
VER_IN_NAME   ?= 1
INCLUDE_ARCH  ?= 1
OS_ALIAS      ?= $(OS)
ARCH_ALIAS    ?= $(ARCH)

# ── URL override ──────────────────────────────────────────────────────────────
DL_BASE_URL   ?= $(GITHUB)/$(REPO)/$(RELEASE_DL)/$(URL_VER_TAG)$(VERSION)
URL_TEMPLATE  ?=

# ── Binary location ───────────────────────────────────────────────────────────
BIN_SUBDIR    ?=

# ── Extra files ───────────────────────────────────────────────────────────────
EXTRA_GLOB    ?=
EXTRA_DEST    ?= $(LOCAL)

# ── Post-install ──────────────────────────────────────────────────────────────
UPX           ?= 0
DEST          ?= $(BIN_PATH)

# ── Version source ────────────────────────────────────────────────────────────
RELEASE_TYPE  ?= latest
VERSION_URL   ?=

# ── Memoized version fetch ────────────────────────────────────────────────────
_REPO_KEY := $(subst -,_,$(subst /,_,$(REPO)))

$(if $(VERSION_URL),,\
  $(if $(filter undefined,$(origin _VER_$(_REPO_KEY))),$(eval _VER_$(_REPO_KEY) := $(shell \
    GAT=$$(cat /run/secrets/gat 2>/dev/null || true); \
    if [ -n "$$GAT" ]; then \
        $(_CURL) -H "Authorization: Bearer $$GAT" \
            "$(API_GITHUB)/$(REPO)/$(RELEASE_LATEST)" 2>/dev/null \
        || $(_CURL) "$(API_GITHUB)/$(REPO)/$(RELEASE_LATEST)"; \
    else \
        $(_CURL) "$(API_GITHUB)/$(REPO)/$(RELEASE_LATEST)"; \
    fi | jq -r '.tag_name // empty' | sed 's/^v//'\
  )))\
)

$(if $(VERSION_URL),,\
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
    )))\
  )\
)

$(if $(VERSION_URL),\
  $(eval VERSION := $(shell $(_CURL) '$(VERSION_URL)' | tr -d '[:space:]' | sed 's/^v//'))\
,\
  $(eval VERSION := $(if $(filter stable,$(RELEASE_TYPE)),$(_STABLE_$(_REPO_KEY)),$(_VER_$(_REPO_KEY))))\
)

ifeq ($(strip $(VERSION)),)
$(if $(or $(REPO),$(VERSION_URL)),$(error [download.mk] Empty version for REPO=$(REPO). Check network / GitHub API.))
endif
ifeq ($(VERSION),null)
$(error [download.mk] Null version for REPO=$(REPO). GitHub API returned null.)
endif

# ── Archive name derivation ───────────────────────────────────────────────────
_VER_PART    := $(if $(filter 0,$(VER_IN_NAME)),,$(SEP)$(VER_TAG)$(VERSION))
_ARCH_PART   := $(if $(filter 0,$(INCLUDE_ARCH)),,$(OS_ARCH_SEP)$(ARCH_ALIAS))
_ARCHIVE     := $(BIN)$(_VER_PART)$(SEP)$(OS_ALIAS)$(_ARCH_PART)
_DEFAULT_URL := $(DL_BASE_URL)/$(_ARCHIVE)$(EXT)
_URL         := $(or $(URL_TEMPLATE),$(_DEFAULT_URL))

# ── Targets ───────────────────────────────────────────────────────────────────

install-tool:
	@[ -n '$(APP_NAME)' ] \
		|| { printf '[download.mk] Error: APP_NAME is required\n' >&2; exit 1; }
	@set -euo pipefail; \
	_TMPDIR="$$(mktemp -d)"; \
	trap 'rm -rf "$$_TMPDIR"' EXIT; \
	cd "$$_TMPDIR"; \
	_dl_probe() { \
	  _url="$$1"; _out="$$2"; \
	  printf '[download.mk] probing %s\n' "$$_url"; \
	  _META="$$(curl -fsS --head -L --max-time 10 \
	              --retry 2 --retry-connrefused --retry-delay 1 \
	              -D /dev/null -o /dev/null \
	              -w '%{content_length}|%{url_effective}' \
	              "$$_url" 2>/dev/null || true)"; \
	  _FILE_SIZE="$$(printf '%s' "$$_META" | cut -d'|' -f1)"; \
	  _FINAL_URL="$$(printf '%s' "$$_META" | cut -d'|' -f2-)"; \
	  [ -n "$$_FINAL_URL" ] && _DL_URL="$$_FINAL_URL" || _DL_URL="$$_url"; \
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
	  if command -v axel >/dev/null 2>&1 && [ "$$_N" -gt 1 ]; then \
	    axel -n "$$_N" -q -o "$$_out" "$$_DL_URL"; \
	  else \
	    $(_CURL) -o "$$_out" "$$_DL_URL"; \
	  fi; \
	}; \
	_install_bins() { \
	  for _BIN in $$@; do \
	    if [ -n '$(BIN_SUBDIR)' ]; then \
	      _SRC='$(BIN_SUBDIR)'/$$_BIN; \
	    else \
	      _SRC="$$(find . -name "$$_BIN" -type f -perm /111 | head -1)"; \
	      [ -n "$$_SRC" ] \
	        || { printf '[download.mk] Error: %s not found\n' "$$_BIN" >&2; exit 1; }; \
	    fi; \
	    install -m 755 "$$_SRC" '$(DEST)'/; \
	    $(if $(filter 1,$(UPX)),upx --best '$(DEST)'/$$_BIN 2>/dev/null || true;) \
	    printf '[download.mk] installed: %s -> $(DEST)\n' "$$_BIN"; \
	  done; \
	  $(if $(EXTRA_GLOB),mkdir -p '$(EXTRA_DEST)' && cp -r $(EXTRA_GLOB) '$(EXTRA_DEST)'/;) \
	}; \
	_is_archive=0; \
	case '$(EXT)' in .tar.gz|.tgz|.tar.xz|.zip) _is_archive=1 ;; esac; \
	_per_bin=$$(printf '%s' '$(_URL)' | grep -cF '{BIN}' || true); \
	if [ "$$_is_archive" -eq 1 ] && [ "$$_per_bin" -eq 0 ]; then \
	  _dl_probe '$(_URL)' 'dl$(EXT)'; \
	  case '$(EXT)' in \
	    .tar.gz|.tgz) tar -xzf 'dl$(EXT)' ;; \
	    .tar.xz)      tar -xJf 'dl$(EXT)' ;; \
	    .zip)         unzip -q  'dl$(EXT)' ;; \
	  esac; \
	  rm -f 'dl$(EXT)'; \
	  _install_bins $(BINS); \
	else \
	  for _BIN in $(BINS); do \
	    _URL_ITER="$$(printf '%s' '$(_URL)' | sed "s|{BIN}|$$_BIN|g")"; \
	    case '$(EXT)' in \
	      .gz) \
	        _dl_probe "$$_URL_ITER" "$$_BIN.gz"; \
	        gzip -dc "$$_BIN.gz" > "$$_BIN"; \
	        install -m 755 "$$_BIN" '$(DEST)'/; \
	        $(if $(filter 1,$(UPX)),upx --best '$(DEST)'/$$_BIN 2>/dev/null || true;) \
	        printf '[download.mk] installed: %s -> $(DEST)\n' "$$_BIN"; \
	        ;; \
	      .tar.gz|.tgz|.tar.xz|.zip) \
	        _dl_probe "$$_URL_ITER" "dl$(EXT)"; \
	        case '$(EXT)' in \
	          .tar.gz|.tgz) tar -xzf 'dl$(EXT)' ;; \
	          .tar.xz)      tar -xJf 'dl$(EXT)' ;; \
	          .zip)         unzip -q  'dl$(EXT)' ;; \
	        esac; \
	        rm -f 'dl$(EXT)'; \
	        _install_bins "$$_BIN"; \
	        ;; \
	      *) \
	        _dl_probe "$$_URL_ITER" '$(DEST)'/$$_BIN; \
	        chmod 755 '$(DEST)'/$$_BIN; \
	        $(if $(filter 1,$(UPX)),upx --best '$(DEST)'/$$_BIN 2>/dev/null || true;) \
	        printf '[download.mk] installed: %s -> $(DEST)\n' "$$_BIN"; \
	        ;; \
	    esac; \
	    find . -mindepth 1 -delete 2>/dev/null || true; \
	  done; \
	fi

get-version:
	@[ -n '$(REPO)$(VERSION_URL)' ] \
		|| { printf '[download.mk] Error: REPO or VERSION_URL is required\n' >&2; exit 1; }
	@[ -n '$(VERSION)' ] \
		|| { printf '[download.mk] Error: could not resolve version for $(REPO)\n' >&2; exit 1; }
	@printf '%s\n' '$(VERSION)'

get-stable-version:
	@[ -n '$(REPO)' ] \
		|| { printf '[download.mk] Error: REPO is required\n' >&2; exit 1; }
	@[ -n '$(VERSION)' ] \
		|| { printf '[download.mk] Error: could not resolve stable version for $(REPO)\n' >&2; exit 1; }
	@printf '%s\n' '$(VERSION)'
