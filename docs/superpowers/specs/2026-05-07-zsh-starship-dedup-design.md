# zsh Starship Deduplication Design

**Date:** 2026-05-07
**Scope:** `nix/modules/home/programs/zsh.nix`

## Context

On NixOS, `zsh.nix`'s `initContent` runs on every shell start:

```nix
initContent = ''
  eval "$(sheldon source)"
  eval "$(starship init zsh)"
  source ${dotfilesPath}/zshrc
'';
```

`sheldon.toml` already initialises starship via a cached + deferred path:

```toml
[plugins.starship]
inline = '''
if (($+commands[starship])); then
  if [[ -f "$ZCACHE_DIR/starship.zsh" ]]; then
    source "$ZCACHE_DIR/starship.zsh"
  else
    zsh-defer -p -r _zcache_eval starship 0 "_starship_init" "$commands[starship]"
  fi
fi
'''
```

The `eval "$(starship init zsh)"` in `initContent` runs synchronously and uncached before sheldon's deferred version. Result: starship initialises twice per shell start — once blocking (slow), once deferred (fast+cached). The blocking call is redundant.

## Change

Remove `eval "$(starship init zsh)"` from `zsh.nix` `initContent`.

**Before:**

```nix
initContent = ''
  # Init Sheldon
  eval "$(sheldon source)"

  # Init Starship
  eval "$(starship init zsh)"

  # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
  source ${dotfilesPath}/zshrc
'';
```

**After:**

```nix
initContent = ''
  # Init Sheldon
  eval "$(sheldon source)"

  # Source core monolithic zshrc script (bypassing Nix native strings to keep dotfiles source truth)
  source ${dotfilesPath}/zshrc
'';
```

Starship continues to be initialised by sheldon (cached in `$ZCACHE_DIR/starship.zsh`, deferred via `zsh-defer`).

## Files Changed

| File                                | Action                                            |
| ----------------------------------- | ------------------------------------------------- |
| `nix/modules/home/programs/zsh.nix` | Modify: remove `eval "$(starship init zsh)"` line |

## What Is Not Changed

- `eval "$(sheldon source)"` in `initContent` is kept (provides sheldon plugins before `zshrc` runs)
- `sheldon.toml` starship plugin unchanged
- All other zsh config unchanged
