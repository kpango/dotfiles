# Update devbox.json

## Context

The goal is to update the `devbox.json` file to be 100% compatible with the `kpango/dev` Docker image, which is built using the Dockerfiles in the `dockers` directory.

## Findings from Dockerfiles & `go.tools`

The `devbox.json` currently has a subset of the tools. We need to add the following tools to the `devbox.json`:

1.  **From `apt-get install` (C/C++ & Utils):**
    - `automake`, `bash`, `ca-certificates`, `clang-tools` (for `clang-format`, `clang-tidy`, `clangd`), `diffutils`, `ctags` (exuberant-ctags), `g++`, `gawk`, `gcc`, `gettext`, `gfortran`, `graphviz`, `jq`, `less`, `libaec`, `libfp16` (if available, maybe we can skip library devs unless needed for builds), `hdf5`, `lapack`, `openmp` (for `libomp-dev`), `openblas`, `openssl` (libssl-dev), `libtool`, `lua5_4`, `luajit`, `luarocks`, `mariadb-client`, `mtr`, `ncurses` (for `ncurses-term`), `nkf`, `nodejs`, `openssh` (openssh-client), `pass`, `perl`, `pinentry-curses` or `pinentry-tty`, `python3` (with dev/pip/setuptools), `ruby`, `sass`, `sed`, `tar`, `tig`, `tmux`, `ugrep`, `xclip`, `zip`.

2.  **From `bun install -g` (NPM Globals):**
    - `prettier`, `pyright`, `markdownlint-cli`, `dockerfile-language-server-nodejs`, `bash-language-server`, `typescript`, `typescript-language-server`.
    - _AI Tools (will be added via `init_hook` bun install):_ `opencode-ai`, `@anthropic-ai/claude-code`, `@byterover/cipher`, `@github/copilot`, `@google/gemini-cli`, `@google/jules`, `@openai/codex`, `@qwen-code/qwen-code`.

3.  **From `pip install`:**
    - `mbake` (via pip in `init_hook` if needed, but preferable to use python packages if in nix, but mbake isn't in nixpkgs).

4.  **From `cargo install`:**
    - `bandwhich`, `bat`, `bottom` (btm), `broot`, `cargo-asm` (cargo-show-asm), `cargo-binutils`, `cargo-bloat`, `cargo-check` (cargo-tarpaulin etc., usually `cargo check` is built-in. Let's use `cargo-edit`, `cargo-expand`, `cargo-machete`, `cargo-watch`, `cargo-tree` (built-in usually, but we'll add if separate)).
    - `delta` (git-delta), `dogdns` (dog), `dutree`, `erdtree` (erd), `eza`, `fd`, `gping`, `helix` (hx), `herdr`, `hyperfine`, `lsd`, `prek` (might not be in nixpkgs), `procs`, `ripgrep` (rg), `ripgrep-all` (rga), `rnix-lsp`, `rtk` (rtk-ai), `sad`, `sd`, `sheldon`, `shellharden`, `starship`, `stylua`, `t-rec`, `tokei`, `tree-sitter` (tree-sitter-cli), `xh`.

5.  **From `go.tools` (Go tools):**
    - `gqlgen`, `dbmate`, `ghz`, `buf`, `gotests`, `direnv`, `grpcurl`, `hub`, `delve`, `go-task`, `hugo`, `mockgen`, `yamlfmt`, `gotestfmt`, `helmfile`, `kubecolor`, `kubeval`, `evans`, `duf`, `gocode`, `actionlint`, `gosec`, `golines`, `goreturns`, `vegeta`, `prototool`, `ghq`, `govulncheck`, `gofumpt`, `shfmt`, `kind`, `kustomize`.
    - _Note: Many of these are already built into `devbox.json`'s package list, but we'll use a `init_hook` bash script to `go install` from the `dockers/go.tools` file directly to ensure we don't miss any obscure ones, or map the major ones to `devbox.json` `packages` list._

6.  **From `k8s.Dockerfile` / `docker.Dockerfile` / `go.Dockerfile` (Special Binaries):**
    - `kubectl`, `helm`, `kubefwd`, `kubectx`, `kubens`, `krew`, `kubebox`, `stern`, `kubebuilder`, `k9s`, `conftest`, `linkerd`, `skaffold`, `kube-linter`, `helm-docs`, `kubectl-gadget` (inspektor-gadget), `kdash`, `kubectl-rolesum` (Ladicle/kubectl-rolesum), `istioctl` (istio), `k3d`, `telepresence`.
    - `trivy`, `dive`, `slim` (slimtoolkit), `docker-credential-pass`, `docker-compose`, `docker-buildx`, `containerd`.
    - `fzf`, `gh`, `golangci-lint`, `pulumi`, `tinygo`, `dagger`.
    - `zig`, `zls`, `protoc` (protobuf).
    - `faiss`, `ngt`, `usearch` (these are C++ libraries for `vald`, usually we can just install the dev headers if available in nixpkgs: `faiss`, `ngt` doesn't exist in nixpkgs probably).

## Proposed Design Approach

Since the user wants **EVERY SINGLE TOOL** mapped exactly to Nixpkgs if possible, and fallback to Option 2 if not, here is the design:

### 1. The `packages` Array in `devbox.json`

We will massively expand the `packages` list. We will translate the tools into their Nixpkgs names.
Examples:

- `libomp-dev` -> `openmp`
- `ripgrep_all` -> `ripgrep-all`
- `git-delta` -> `delta`
- `rg` -> `ripgrep`
- NPM CLI tools -> `nodePackages.prettier`, `pyright`, `nodePackages.typescript`, etc.

### 2. The `init_hook` (Option 2 Fallback)

For tools that are highly customized (like AI CLIs from bun, or specific go tools from `go.tools`, or `rtk`), we will add a fallback installation block in the `init_hook` of `devbox.json`.

```json
"init_hook": [
    "... existing hooks ...",
    "export BUN_INSTALL=$HOME/.bun",
    "export PATH=$BUN_INSTALL/bin:$PATH",
    "if ! command -v gemini &> /dev/null; then bun install -g @google/gemini-cli @anthropic-ai/claude-code @github/copilot @openai/codex @qwen-code/qwen-code opencode-ai @byterover/cipher; fi",
    "if ! command -v rtk &> /dev/null; then cargo install --force --locked --git https://github.com/rtk-ai/rtk; fi",
    "if ! command -v herdr &> /dev/null; then cargo install --force --git https://github.com/ogulcancelik/herdr; fi",
    "if ! command -v prek &> /dev/null; then cargo install --locked --force --no-default-features prek; fi",
    "if ! command -v mbake &> /dev/null; then pip install mbake; fi"
]
```

For `go.tools`, since it's a file, we can add a script to iterate over it and install the tools that might be missing from Nix:

```json
"scripts": {
    "setup": "rustup default nightly && go install github.com/mattn/jvgrep@latest",
    "install_go_tools": "cat dockers/go.tools | grep -v '#' | xargs -I {} go install {}"
}
```

## Are you okay with this design?

Please review this written spec. If approved, I will implement it.
