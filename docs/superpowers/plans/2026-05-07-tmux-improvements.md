# tmux.conf Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve tmux.conf with fish-style path shortening, Wayland-aware clipboard, true color fixes, general cleanup, and Nix-native plugin management.

**Architecture:** Changes are split across three files: a new `tmux-short-path` helper script (called from the status bar), `tmux.conf` (the portable base used in Docker too), and `tmux.nix` (strips TPM lines and uses home-manager plugins when building for NixOS). The `tmux.conf` retains TPM bootstrap so it continues to work standalone in Docker containers.

**Tech Stack:** bash, tmux format strings, Nix/home-manager (`pkgs.tmuxPlugins`), `wl-copy`/`wl-paste` (wl-clipboard)

---

### Task 1: Create tmux-short-path script

**Files:**

- Create: `tmux-short-path`

- [ ] **Step 1: Create the script**

Create `tmux-short-path` in the dotfiles root (same location as `tmux-kube`):

```bash
#!/usr/bin/env bash
# Abbreviates all path components except the last to their first character.
# Replaces $HOME with ~.
# Usage: tmux-short-path /some/deep/path
path=$(echo "$1" | sed "s|^${HOME}|~|")
IFS='/' read -ra parts <<< "$path"
result=""
count=${#parts[@]}
for i in "${!parts[@]}"; do
    part="${parts[$i]}"
    if [[ $i -eq $((count - 1)) ]] || [[ -z "$part" ]]; then
        result+="$part"
    else
        result+="${part:0:1}"
    fi
    [[ $i -lt $((count - 1)) ]] && result+="/"
done
echo "$result"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x tmux-short-path
```

- [ ] **Step 3: Verify the script manually**

```bash
./tmux-short-path "/home/kpango/go/src/github.com/kpango/dotfiles"
```

Expected output: `~/g/s/g/k/dotfiles`

```bash
./tmux-short-path "/home/kpango/go/src/github.com/kpango"
```

Expected output: `~/g/s/g/kpango`

```bash
./tmux-short-path "/home/kpango"
```

Expected output: `~`

```bash
./tmux-short-path "/root/app"
```

Expected output: `/r/app` (no `~` substitution when path is not under `$HOME`)

- [ ] **Step 4: Symlink to home directory**

The script is referenced as `~/.tmux-short-path` in `tmux.conf` (same pattern as `~/.tmux-kube`). Check if the dotfiles use a symlink setup:

```bash
ls -la ~/.tmux-kube
```

If it shows a symlink to the dotfiles repo, create the same for `tmux-short-path`:

```bash
ln -sf "$(pwd)/tmux-short-path" ~/.tmux-short-path
```

- [ ] **Step 5: Commit**

```bash
git add tmux-short-path
git commit -m "feat: add tmux-short-path fish-style path abbreviation script"
```

---

### Task 2: Update status-left to use tmux-short-path

**Files:**

- Modify: `tmux.conf:118`

- [ ] **Step 1: Replace `#{pane_current_path}` with the script call in status-left**

Current line 118:

```
set -g status-left "#[fg=green,bg=#303030][#S:#I.#P]#[fg=#303030]#[fg=brightcyan]#{pane_current_path}#[fg=#303030]#[fg=magenta]#(cd #{pane_current_path}; git rev-parse --abbrev-ref HEAD)#[fg=#303030]"
```

Replace with:

```
set -g status-left "#[fg=green,bg=#303030][#S:#I.#P]#[fg=#303030]#[fg=brightcyan]#(~/.tmux-short-path #{pane_current_path})#[fg=#303030]#[fg=magenta]#(cd #{pane_current_path}; git rev-parse --abbrev-ref HEAD)#[fg=#303030]"
```

- [ ] **Step 2: Reload config and verify**

In a running tmux session:

```
prefix + r
```

Navigate into a deep directory in a pane (e.g. `cd ~/go/src/github.com/kpango/dotfiles`) and confirm the status bar shows `~/g/s/g/k/dotfiles` instead of the full path.

- [ ] **Step 3: Commit**

```bash
git add tmux.conf
git commit -m "feat: shorten status-left path with fish-style abbreviation"
```

---

### Task 3: Fix clipboard bindings for Wayland and Docker

**Files:**

- Modify: `tmux.conf:95-97`

- [ ] **Step 1: Replace xsel clipboard bindings**

Current lines 95-97:

```
bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel "xsel -i -p && xsel -o -p | xsel -i -b" # for Linux
bind-key p run "xsel -o | tmux load-buffer - ; tmux paste-buffer" # for Linux
# bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel "pbcopy" # for mac OS
```

Replace with:

```
bind-key -T copy-mode-vi 'y' send-keys -X copy-pipe-and-cancel "if command -v wl-copy >/dev/null 2>&1; then wl-copy; fi"
bind-key p run "{ wl-paste --no-newline 2>/dev/null || true; } | tmux load-buffer - ; tmux paste-buffer"
```

- [ ] **Step 2: Reload config and verify copy on Wayland host**

In tmux on the Wayland host:

1. Enter copy mode: `prefix + [`
2. Select text with `v`, copy with `y`
3. Paste outside tmux (e.g. in another app) — clipboard should contain the copied text
4. `prefix + p` inside tmux — should also paste

- [ ] **Step 3: Verify graceful fallback in Docker**

In a Docker container running tmux (where `wl-copy` is absent):

1. Enter copy mode, select text with `v`, copy with `y` — should complete without error
2. `prefix + p` — should paste from tmux's internal buffer (may be empty if nothing previously copied from outside)

- [ ] **Step 4: Commit**

```bash
git add tmux.conf
git commit -m "fix: replace xsel with wl-copy/wl-paste for Wayland, silent fallback in Docker"
```

---

### Task 4: Fix true color and terminal settings

**Files:**

- Modify: `tmux.conf:100-106`

- [ ] **Step 1: Remove the screen-256color downgrade and fix terminal-overrides**

Current lines 100-106:

```
# THEME
## set the default TERM
# set -g default-terminal screen
## update the TERM variable of terminal emulator when creating a new session or attaching a existing session
set -g update-environment 'DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY TERM'
## determine if we should enable 256-colour support
if-shell "[[ ${TERM} =~ 256color || ${TERM} == fbterm ]]" 'set -g default-terminal screen-256color'
set-option -sa terminal-overrides ",${TERM}:RGB"
```

Replace with:

```
# THEME
set -g update-environment 'DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY TERM'
set -as terminal-features ",xterm*:RGB"
set -as terminal-features ",tmux*:RGB"
```

- [ ] **Step 2: Reload config and verify true color still works**

Run this inside tmux to confirm 24-bit color is active:

```bash
awk 'BEGIN{
    s="/\\/";
    for (colnum = 0; colnum<77; colnum++) {
        r = 255-(colnum*255/76);
        g = (colnum*510/76);
        b = (colnum*255/76);
        if (g>255) g = 510-g;
        printf "\033[48;2;%d;%d;%dm", r,g,b;
        printf "\033[38;2;%d;%d;%dm", 255-r,255-g,255-b;
        printf "%s\033[0m", substr(s,colnum%2+1,1);
    }
    printf "\n";
}'
```

Expected: a smooth color gradient. If you see banding or wrong colors, true color is not active.

- [ ] **Step 3: Commit**

```bash
git add tmux.conf
git commit -m "fix: remove screen-256color downgrade, use terminal-features for true color"
```

---

### Task 5: General cleanup

**Files:**

- Modify: `tmux.conf`

- [ ] **Step 1: Remove dead commented-out bindings and add renumber-windows**

Make the following changes to `tmux.conf`:

**Remove** lines 41-43 (old commented-out bind-key -r lines):

```
# bind-key -r c new-window
# bind-key -r s split-window -v
# bind-key -r v split-window -h
```

**Remove** lines 47-49 (old $PWD-based bind-key lines):

```
# bind-key -r c new-window -c $PWD
# bind-key -r s split-window -c $PWD -v
# bind-key -r v split-window -c $PWD -h
```

**Remove** line 130 (handled by tmux.nix on macOS):

```
# set-environment -g PATH "/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin"
```

**Change** line 131 — remove deprecated `-b` flag:

```
run '~/.tmux/plugins/tpm/tpm'
```

(was: `run -b '~/.tmux/plugins/tpm/tpm'`)

**Add** after `set -g history-limit 1000000` (line 26):

```
set -g renumber-windows on
```

- [ ] **Step 2: Reload config and verify tmux still starts cleanly**

```bash
tmux kill-server 2>/dev/null; tmux new-session
```

No error messages should appear in the status bar or on attach.

- [ ] **Step 3: Commit**

```bash
git add tmux.conf
git commit -m "chore: remove dead comments, add renumber-windows, fix deprecated run -b"
```

---

### Task 6: Update tmux.nix for Nix plugin management

**Files:**

- Modify: `nix/modules/home/programs/tmux.nix`

- [ ] **Step 1: Add `pkgs` to the module arguments and switch to home-manager plugins**

Current `nix/modules/home/programs/tmux.nix`:

```nix
{ isDarwin, dotfilesPath, ... }:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    extraConfig =
      let
        baseConfig = builtins.readFile "${dotfilesPath}/tmux.conf";
      in
      if isDarwin then
        builtins.replaceStrings
          [ "# set-environment -g PATH" ]
          [ "set-environment -g PATH" ]
          baseConfig
      else
        baseConfig;
  };
}
```

Replace with:

```nix
{ isDarwin, dotfilesPath, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    plugins = with pkgs.tmuxPlugins; [ cpu ];
    extraConfig =
      let
        stripTPM = str: builtins.replaceStrings
          [ "set -g @plugin 'tmux-plugins/tpm'\n"
            "set -g @plugin 'tmux-plugins/tmux-cpu'\n"
            "run '~/.tmux/plugins/tpm/tpm'\n" ]
          [ "" "" "" ]
          str;
        baseConfig = stripTPM (builtins.readFile "${dotfilesPath}/tmux.conf");
      in
      if isDarwin then
        builtins.replaceStrings
          [ "# set-environment -g PATH" ]
          [ "set-environment -g PATH" ]
          baseConfig
      else
        baseConfig;
  };
}
```

- [ ] **Step 2: Verify `pkgs` is available at the call site**

Check how `tmux.nix` is imported in the NixOS/home-manager configuration to confirm `pkgs` is passed through:

```bash
grep -r "tmux.nix\|programs/tmux" nix/ --include="*.nix" -l
```

Read the importing file and confirm `pkgs` is in scope (it is for home-manager modules by default).

- [ ] **Step 3: Build the NixOS configuration to verify no evaluation errors**

```bash
nixos-rebuild dry-run --flake .#tr 2>&1 | tail -20
```

or if using home-manager standalone:

```bash
home-manager build --flake .#kpango 2>&1 | tail -20
```

Expected: build succeeds with no errors. If `pkgs` is not in scope, the error will say `undefined variable 'pkgs'` — fix by checking the module import chain.

- [ ] **Step 4: Commit**

```bash
git add nix/modules/home/programs/tmux.nix
git commit -m "feat: switch tmux Nix module to home-manager plugin management, strip TPM from Nix config"
```
