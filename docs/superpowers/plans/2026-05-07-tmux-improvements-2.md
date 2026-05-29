# tmux Improvements Round 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove a duplicate setting, consolidate two status-bar subprocesses into one, add session persistence with auto-save, and enable pane border labels.

**Architecture:** Four independent changes to `tmux.conf` plus a new `tmux-status-left` helper script that inlines path-shortening logic and git branch lookup. Session persistence uses `tmux-resurrect` + `tmux-continuum` added to both the TPM path (for Docker) and the Nix home-manager path. Deployment follows the established symlink pattern (`tmux-kube`, `tmux-short-path`).

**Tech Stack:** bash, tmux config, Nix/home-manager (`pkgs.tmuxPlugins.resurrect`, `pkgs.tmuxPlugins.continuum`)

---

### Task 1: Create tmux-status-left script

**Files:**

- Create: `tmux-status-left`

- [ ] **Step 1: Create the script**

```bash
#!/usr/bin/env bash
[[ -z "$1" ]] && printf '%s' "#[fg=brightcyan].#[fg=#303030]" && exit 0
[[ "$1" == "/" ]] && printf '%s' "#[fg=brightcyan]/#[fg=#303030]" && exit 0

case "$1" in
  "$HOME"/*) path="~/${1#"$HOME"/}" ;;
  "$HOME")   path="~" ;;
  *)         path="$1" ;;
esac

IFS='/' read -ra parts <<< "$path"
last=$((${#parts[@]} - 1))
result=""
for i in "${!parts[@]}"; do
    p="${parts[$i]}"
    [[ -z "$p" || $i -eq $last ]] && result+="$p" || result+="${p:0:1}"
    [[ $i -lt $last ]] && result+="/"
done

branch=$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ -n "$branch" ]]; then
    printf '%s' "#[fg=brightcyan]${result}#[fg=#303030]#[fg=magenta]${branch}#[fg=#303030]"
else
    printf '%s' "#[fg=brightcyan]${result}#[fg=#303030]"
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x tmux-status-left
```

- [ ] **Step 3: Verify manually**

```bash
./tmux-status-left "/home/kpango/go/src/github.com/kpango/dotfiles"
```

Expected: `#[fg=brightcyan]~/g/s/g/k/dotfiles#[fg=#303030]#[fg=magenta]main#[fg=#303030]` (branch name may differ)

```bash
./tmux-status-left "/home/kpango"
```

Expected: `#[fg=brightcyan]~#[fg=#303030]` (no git repo → no branch segment)

```bash
./tmux-status-left "/"
```

Expected: `#[fg=brightcyan]/#[fg=#303030]`

```bash
./tmux-status-left ""
```

Expected: `#[fg=brightcyan].#[fg=#303030]`

- [ ] **Step 4: Symlink to home**

```bash
ls -la ~/.tmux-kube  # confirm symlink pattern
ln -sf "$(pwd)/tmux-status-left" ~/.tmux-status-left
ls -la ~/.tmux-status-left  # confirm symlink created
```

- [ ] **Step 5: Commit**

```bash
git add tmux-status-left
git commit -m "feat: add tmux-status-left combined path+branch status script"
```

---

### Task 2: Update tmux.conf — cleanup, status-left, resurrect/continuum, pane-border

**Files:**

- Modify: `tmux.conf`

- [ ] **Step 1: Remove the duplicate `set -g status-keys vi`**

Find and remove the second occurrence. The file has two lines:

- Line ~25: `set -g status-keys vi` (keep)
- Line ~33: `set -g status-keys vi` (remove — it follows `set -g focus-events on`)

After removal, the block around line 32-35 should read:

```
set -g focus-events on
setw -g monitor-activity on
setw -g visual-activity on
```

- [ ] **Step 2: Update status-left to use tmux-status-left**

Find:

```
set -g status-left "#[fg=green,bg=#303030][#S:#I.#P]#[fg=#303030]#[fg=brightcyan]#(~/.tmux-short-path #{pane_current_path})#[fg=#303030]#[fg=magenta]#(cd #{pane_current_path}; git rev-parse --abbrev-ref HEAD)#[fg=#303030]"
```

Replace with:

```
set -g status-left "#[fg=green,bg=#303030][#S:#I.#P]#[fg=#303030]#(~/.tmux-status-left #{pane_current_path})"
```

- [ ] **Step 3: Add resurrect and continuum plugin declarations**

Find the plugin declaration block at the top of `tmux.conf`:

```
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-cpu'

set -g @cpu_interval 5
```

Replace with:

```
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-cpu'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

set -g @cpu_interval 5
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
```

- [ ] **Step 4: Enable pane-border-status**

Find:

```
set -g pane-border-status "off"
```

Replace with:

```
set -g pane-border-status "bottom"
```

- [ ] **Step 5: Commit**

```bash
git add tmux.conf
git commit -m "feat: consolidate status-left, add resurrect/continuum, enable pane-border-status, remove duplicate setting"
```

---

### Task 3: Update tmux.nix — add plugins and extend stripTPM

**Files:**

- Modify: `nix/modules/home/programs/tmux.nix`

- [ ] **Step 1: Read the current file**

```bash
cat nix/modules/home/programs/tmux.nix
```

Confirm current content matches:

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

- [ ] **Step 2: Replace the entire file with the updated version**

```nix
{ isDarwin, dotfilesPath, pkgs, ... }:

{
  programs.tmux = {
    enable = true;
    clock24 = true;
    mouse = true;
    plugins = with pkgs.tmuxPlugins; [
      cpu
      resurrect
      {
        plugin = continuum;
        extraConfig = ''
          set -g @continuum-restore 'on'
          set -g @continuum-save-interval '15'
        '';
      }
    ];
    extraConfig =
      let
        stripTPM = str: builtins.replaceStrings
          [ "set -g @plugin 'tmux-plugins/tpm'\n"
            "set -g @plugin 'tmux-plugins/tmux-cpu'\n"
            "set -g @plugin 'tmux-plugins/tmux-resurrect'\n"
            "set -g @plugin 'tmux-plugins/tmux-continuum'\n"
            "set -g @continuum-restore 'on'\n"
            "set -g @continuum-save-interval '15'\n"
            "run '~/.tmux/plugins/tpm/tpm'\n" ]
          [ "" "" "" "" "" "" "" ]
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

- [ ] **Step 3: Verify Nix syntax (count braces)**

```bash
grep -c '{' nix/modules/home/programs/tmux.nix
grep -c '}' nix/modules/home/programs/tmux.nix
```

Expected: same count for both (balanced).

- [ ] **Step 4: Commit**

```bash
git add nix/modules/home/programs/tmux.nix
git commit -m "feat: add resurrect/continuum to Nix tmux plugins, extend stripTPM"
```

---

### Task 4: Update deployment — shared.nix and install.mk

**Files:**

- Modify: `nix/modules/home/dotfiles/shared.nix`
- Modify: `Makefile.d/install.mk`

- [ ] **Step 1: Add tmux-status-left to shared.nix**

In `nix/modules/home/dotfiles/shared.nix`, find:

```
    ".tmux-kube".source = "${dotfilesPath}/tmux-kube";
    ".tmux-short-path".source = "${dotfilesPath}/tmux-short-path";
```

Replace with:

```
    ".tmux-kube".source = "${dotfilesPath}/tmux-kube";
    ".tmux-short-path".source = "${dotfilesPath}/tmux-short-path";
    ".tmux-status-left".source = "${dotfilesPath}/tmux-status-left";
```

- [ ] **Step 2: Add tmux-status-left to install.mk DOTFILES_MAP**

In `Makefile.d/install.mk`, find:

```
tmux-kube .tmux-kube
tmux-short-path .tmux-short-path
tmux.new-session .tmux.new-session
```

Replace with:

```
tmux-kube .tmux-kube
tmux-short-path .tmux-short-path
tmux-status-left .tmux-status-left
tmux.new-session .tmux.new-session
```

- [ ] **Step 3: Commit**

```bash
git add nix/modules/home/dotfiles/shared.nix Makefile.d/install.mk
git commit -m "feat: deploy tmux-status-left via Nix and Makefile"
```
