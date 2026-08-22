# Design Specification: Antigravity CLI (agy) and Gemini CLI Configuration Alignment & Synchronization

**Date**: 2026-08-20  
**Author**: Gemini CLI Agent  
**Status**: Approved

## 1. Objective

Ensure that the next-generation Antigravity CLI (`agy`) is synchronized and configured with the exact same capabilities, custom settings, policies, active extensions, and skills as the current Gemini CLI environment.

## 2. Background & Problem Analysis

During system recon, we discovered:

1. **Broken Symlinks in `~/.gemini/`**: Since the repository directory was renamed from `gemini/` to `agy/`, the active symlinks in `~/.gemini/` are broken, pointing to non-existent paths inside the `dotfiles` workspace:
   - `~/.gemini/settings.json` -> `.../dotfiles/gemini/settings.json` (Broken)
   - `~/.gemini/policies/policy.toml` -> `.../dotfiles/gemini/policies/policy.toml` (Broken)
   - `~/.gemini/policies/rules.toml` -> `.../dotfiles/gemini/policies/policy.toml` (Broken)
2. **Makefile Line-Continuation Bug**: Redundant backslashes (`\`) are present in `Makefile.d/install.mk` inside `define DOTFILES_MAP`. This causes `make` to merge entries into a single malformed string, causing errors during installation.
3. **Separate Homes by Default**: `agy` and Gemini CLI look for configuration files in `~/.agy` and `~/.gemini` respectively. Since `~/.gemini` currently contains all superpowers extensions and credentials, `agy` is missing these assets by default.

## 3. Detailed Technical Design

### A. Makefile Syntax Correction

Surgically remove the trailing backslashes (`\`) on the lines mapping the `agy` config files in `Makefile.d/install.mk`.

**Before:**

```makefile
agy/policies/policy.toml .agy/policies/rules.toml \
agy/settings.json .agy/settings.json \
ghostty.conf .config/ghostty/config
```

**After:**

```makefile
agy/policies/policy.toml .agy/policies/rules.toml
agy/settings.json .agy/settings.json
ghostty.conf .config/ghostty/config
```

### B. Symlink Restoration in `~/.gemini`

Update the broken global symlinks for the regular user `kpango` to point to the newly named `agy/` directories in the repository:

- Re-create `~/.gemini/settings.json` pointing to `~/go/src/github.com/kpango/dotfiles/agy/settings.json`.
- Re-create `~/.gemini/policies/policy.toml` pointing to `~/go/src/github.com/kpango/dotfiles/agy/policies/policy.toml`.
- Re-create `~/.gemini/policies/rules.toml` pointing to `~/go/src/github.com/kpango/dotfiles/agy/policies/policy.toml`.

### C. Active Directory Synchronization (`~/.agy` ➡️ `~/.gemini`)

To fully align `agy` and Gemini CLI:

- Move or backup any existing `~/.agy` folder (if any).
- Create a symbolic link `~/.agy` pointing directly to `~/.gemini`.
- This ensures that both utilities read and write to the same folder, sharing all credentials (`gemini-credentials.json`), history, and installed extensions/skills seamlessly.

## 4. Verification Plan

1. **Verify Makefile**: Run `make -C ~/go/src/github.com/kpango/dotfiles/ -n dotfiles/install` to ensure no syntax/merging errors occur.
2. **Verify Symlinks**: Check that `~/.gemini/settings.json`, `~/.gemini/policies/policy.toml`, and `~/.gemini/policies/rules.toml` point to `agy/...` and are not broken.
3. **Verify Synchronized Environment**: Confirm `~/.agy` successfully links to `~/.gemini` and that running `agy --version` or executing `agy` works perfectly without configuration errors.
