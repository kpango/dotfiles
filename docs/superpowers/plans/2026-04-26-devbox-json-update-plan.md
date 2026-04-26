# devbox.json Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `devbox.json` to achieve 100% compatibility with the `kpango/dev` Docker image environment by mapping all tools from the `dockers` directory to Nixpkgs and adding a fallback setup script.

**Architecture:** Add Nixpkgs equivalents for all identified tools to the `packages` array. For tools missing from Nixpkgs or requiring specific installation methods (like global npm AI tools or specific Go tools), configure fallback installations via `bun install`, `cargo install`, `pip install`, and a custom go tools installation script within the `init_hook` and `scripts` blocks of `devbox.json`.

**Tech Stack:** Devbox, Nix, Shell Scripting, devbox.json.

---

### Task 1: Update the `packages` array in `devbox.json`

**Files:**

- Modify: `devbox.json`

- [ ] **Step 1: Write a test (conceptual - verify devbox config is valid JSON before start)**
      Run: `cat devbox.json | jq . > /dev/null`
      Expected: Passes without error.

- [ ] **Step 2: Add C/C++ & Utils from `apt-get` to `packages`**
      Modify `devbox.json` `packages` array to include:

```json
    "automake",
    "bash",
    "cacert",
    "clang-tools",
    "diffutils",
    "ctags",
    "gnumake",
    "gawk",
    "gettext",
    "gfortran",
    "graphviz",
    "libaec",
    "hdf5",
    "lapack",
    "openmp",
    "openblas",
    "openssl",
    "libtool",
    "lua5_4",
    "luajit",
    "luarocks",
    "mariadb-client",
    "mtr",
    "ncurses",
    "nkf",
    "openssh",
    "pass",
    "pinentry",
    "ruby",
    "sass",
    "gnused",
    "gnutar",
    "tig",
    "ugrep",
    "xclip",
    "zip",
```

- [ ] **Step 3: Add NPM Globals & Python tools to `packages`**
      Modify `devbox.json` `packages` array to include:

```json
    "nodePackages.prettier",
    "pyright",
    "nodePackages.typescript",
    "nodePackages.typescript-language-server",
    "nodePackages.bash-language-server",
    "nodePackages.dockerfile-language-server-nodejs",
```

- [ ] **Step 4: Add Rust tools to `packages`**
      Modify `devbox.json` `packages` array to include:

```json
    "bandwhich",
    "bottom",
    "broot",
    "cargo-asm",
    "cargo-binutils",
    "cargo-bloat",
    "cargo-edit",
    "cargo-expand",
    "cargo-machete",
    "cargo-watch",
    "delta",
    "dogdns",
    "erdtree",
    "gping",
    "rnix-lsp",
    "sad",
    "sd",
    "shellharden",
    "stylua",
    "t-rec",
    "tokei",
    "tree-sitter",
    "xh",
```

- [ ] **Step 5: Add Special Binaries & K8s tools to `packages`**
      Modify `devbox.json` `packages` array to include:

```json
    "kubefwd",
    "kubens",
    "krew",
    "kubebox",
    "conftest",
    "linkerd",
    "helm-docs",
    "istioctl",
    "telepresence",
    "containerd",
    "docker-compose",
    "docker-buildx",
```

- [ ] **Step 6: Run `devbox update` or `jq` format check**
      Run: `devbox generate devcontainer` or `cat devbox.json | jq . > /dev/null`
      Expected: Valid JSON and parses correctly.

- [ ] **Step 7: Commit changes**

```bash
git add devbox.json
git commit -m "feat(devbox): map missing apt/cargo/k8s packages to nixpkgs"
```

---

### Task 2: Configure `init_hook` and `scripts` for fallback tools

**Files:**

- Modify: `devbox.json`

- [ ] **Step 1: Write the failing test (Verify tools aren't present yet)**
      Run: `devbox run "command -v mbake"`
      Expected: FAIL (empty or non-zero exit)

- [ ] **Step 2: Update `shell.init_hook` in `devbox.json`**
      Add the following lines to the `init_hook` array in `devbox.json`:

```json
      "export BUN_INSTALL=$HOME/.bun",
      "export PATH=$BUN_INSTALL/bin:$PATH",
      "if ! command -v gemini &> /dev/null; then bun install -g @google/gemini-cli @anthropic-ai/claude-code @github/copilot @openai/codex @qwen-code/qwen-code opencode-ai @byterover/cipher markdownlint-cli; fi",
      "if ! command -v rtk &> /dev/null; then cargo install --force --locked --git https://github.com/rtk-ai/rtk; fi",
      "if ! command -v herdr &> /dev/null; then cargo install --force --git https://github.com/ogulcancelik/herdr; fi",
      "if ! command -v prek &> /dev/null; then cargo install --locked --force --no-default-features prek; fi",
      "if ! command -v mbake &> /dev/null; then pip install mbake --prefix /usr/local || pip install mbake; fi"
```

- [ ] **Step 3: Update `shell.scripts` in `devbox.json`**
      Add/modify the `scripts` object in `devbox.json` to handle Go tools installation:

```json
      "setup": "rustup default nightly && go install github.com/mattn/jvgrep@latest",
      "install_go_tools": "if [ -f dockers/go.tools ]; then cat dockers/go.tools | grep -v '#' | xargs -I {} go install {}; else echo 'dockers/go.tools not found'; fi",
      "update_tools": "go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && devbox run install_go_tools"
```

- [ ] **Step 4: Verify `devbox.json` syntax**
      Run: `cat devbox.json | jq . > /dev/null`
      Expected: Valid JSON.

- [ ] **Step 5: Test the scripts execution (dry-run/print)**
      Run: `devbox run install_go_tools --help` (just to see if Devbox registers the script, it might print help for go install or fail gracefully if `go.tools` parses)
      Expected: Devbox script executes.

- [ ] **Step 6: Commit changes**

```bash
git add devbox.json
git commit -m "feat(devbox): configure fallback init_hooks and setup scripts for missing tools"
```
