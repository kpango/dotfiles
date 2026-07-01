# Pinentry Makefile Protocol Alignment Design

## Overview

This design aligns the `pinentry-tmux` build and installation protocol within `Makefile.d/install.mk` to mirror the robust, cross-platform approach used by `tmux-pane-info`.

## Architecture & Changes

### 1. Robust Go Resolution (`pinentry/install`)

**Current:**
Hardcoded `GOROOT=$(shell dirname $$(dirname $$(realpath $$(command -v go))))` which is brittle across different environments.
**Design:**
Adopt the `$(FIND_GO)` macro used by `tmux/go/install`.

- If Go is found (`[ -n "$$_go" ]`), compile the local source code with `GOEXPERIMENT=runtimesecret`, then `sudo install` it to `/usr/local/bin/pinentry-tmux`.
- If Go is not found, emit a clear error message and `exit 1` (since there is no zsh fallback for pinentry like there is for tmux-pane-info).

### 2. Remote Update Target (`pinentry/update`)

**Current:**
No target exists to update `pinentry-tmux` from the remote repository without a local clone.
**Design:**
Create `pinentry/update` mirroring `tmux/go/update`.

- Use `$(FIND_GO)`.
- If Go is found, run `go build` targeting `github.com/kpango/dotfiles/pinentry/tmux@latest` with `GOEXPERIMENT=runtimesecret`.
- `sudo install` the resulting binary to `/usr/local/bin/pinentry-tmux`.

## Spec Self-Review

- **Placeholders:** None.
- **Consistency:** Accurately reflects the discussed design matching the `tmux-pane-info` behavior.
- **Scope:** Narrowly focused on updating two Makefile targets.
