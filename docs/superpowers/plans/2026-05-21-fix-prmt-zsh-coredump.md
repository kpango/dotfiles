# Fix prmt Plugin Zsh Core Dump (SIGSEGV/SIGABRT) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate SIGSEGV/SIGABRT core dumps in Zsh caused by unsafe FD lifecycle management and ZLE hook self-deletion in the inline `prmt` plugin configuration.

**Architecture:** Three surgical changes to the `[plugins.prmt]` inline block in `sheldon.toml`: (1) remove `exec {fd}<&-` from `_prmt_async_callback`, (2) remove `exec {_prmt_fd}<&-` from `_prmt_precmd`, (3) replace self-deleting ZLE hook in `_prmt_zle_init` with an idempotency flag. No changes to prompt formatting logic.

**Tech Stack:** Zsh, sheldon (plugin manager), `zsh/zle`, `zle -F` (FD-based async callbacks), `add-zle-hook-widget`

---

## Root Cause Summary

| #   | Location                            | Bug                                                                                            | Mechanism                                              |
| --- | ----------------------------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| 1   | `_prmt_async_callback` always block | Double-free: `exec {fd}<&-` manually closes an FD that Zsh's process substitution already owns | Memory corruption in Zsh's internal FD table → SIGSEGV |
| 2   | `_prmt_precmd`                      | Same double-free pattern: `exec {_prmt_fd}<&-` after `zle -F` already unregistered the fd      | Use-after-free / SIGABRT                               |
| 3   | `_prmt_zle_init`                    | Hook self-deletes via `add-zle-hook-widget -d` / `zle -D` during its own execution             | Stack corruption in certain Zsh versions → SIGABRT     |

---

## File Structure

- **Modify:** `sheldon.toml` — `[plugins.prmt]` inline block only (lines 26–101)

No new files are created. All three fixes land in a single TOML stanza.

---

### Task 1: Remove manual FD closure in `_prmt_async_callback`

**Files:**

- Modify: `sheldon.toml:54-58` (the `always` block of `_prmt_async_callback`)

**What to change:** Delete `exec {fd}<&- 2>/dev/null` from the `always` block.  
Zsh owns the FD lifetime for process substitution `<(...)`. `zle -F $fd` already unregisters the handler; calling `exec {fd}<&-` after that corrupts the FD table.

- [ ] **Step 1: Apply the fix**

In `sheldon.toml`, locate the `always` block inside `_prmt_async_callback` (around line 54). Change it from:

```zsh
    } always {
      zle -F $fd 2>/dev/null
      exec {fd}<&- 2>/dev/null
      _prmt_fd=0
    }
```

To:

```zsh
    } always {
      zle -F $fd 2>/dev/null
      _prmt_fd=0
    }
```

- [ ] **Step 2: Verify the diff**

```bash
git diff sheldon.toml
```

Expected: Only the `exec {fd}<&- 2>/dev/null` line removed from the `always` block. No other changes.

---

### Task 2: Remove manual FD closure in `_prmt_precmd`

**Files:**

- Modify: `sheldon.toml:72-76` (the old-FD cleanup block inside `_prmt_precmd`)

**What to change:** Delete `exec {_prmt_fd}<&- 2>/dev/null` from the old-FD guard. Simply unregistering with `zle -F` is sufficient; closing the FD manually causes a double-free.

- [ ] **Step 1: Apply the fix**

In `sheldon.toml`, locate the old-FD guard inside `_prmt_precmd` (around line 72). Change it from:

```zsh
    (( _prmt_fd )) && {
      zle -F $_prmt_fd 2>/dev/null
      exec {_prmt_fd}<&- 2>/dev/null
      _prmt_fd=0
    }
```

To:

```zsh
    (( _prmt_fd )) && {
      zle -F $_prmt_fd 2>/dev/null
      _prmt_fd=0
    }
```

- [ ] **Step 2: Verify the diff**

```bash
git diff sheldon.toml
```

Expected: Two lines removed total so far (`exec {fd}<&-` and `exec {_prmt_fd}<&-`). No other changes yet.

---

### Task 3: Replace self-deleting ZLE hook with idempotency flag in `_prmt_zle_init`

**Files:**

- Modify: `sheldon.toml:87-95` (`_prmt_zle_init` function and its registration)

**What to change:** Remove `add-zle-hook-widget -d` / `zle -D` from inside `_prmt_zle_init`. Introduce a `_prmt_init_done` guard variable so the body only runs once. The hook registration at the bottom stays as-is — the idempotency flag handles the "run once" requirement without the hook tearing itself down mid-execution.

- [ ] **Step 1: Apply the fix**

In `sheldon.toml`, locate `_prmt_zle_init` and its preceding `typeset` declaration. Replace this block:

```zsh
  # One-shot zle-line-init hook: when ZLE first becomes active, register the fd callback that
  # precmd opened but could not register (ZLE was not yet active at precmd time).
  _prmt_zle_init() {
    # Remove this one-shot hook (prefer add-zle-hook-widget; fallback to zle -D)
    add-zle-hook-widget -d zle-line-init _prmt_zle_init 2>/dev/null || \
      zle -D zle-line-init 2>/dev/null
    (( _prmt_fd )) && zle -F $_prmt_fd _prmt_async_callback 2>/dev/null
  }
```

With:

```zsh
  # Idempotent zle-line-init hook: when ZLE first becomes active, register the fd callback that
  # precmd opened but could not register (ZLE was not yet active at precmd time).
  typeset -g _prmt_init_done=''
  _prmt_zle_init() {
    [[ -n $_prmt_init_done ]] && return
    _prmt_init_done=1
    (( _prmt_fd )) && zle -F $_prmt_fd _prmt_async_callback 2>/dev/null
  }
```

- [ ] **Step 2: Verify the full diff**

```bash
git diff sheldon.toml
```

Expected output (3 distinct hunks):

1. `always` block in `_prmt_async_callback`: `exec {fd}<&- 2>/dev/null` line removed.
2. Old-FD guard in `_prmt_precmd`: `exec {_prmt_fd}<&- 2>/dev/null` line removed.
3. `_prmt_zle_init`: comment updated, `add-zle-hook-widget -d` / `zle -D` lines replaced with `typeset -g _prmt_init_done=''` declaration and idempotency guard.

No changes to `_prmt_fmt`, `_prmt_preexec`, prompt rendering logic, or the hook registration block at the bottom.

---

### Task 4: Smoke-test the fixed configuration

**Files:**

- Read: `sheldon.toml` (verify final state)

- [ ] **Step 1: Confirm final state of the prmt block**

The complete `[plugins.prmt]` inline block should now read:

```toml
[plugins.prmt]
inline = '''
if (($+commands[prmt])) && [[ -t 0 ]]; then
  zmodload zsh/datetime
  # PRMT_HOSTNAME: stripped hostname (prmt has no native hostname stripping)
  # PRMT_DURATION: command duration (prmt has no native duration module)
  local _prmt_h=${HOSTNAME%%-*}
  export PRMT_HOSTNAME=${_prmt_h:0:12} PRMT_DURATION=''
  typeset -g _prmt_fd=0
  # {time}       — native 24h time with seconds
  # {path:r}     — native relative path (~ substituted for home)
  # {git:full}   — native branch + status indicators (dirty/staged/untracked)
  # {go}/{rust}/{node} — auto-detected versions, shown only in relevant project dirs
  # {ok}/{fail}  — native exit-code indicators; two {fail} tokens = symbol + code number
  # {env}        — native env var interpolation for USER, hostname, duration
  typeset -g _prmt_fmt="🕙 {time:cyan:24hs}\n{env:green.bold:USER:╭─:@}{env::PRMT_HOSTNAME::: in }{path:cyan:r}{git:purple:: }{go:cyan:: 🐹}{rust:red:: 🦀}{node:green:: ⬢}{env:yellow:PRMT_DURATION:  took }\n{ok:green.bold:╰─λ}{fail:red.bold:╰─✗}{fail:red.dim:code: } "

  _prmt_preexec() { _prmt_cmd_start=$EPOCHREALTIME }

  _prmt_async_callback() {
    local fd=$1
    {
      local line buf=''
      while IFS= read -r -u $fd line || [[ -n $line ]]; do
        [[ -n $buf ]] && buf+=$'\n'
        buf+=$line
      done
      [[ -n $buf ]] && PROMPT=$buf && zle reset-prompt 2>/dev/null
    } always {
      zle -F $fd 2>/dev/null
      _prmt_fd=0
    }
  }

  _prmt_precmd() {
    [[ -t 0 ]] || return
    local _exit=$?
    if [[ -n $_prmt_cmd_start ]]; then
      local -F elapsed=$(( EPOCHREALTIME - _prmt_cmd_start ))
      (( elapsed >= 1.0 )) && printf -v PRMT_DURATION '%.1fs' $elapsed || PRMT_DURATION=''
      unset _prmt_cmd_start
    else
      PRMT_DURATION=''
    fi

    (( _prmt_fd )) && {
      zle -F $_prmt_fd 2>/dev/null
      _prmt_fd=0
    }

    # Show placeholder immediately so no stale prompt data is visible while prmt renders
    PROMPT='%F{blue}…%f '
    exec {_prmt_fd}< <(prmt --shell zsh --code $_exit "$_prmt_fmt" 2>/dev/null)
    # Register async callback (succeeds once ZLE is active; first call may fail — _prmt_zle_init handles that)
    zle -F $_prmt_fd _prmt_async_callback 2>/dev/null
  }

  # Idempotent zle-line-init hook: when ZLE first becomes active, register the fd callback that
  # precmd opened but could not register (ZLE was not yet active at precmd time).
  typeset -g _prmt_init_done=''
  _prmt_zle_init() {
    [[ -n $_prmt_init_done ]] && return
    _prmt_init_done=1
    (( _prmt_fd )) && zle -F $_prmt_fd _prmt_async_callback 2>/dev/null
  }
  autoload -Uz add-zle-hook-widget
  { add-zle-hook-widget zle-line-init _prmt_zle_init } 2>/dev/null || \
    zle -N zle-line-init _prmt_zle_init

  preexec_functions=(_prmt_preexec "${preexec_functions[@]}")
  precmd_functions=(_prmt_precmd "${precmd_functions[@]}")
  # _prmt_precmd skips for non-TTY (no point rendering a prompt to a pipe/file)
fi
'''
```

- [ ] **Step 2: Parse check (no syntax errors)**

```bash
zsh -n <(grep -A200 '^\[plugins\.prmt\]' sheldon.toml | sed "1d;/^\[plugins\./q" | head -n -1 | sed "s/^inline = '''//;s/'''$//")
```

Expected: No output (exit 0 = no syntax errors).

- [ ] **Step 3: Reload sheldon and source in a subshell**

```bash
zsh -ic 'sheldon source > /tmp/sheldon_test.zsh && zsh -n /tmp/sheldon_test.zsh && echo "OK"'
```

Expected: `OK` printed, no `zsh: parse error` or `zsh: command not found`.

- [ ] **Step 4: Commit**

```bash
git add sheldon.toml
git commit -m "fix(prmt): remove double-free FD closes and unsafe ZLE hook self-deletion

- Drop exec {fd}<&- from _prmt_async_callback always block: Zsh owns
  the FD lifetime for <(...) process substitution; closing it manually
  after zle -F corrupts the internal FD table (SIGSEGV).
- Drop exec {_prmt_fd}<&- from _prmt_precmd for the same reason.
- Replace add-zle-hook-widget -d / zle -D self-deletion in
  _prmt_zle_init with an idempotency flag (_prmt_init_done) to prevent
  multiple executions without tearing down the hook mid-execution
  (SIGABRT on certain Zsh versions)."
```

---

## Self-Review Checklist

- [x] **Spec coverage:** All three bug fixes from the spec are addressed (Task 1 = async callback FD, Task 2 = precmd FD, Task 3 = ZLE hook).
- [x] **Placeholder scan:** No TBDs, no vague steps — every step shows the exact before/after code.
- [x] **Type consistency:** `_prmt_fd`, `_prmt_init_done`, `_prmt_async_callback`, `_prmt_precmd`, `_prmt_zle_init` are named consistently across all tasks.
- [x] **No prompt formatting changes:** `_prmt_fmt`, `_prmt_preexec`, and the `prmt --shell zsh` invocation are untouched.
