# Dotfiles Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refine dotfiles by extracting Ghostty theme, updating docs, tweaking Helix/Tmux settings, and adding Lumen as the global pager.

**Architecture:** Configuration file modifications and adding a new build stage to the Rust Dockerfile for Lumen.

**Tech Stack:** zsh, ghostty, helix, tmux, docker, rust, git

---

### Task 1: Update README.md with Prompt Info

**Files:**

- Modify: `README.md`

- [ ] **Step 1: Replace Starship prompt mention with PRMT**

Use `replace` tool to change the prompt description in `README.md`.

```markdown
- **Prompt:** Custom optimized inline prompt (`prmt`).
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update prompt info to prmt in README"
```

### Task 2: Extract Ghostty Theme

**Files:**

- Create: `ghostty/themes/zed_kpango`
- Modify: `ghostty.conf`

- [ ] **Step 1: Create theme file**

Create `ghostty/themes/zed_kpango` with the palette configuration.

```conf
palette = 0=#000000
palette = 1=#fc4346
palette = 2=#50fb7c
palette = 3=#f0fb8c
palette = 4=#49baff
palette = 5=#fc4cb4
palette = 6=#8be9fe
palette = 7=#ededec
palette = 8=#555555
palette = 9=#fc4346
palette = 10=#50fb7c
palette = 11=#f0fb8c
palette = 12=#49baff
palette = 13=#fc4cb4
palette = 14=#8be9fe
palette = 15=#ededec
background = #1f1f1f
foreground = #ebece6
cursor-color = #e4e4e4
cursor-text = #f6f6f6
selection-background = #3a3d41
selection-foreground = #e0e0e0
```

- [ ] **Step 2: Update ghostty.conf**

Remove the hardcoded palette and color lines in `ghostty.conf` and replace them with:

```conf
theme = zed_kpango
```

- [ ] **Step 3: Commit**

```bash
git add ghostty/themes/zed_kpango ghostty.conf
git commit -m "style: extract ghostty colors into zed_kpango theme"
```

### Task 3: Editor & Tmux Polish

**Files:**

- Modify: `helix/config.toml`
- Modify: `tmux.conf.d/options.conf`

- [ ] **Step 1: Enable whitespace rules in Helix**

Uncomment `trim-trailing-whitespace` and `trim-final-newlines` in `helix/config.toml`.

- [ ] **Step 2: Add clipboard setting in Tmux**

Append `set -s set-clipboard on` to `tmux.conf.d/options.conf`.

- [ ] **Step 3: Commit**

```bash
git add helix/config.toml tmux.conf.d/options.conf
git commit -m "chore: enable helix whitespace trimming and tmux clipboard integration"
```

### Task 4: Install and Configure Lumen

**Files:**

- Modify: `dockers/rust.Dockerfile`
- Modify: `gitconfig`

- [ ] **Step 1: Add Lumen build stage to rust.Dockerfile**

Insert a new stage for `lumen` before the `rust-base-bins` stage.

```dockerfile
FROM rust-base AS lumen
RUN --mount=type=cache,id=cargo-registry-${TARGETARCH},target=${CARGO_HOME}/registry,sharing=locked \
    --mount=type=cache,id=cargo-git-${TARGETARCH},target=${CARGO_HOME}/git,sharing=locked \
    --mount=type=secret,id=gat \
    GITHUB_TOKEN=$(cat /run/secrets/gat) cargo install --git https://github.com/jnsahaj/lumen \
    && (upx --best ${BIN_PATH}/lumen || true)
```

And add the copy line in the final `FROM scratch AS rust` stage:

```dockerfile
COPY --link --from=lumen ${BIN_PATH}/lumen ${BIN_PATH}/lumen
```

- [ ] **Step 2: Update gitconfig pager**

Change `pager = unk diff` in `gitconfig` to `pager = lumen`.

- [ ] **Step 3: Commit**

```bash
git add dockers/rust.Dockerfile gitconfig
git commit -m "feat: install and configure lumen as default git pager"
```
