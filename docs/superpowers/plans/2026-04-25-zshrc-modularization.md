# Zshrc Modularization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Break the monolithic `zshrc` file into smaller, topic-based modules in a `zsh/` directory.

**Architecture:** A new `zsh/` directory containing sequentially prefixed files (e.g., `00-tmux.zsh`, `01-core.zsh`, `20-git.zsh`). The root `zshrc` will dynamically iterate and source these files.

**Tech Stack:** Zsh, Bash.

---

### Task 1: Create Directory and Scaffold Files

**Files:**

- Create: `zsh/00-tmux.zsh`
- Create: `zsh/01-core.zsh`
- Create: `zsh/10-editor.zsh`
- Create: `zsh/20-git.zsh`
- Create: `zsh/20-docker.zsh`
- Create: `zsh/20-k8s.zsh`
- Create: `zsh/20-dev.zsh`
- Create: `zsh/20-os.zsh`
- Create: `zsh/20-network.zsh`
- Create: `zsh/20-ssh-gpg.zsh`

- [ ] **Step 1: Create directory**

```bash
mkdir -p zsh
```

- [ ] **Step 2: Create empty module files**

```bash
touch zsh/00-tmux.zsh zsh/01-core.zsh zsh/10-editor.zsh zsh/20-git.zsh zsh/20-docker.zsh zsh/20-k8s.zsh zsh/20-dev.zsh zsh/20-os.zsh zsh/20-network.zsh zsh/20-ssh-gpg.zsh
```

- [ ] **Step 3: Commit**

```bash
git add zsh/
git commit -m "feat: scaffold zsh modular directory"
```

---

### Task 2: Extract tmux logic (00-tmux.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/00-tmux.zsh`

- [ ] **Step 1: Extract tmux logic**
      Find the block from the beginning of `zshrc` down to just before `if [ -z $DOTENV_LOADED ]; then`.
      Copy this logic into `zsh/00-tmux.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/00-tmux.zsh
git commit -m "refactor: extract tmux configuration to 00-tmux.zsh"
```

---

### Task 3: Extract Core Logic (01-core.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/01-core.zsh`

- [ ] **Step 1: Extract core logic**
      Extract base exports (`LANG`, `LC_*`, `PATH`), options (`setopt`), `compinit` and completions (`zstyle`), `vcs_info`, history bindings (`select-history`, `fzf-z-search`), `sheldon` initialization, and basic aliases (`cp`, `mv`, `mkdir`, `f`, `rm`, `L`, `mkcd`, `..`, `...`).
      This spans across the `DOTENV_LOADED` block and `ZSH_LOADED` block. Add this to `zsh/01-core.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/01-core.zsh
git commit -m "refactor: extract core zsh configuration to 01-core.zsh"
```

---

### Task 4: Extract Editor Logic (10-editor.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/10-editor.zsh`

- [ ] **Step 1: Extract Editor logic**
      Extract the `if type hx`, `if type nvim`, `if type vim` blocks that set `EDITOR`, `VISUAL`, `PAGER`, and the aliases `nvim`, `vi`, `vim`, `nvinit`, `nvup`, `vedit`, `vake`. Put these into `zsh/10-editor.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/10-editor.zsh
git commit -m "refactor: extract editor configuration to 10-editor.zsh"
```

---

### Task 5: Extract Git Logic (20-git.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/20-git.zsh`

- [ ] **Step 1: Extract Git logic**
      Extract the `if type git` block containing aliases like `gco`, `gsta`, `gcom`, and functions like `gitthisrepo`, `gitdefaultbranch`, `gfr`, `gfrs`, `gcp`, `grs`. Put them into `zsh/20-git.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/20-git.zsh
git commit -m "refactor: extract git configuration to 20-git.zsh"
```

---

### Task 6: Extract Docker Logic (20-docker.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/20-docker.zsh`

- [ ] **Step 1: Extract Docker logic**
      Extract the `if type container` and `if type docker` blocks handling `dls`, `dsh`, and `DOCKER_BUILDKIT`. Put them into `zsh/20-docker.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/20-docker.zsh
git commit -m "refactor: extract docker configuration to 20-docker.zsh"
```

---

### Task 7: Extract Kubernetes Logic (20-k8s.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/20-k8s.zsh`

- [ ] **Step 1: Extract Kubernetes logic**
      Extract the `if type kubectl`, `kind`, `k3d`, `helm`, `skaffold`, `linkerd`, `kustomize`, `octant` blocks. Put them into `zsh/20-k8s.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/20-k8s.zsh
git commit -m "refactor: extract k8s configuration to 20-k8s.zsh"
```

---

### Task 8: Extract Dev Logic (20-dev.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/20-dev.zsh`

- [ ] **Step 1: Extract Dev logic**
      Extract the Rust (`RUST_HOME`), Go (`GOPATH`, `GOROOT`), Clang (`LLVM_HOME`), Python, PHP setups, and the `vald` repository functions (`valdup`, `valddep`, `valdmanifest`). Put them into `zsh/20-dev.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/20-dev.zsh
git commit -m "refactor: extract dev environment configuration to 20-dev.zsh"
```

---

### Task 9: Extract OS/Package Manager Logic (20-os.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/20-os.zsh`

- [ ] **Step 1: Extract OS logic**
      Extract `brewup`, `archup`, `kacman`, `kacclean`, `aptup`, `update_git_repo`, `kpangoup`, `fup` (fwupdmgr), and hardware aliases like `discrete`, `integrated`, `compton`. Put them into `zsh/20-os.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/20-os.zsh
git commit -m "refactor: extract OS updater configuration to 20-os.zsh"
```

---

### Task 10: Extract Network Logic (20-network.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/20-network.zsh`

- [ ] **Step 1: Extract Network logic**
      Extract `nmcli` functions (`nmcliwifie`, `nmcliwifi`, `nmclr`), `tailscaleup`, `wakeonlan` (`p1up`, `trup`), `whois`/`traceroute` (`checkcountry`), and `ciscovpn`. Put them into `zsh/20-network.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/20-network.zsh
git commit -m "refactor: extract network configuration to 20-network.zsh"
```

---

### Task 11: Extract SSH/GPG Logic (20-ssh-gpg.zsh)

**Files:**

- Modify: `zshrc`
- Modify: `zsh/20-ssh-gpg.zsh`

- [ ] **Step 1: Extract SSH/GPG logic**
      Extract `ssh-keygen` wrappers (`rsagen`, `edgen`, `sshperm`), `sshls`, `sshinit`, and the `gpgbackup`/`gpgrestore` functions. Put them into `zsh/20-ssh-gpg.zsh`.

- [ ] **Step 2: Commit**

```bash
git add zsh/20-ssh-gpg.zsh
git commit -m "refactor: extract ssh/gpg configuration to 20-ssh-gpg.zsh"
```

---

### Task 12: Rewrite Root zshrc

**Files:**

- Modify: `zshrc`

- [ ] **Step 1: Replace root zshrc**
      Overwrite `zshrc` to iterate and source the modules dynamically:

```zsh
#!/usr/bin/env zsh

# Determine DOTFILES_DIR
export GIT_USER=kpango
DOTFILE_URL="github.com/$GIT_USER/dotfiles"
if type ghq >/dev/null 2>&1; then
    export DOTFILES_DIR="$(ghq root)/$DOTFILE_URL"
elif [ -d "$HOME/go/src/$DOTFILE_URL" ]; then
    export DOTFILES_DIR="$HOME/go/src/$DOTFILE_URL"
else
    export DOTFILES_DIR="$HOME/dotfiles"
fi

for config_file in "$DOTFILES_DIR/zsh"/*.zsh; do
    source "$config_file"
done

if [ ! -f "$HOME/.zshrc.zwc" -o "$HOME/.zshrc" -nt "$HOME/.zshrc.zwc" ]; then
    zcompile $HOME/.zshrc
fi

if [ ! -f "$HOME/.zcompdump.zwc" -o "$HOME/.zcompdump" -nt "$HOME/.zcompdump.zwc" ]; then
    zcompile $HOME/.zcompdump
fi
```

- [ ] **Step 2: Verify Syntax**
      Run: `zsh -n zshrc`
      Expected: No output (meaning syntax is valid).

- [ ] **Step 3: Commit**

```bash
git add zshrc
git commit -m "refactor: dynamically source modules in root zshrc"
```
