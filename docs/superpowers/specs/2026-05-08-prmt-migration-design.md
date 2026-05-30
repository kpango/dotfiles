# starship → prmt Migration Design

**Date:** 2026-05-08
**Scope:** `sheldon.toml`, `nix/pkgs/prmt.nix` (new), `nix/modules/home/packages/shared.nix`, `nix/modules/nixos/core/programs.nix`, `nix/modules/home/dotfiles/shared.nix`, `Makefile.d/install.mk`

## Goal

Replace starship with prmt for a ~1ms shell prompt render (vs starship's ~15–50ms), preserving the 3-line visual style of the current prompt.

## Prompt Output

Success:

```
 🕙 2026-05-08 14:23:45
╭─kpango@hostname in ~/g/s/g/k/dotfiles  main
╰─λ
```

Failure / slow command:

```
 🕙 2026-05-08 14:24:01
╭─kpango@hostname in ~/g/s/g/k/dotfiles  main  took 3.1s
×
```

## Architecture

### PROMPT format string

```
🕙 {env:cyan:PRMT_DATETIME}\n{env:green.bold:USER:╭─:@}{env::PRMT_HOSTNAME::: in }{path:cyan:i}{git:purple:short: }{env:yellow:PRMT_DURATION:  took }\n{ok:green.bold:╰─λ}{fail:red.bold:×}
```

Module breakdown:

| Token                                | Module | Notes                                                             |
| ------------------------------------ | ------ | ----------------------------------------------------------------- |
| `🕙 {env:cyan:PRMT_DATETIME}`        | env    | Full datetime set by precmd `strftime` builtin                    |
| `{env:green.bold:USER:╭─:@}`         | env    | `╭─kpango@` in green bold                                         |
| `{env::PRMT_HOSTNAME::: in }`        | env    | hostname trimmed at `-`, suffix `in`                              |
| `{path:cyan:i}`                      | path   | Fish-style initials abbreviation                                  |
| `{git:purple:short: }`               | git    | Branch name only, leading space prefix (only active in git repos) |
| `{env:yellow:PRMT_DURATION:  took }` | env    | `  took 2.3s` — only when `PRMT_DURATION` is non-empty            |
| `{ok:green.bold:╰─λ}`                | ok     | Custom success symbol                                             |
| `{fail:red.bold:×}`                  | fail   | Custom failure symbol                                             |

### prmt flags

```
--shell zsh       wrap ANSI escapes for correct zsh cursor positioning
--no-version      skip all language version filesystem reads
--timeout 3       hard cap at 3ms
--code $_prmt_exit  exit code captured in precmd (see below)
```

### Shell hooks (all zsh builtins — zero subprocesses)

The hooks are defined inside the sheldon `[plugins.prmt]` inline block:

```zsh
zmodload zsh/datetime
PRMT_HOSTNAME=${HOSTNAME%%-*}        # trim at first hyphen, set once
_prmt_exit=0
PRMT_DATETIME=''
PRMT_DURATION=''

_prmt_preexec() {
  _prmt_cmd_start=$EPOCHREALTIME
}

_prmt_precmd() {
  local _exit=$?                     # must be first line — $? is user command's exit code
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

preexec_functions=(_prmt_preexec "${preexec_functions[@]}")   # prepend — runs first
precmd_functions=(_prmt_precmd "${precmd_functions[@]}")      # prepend — $? is user's code
```

`_prmt_precmd` is prepended so it runs before any other precmd function, ensuring `$?` is the user command's exit code, not a subsequent hook's.

`$EPOCHREALTIME` and `strftime` are zsh builtins (`zsh/datetime` module). No `date`, no `git`, no subprocess forks in the hooks.

### sheldon.toml change

Replace `[plugins.starship]` with:

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

No `_zcache_eval`, no `zsh-defer`. Setting `PROMPT` is a trivial variable assignment; the prmt binary runs at prompt render time (~1ms).

## Nix Packaging

prmt v0.5.0 is not in nixpkgs. New file `nix/pkgs/prmt.nix`:

```nix
{ rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "prmt";
  version = "0.5.0";
  src = fetchFromGitHub {
    owner = "3axap4eHko";
    repo = "prmt";
    rev = "v${version}";
    hash = "sha256-...";    # computed at implementation time with nix-prefetch-github
  };
  cargoHash = "sha256-..."; # computed at implementation time with cargoSetupHook
  buildFeatures = [ "git-gix" ];
}
```

`buildFeatures = [ "git-gix" ]` enables the default feature flag that uses the `gix` library for git operations (pure Rust, no git subprocess).

## Files Changed

| File                                   | Change                                                                 |
| -------------------------------------- | ---------------------------------------------------------------------- |
| `sheldon.toml`                         | Replace `[plugins.starship]` block with `[plugins.prmt]` block         |
| `nix/pkgs/prmt.nix`                    | New file: `rustPlatform.buildRustPackage` derivation                   |
| `nix/modules/home/packages/shared.nix` | Replace `starship` with `(pkgs.callPackage ../../../pkgs/prmt.nix {})` |
| `nix/modules/nixos/core/programs.nix`  | Remove `programs.starship.enable = true`                               |
| `nix/modules/home/dotfiles/shared.nix` | Remove `.config/starship.toml` entry                                   |
| `Makefile.d/install.mk`                | Remove `starship.toml .config/starship.toml` from `DOTFILES_MAP`       |

`starship.toml` is kept in the repository as a reference but no longer deployed.

## Performance

|                                                        | Render time per prompt |
| ------------------------------------------------------ | ---------------------- |
| starship (current, cached+deferred)                    | ~15–50ms               |
| prmt (no flags)                                        | ~2ms                   |
| prmt (`--no-version` + `{git::short}` + `--timeout 3`) | **~1ms**               |
| precmd hooks (`strftime`, `EPOCHREALTIME`)             | <0.1ms                 |

## What Is Preserved vs Simplified

| Feature                           | Starship | prmt                                  |
| --------------------------------- | -------- | ------------------------------------- |
| 3-line structure                  | ✅       | ✅                                    |
| `╭─user@hostname in `             | ✅       | ✅ via `{env}`                        |
| Full datetime `%Y-%m-%d %H:%M:%S` | ✅       | ✅ via zsh `strftime` builtin         |
| Fish-style path abbreviation      | ✅       | ✅ `:i` type                          |
| Hostname trimmed at `-`           | ✅       | ✅ `${HOSTNAME%%-*}` at startup       |
| Git branch                        | ✅       | ✅                                    |
| `╰─λ` / `×` symbols               | ✅       | ✅ custom ok/fail type                |
| Cmd duration (>1s)                | ✅       | ✅ via `$EPOCHREALTIME` + `printf`    |
| Git dirty/ahead/behind counts     | ✅       | ❌ branch only (`{git::short}`)       |
| Language version numbers          | ✅       | ❌ `--no-version`                     |
| Kubernetes / docker context       | ✅       | ❌ dropped (would require subprocess) |

## What Is Not Changed

- `zsh.nix` — already has no `starship init` call (removed in prior session)
- `sheldon.toml` — all other plugins unchanged
- `zshrc` — unchanged
- `tmux-status-left` — unchanged (shows path+git independently)
