# prmt Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace starship with prmt for a ~1ms shell prompt that preserves the 3-line visual style.

**Architecture:** Four independent changes — new Nix derivation, package wiring, sheldon plugin swap, and starship.toml deployment cleanup. The sheldon plugin replaces the entire `_zcache_eval` + `zsh-defer` starship pattern with a simple prmt invocation guarded by precmd hooks for datetime, duration, and exit code capture (all zsh builtins, zero subprocesses).

**Tech Stack:** Nix (`rustPlatform.buildRustPackage`), sheldon (zsh plugin manager), zsh builtins (`zsh/datetime`, `$EPOCHREALTIME`, `strftime`)

---

### Task 1: Create nix/pkgs/prmt.nix

**Files:**

- Create: `nix/pkgs/prmt.nix`

prmt v0.5.0 is not in nixpkgs. `nix/pkgs/` already exists (has `default.nix`). Create a new file alongside it.

- [ ] **Step 1: Create the derivation with placeholder hashes**

```bash
cat > nix/pkgs/prmt.nix << 'EOF'
{ rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "prmt";
  version = "0.5.0";
  src = fetchFromGitHub {
    owner = "3axap4eHko";
    repo = "prmt";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  buildFeatures = [ "git-gix" ];
}
EOF
```

- [ ] **Step 2: Get the correct source hash**

```bash
nix build --impure --expr '(import <nixpkgs> {}).callPackage ./nix/pkgs/prmt.nix {}' 2>&1 | grep "got:"
```

Expected output contains a line like:

```
         got:    sha256-AbCdEf...
```

Copy that `sha256-...` value.

- [ ] **Step 3: Update hash in prmt.nix**

Replace the placeholder source hash with the value from Step 2:

```bash
# Replace the placeholder — use the actual hash from Step 2's output
sed -i 's|hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";|hash = "sha256-REPLACE_WITH_ACTUAL_HASH";|' nix/pkgs/prmt.nix
```

- [ ] **Step 4: Get the correct cargoHash**

```bash
nix build --impure --expr '(import <nixpkgs> {}).callPackage ./nix/pkgs/prmt.nix {}' 2>&1 | grep "got:"
```

This time the error is about cargoHash. Copy the `sha256-...` value.

- [ ] **Step 5: Update cargoHash in prmt.nix**

```bash
sed -i 's|cargoHash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";|cargoHash = "sha256-REPLACE_WITH_ACTUAL_CARGO_HASH";|' nix/pkgs/prmt.nix
```

- [ ] **Step 6: Verify the build succeeds**

```bash
nix build --impure --expr '(import <nixpkgs> {}).callPackage ./nix/pkgs/prmt.nix {}'
```

Expected: build completes with no error. Then verify the binary works:

```bash
./result/bin/prmt --version
```

Expected output: `prmt 0.5.0` (or similar version string).

- [ ] **Step 7: Verify the prompt format string renders**

```bash
./result/bin/prmt --no-version --timeout 3 --code 0 \
  "🕙 {env:cyan:PRMT_DATETIME}\n{env:green.bold:USER:╭─:@}{env::HOSTNAME::: in }{path:cyan:i}{git:purple:short: }{env:yellow:PRMT_DURATION:  took }\n{ok:green.bold:╰─λ}{fail:red.bold:×} "
```

Expected: 3 lines of output with colours. The `{env:cyan:PRMT_DATETIME}` will be empty (env var not set yet) which is fine — it proves the format string parses without error.

- [ ] **Step 8: Commit**

```bash
git add nix/pkgs/prmt.nix
git commit -m "feat: add prmt Nix derivation (rustPlatform.buildRustPackage v0.5.0)"
```

---

### Task 2: Wire prmt into Nix — packages/shared.nix and nixos/core/programs.nix

**Files:**

- Modify: `nix/modules/home/packages/shared.nix`
- Modify: `nix/modules/nixos/core/programs.nix`

- [ ] **Step 1: Read current packages/shared.nix header**

```bash
head -5 nix/modules/home/packages/shared.nix
```

Expected:

```nix
{ pkgs, ... }:

{
  home.packages = with pkgs; [
```

- [ ] **Step 2: Add let binding and replace starship with prmt**

The file currently starts with `{ pkgs, ... }:`. Add a `let` block between the argument set and the `{`, and replace `starship` with `prmt` in the packages list.

Find:

```nix
{ pkgs, ... }:

{
  home.packages = with pkgs; [
```

Replace with:

```nix
{ pkgs, ... }:

let
  prmt = pkgs.callPackage ../../../pkgs/prmt.nix {};
in

{
  home.packages = with pkgs; [
```

Then find (line ~125):

```
    starship
```

Replace with:

```
    prmt
```

- [ ] **Step 3: Verify the replacement**

```bash
grep -n "starship\|prmt" nix/modules/home/packages/shared.nix
```

Expected: one line showing `prmt` (the package), no `starship` lines.

- [ ] **Step 4: Remove programs.starship.enable from nixos/core/programs.nix**

The file at `nix/modules/nixos/core/programs.nix` has this block around line 115–119:

```nix
  # ────────────────────────────────────────────────
  # Starship prompt + Atuin history
  # ────────────────────────────────────────────────
  programs.starship.enable = true;
  programs.atuin.enable = true;
```

Remove only the starship line and update the comment. Find:

```nix
  # ────────────────────────────────────────────────
  # Starship prompt + Atuin history
  # ────────────────────────────────────────────────
  programs.starship.enable = true;
  programs.atuin.enable = true;
```

Replace with:

```nix
  # ────────────────────────────────────────────────
  # Atuin history
  # ────────────────────────────────────────────────
  programs.atuin.enable = true;
```

- [ ] **Step 5: Verify no remaining starship references in these two files**

```bash
grep -n "starship" nix/modules/home/packages/shared.nix nix/modules/nixos/core/programs.nix
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add nix/modules/home/packages/shared.nix nix/modules/nixos/core/programs.nix
git commit -m "feat: replace starship with prmt in Nix packages, remove programs.starship.enable"
```

---

### Task 3: Replace sheldon starship plugin with prmt

**Files:**

- Modify: `sheldon.toml`

The current `[plugins.starship]` block uses `_zcache_eval` + `zsh-defer` to cache `starship init zsh` output. The new `[plugins.prmt]` block replaces this with direct `PROMPT` assignment — no caching needed.

- [ ] **Step 1: Verify current starship block**

```bash
grep -n "plugins.starship\|plugins.zoxide" sheldon.toml
```

Expected output shows `[plugins.starship]` at one line and `[plugins.zoxide]` a few lines after — confirming the block boundaries.

- [ ] **Step 2: Replace the starship block with the prmt block**

Find the entire starship block:

```toml
[plugins.starship]
inline = '''
if (($+commands[starship])); then
  if [[ -f "$ZCACHE_DIR/starship.zsh" ]]; then
    source "$ZCACHE_DIR/starship.zsh"
  else
    _starship_init() {
      starship init zsh | sed -E -e "s/autoload -Uz add-zsh-hook//g" -e "s/add-zsh-hook precmd ([a-z_]*)/precmd_functions+=(\1)/g" -e "s/add-zsh-hook preexec ([a-z_]*)/preexec_functions+=(\1)/g" -e "s/PROMPT2=\"\\\$\((.*)\)\"/PROMPT2=\x27\$\(\1\)\x27/g"
    }
    zsh-defer -p -r _zcache_eval starship 0 "_starship_init" "$commands[starship]"
  fi
fi
'''
```

Replace with:

```toml
[plugins.prmt]
inline = '''
if (($+commands[prmt])); then
  zmodload zsh/datetime
  PRMT_HOSTNAME=${HOSTNAME%%-*}
  _prmt_exit=0 PRMT_DATETIME='' PRMT_DURATION=''

  _prmt_preexec() { _prmt_cmd_start=$EPOCHREALTIME }
  _prmt_precmd() {
    local _exit=$?
    if [[ -n $_prmt_cmd_start ]]; then
      local -F elapsed=$(( EPOCHREALTIME - _prmt_cmd_start ))
      (( elapsed >= 1.0 )) && printf -v PRMT_DURATION '%.1fs' $elapsed || PRMT_DURATION=''
      unset _prmt_cmd_start
    else
      PRMT_DURATION=''
    fi
    strftime -s PRMT_DATETIME '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS
    _prmt_exit=$_exit
  }
  preexec_functions=(_prmt_preexec "${preexec_functions[@]}")
  precmd_functions=(_prmt_precmd "${precmd_functions[@]}")

  setopt PROMPT_SUBST
  PROMPT='$(prmt --shell zsh --no-version --timeout 3 --code $_prmt_exit "🕙 {env:cyan:PRMT_DATETIME}\n{env:green.bold:USER:╭─:@}{env::PRMT_HOSTNAME::: in }{path:cyan:i}{git:purple:short: }{env:yellow:PRMT_DURATION:  took }\n{ok:green.bold:╰─λ}{fail:red.bold:×} ")'
fi
'''
```

- [ ] **Step 3: Verify no starship references remain in sheldon.toml**

```bash
grep -n "starship" sheldon.toml
```

Expected: no output.

- [ ] **Step 4: Verify prmt block is present**

```bash
grep -n "plugins.prmt\|prmt_precmd\|PRMT_HOSTNAME" sheldon.toml
```

Expected: three matching lines confirming the block is present.

- [ ] **Step 5: Smoke-test the plugin in a subshell**

```bash
zsh -c '
  source <(sheldon source 2>/dev/null) 2>/dev/null
  type _prmt_precmd 2>&1
'
```

Expected output: `_prmt_precmd is a shell function` — confirms the plugin loaded and defined the hook. (Requires prmt binary to be installed. If not yet deployed via Nix, install with `cargo install prmt` temporarily for testing.)

- [ ] **Step 6: Delete the stale starship cache if it exists**

```bash
rm -f "${ZCACHE_DIR:-$HOME/.cache/zsh}/starship.zsh"
echo "starship cache cleared (if it existed)"
```

- [ ] **Step 7: Commit**

```bash
git add sheldon.toml
git commit -m "feat: replace sheldon starship plugin with prmt, add precmd hooks for datetime/duration/exit"
```

---

### Task 4: Remove starship.toml deployments

**Files:**

- Modify: `nix/modules/home/dotfiles/shared.nix`
- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Remove .config/starship.toml from shared.nix**

In `nix/modules/home/dotfiles/shared.nix`, find:

```nix
    ".config/starship.toml".source = "${dotfilesPath}/starship.toml";
```

Remove that line entirely.

- [ ] **Step 2: Verify the removal**

```bash
grep -n "starship" nix/modules/home/dotfiles/shared.nix
```

Expected: no output.

- [ ] **Step 3: Remove starship.toml from DOTFILES_MAP in install.mk**

In `Makefile.d/install.mk`, find (line ~30):

```
starship.toml .config/starship.toml
```

Remove that line entirely.

- [ ] **Step 4: Verify the removal**

```bash
grep -n "starship" Makefile.d/install.mk
```

Expected: no output.

- [ ] **Step 5: Verify**

```bash
grep -n "starship" nix/modules/home/dotfiles/shared.nix Makefile.d/install.mk
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add nix/modules/home/dotfiles/shared.nix Makefile.d/install.mk
git commit -m "feat: remove starship.toml from Nix and Makefile deployment"
```

---

### Task 5: Remove starship from Docker volumes and delete starship.toml

**Files:**

- Modify: `zsh/20-docker.zsh`
- Delete: `starship.toml`

`zsh/20-docker.zsh` mounts `starship.toml` into Docker containers. prmt has no config file — the mount is simply removed. `starship.toml` is deleted from the repo as it is no longer deployed or needed.

- [ ] **Step 1: Remove the starship.toml volume mount from 20-docker.zsh**

In `zsh/20-docker.zsh`, find:

```bash
		"-v $rcpath/starship.toml:$container_config/starship.toml"
```

Remove that line entirely.

- [ ] **Step 2: Verify the removal**

```bash
grep -n "starship" zsh/20-docker.zsh
```

Expected: no output.

- [ ] **Step 3: Delete starship.toml**

```bash
git rm starship.toml
```

- [ ] **Step 4: Verify no starship references remain anywhere in the repo**

```bash
grep -rn "starship" . --include="*.nix" --include="*.toml" --include="*.mk" --include="*.sh" --include="*.zsh" --include="Makefile" --include="*.conf" 2>/dev/null | grep -v "\.git/" | grep -v "docs/superpowers/"
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add zsh/20-docker.zsh
git commit -m "feat: remove starship Docker volume mount and delete starship.toml (prmt migration complete)"
```
