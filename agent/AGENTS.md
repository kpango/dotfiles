# Global Agent Instructions

Shared instructions for any AI coding agent (Claude Code, Codex, Antigravity, Pi Coding Agent, or
others) operating in kpango's environment. This file follows the open [AGENTS.md](https://agents.md)
convention — plain Markdown, no tool-specific syntax, readable by any agent that supports the
format. Tool-specific supplementary instructions (hook names, MCP schemas, subagent invocation
syntax, slash commands) live in `agent/AGENTS-<tool>-supplement.md` and are combined with this file
per tool — see `agent/README.md` for how each tool wires the two together.

## Identity & Context

- User: kpango (Yusuke Kato, yusukato@lycorp.co.jp)
- Platform: Arch Linux (zen kernel), Wayland/Sway, Ghostty terminal, Tmux
- Languages: Go (primary), Rust, C/C++, Python, TypeScript, Nix, Zsh
- Editors: Helix (`hx`, primary), VS Code (secondary)
- Shell: Zsh with Sheldon plugin manager, Atuin history
- Dotfiles: `/home/kpango/go/src/github.com/kpango/dotfiles`
- Go workspace: `/home/kpango/go/src/github.com/kpango/`

## Response Style

- Respond in Japanese by default; switch to English for code, commands, and technical identifiers
- Be concise and direct — no unnecessary preamble or trailing summaries
- Prefer code over prose for technical explanations
- No emojis unless explicitly requested

## Development Environment

- Package manager: pacman / AUR (paru)
- Container runtime: Docker (containerd backend)
- Build tools: Make (with `Makefile.d/` modular structure), Go toolchain, Bun
- Version control: Git with `gh` CLI

## Required External Tools

Most hooks/skills fail open (the feature they power is silently skipped) when a tool below is
missing, rather than failing the whole session — but that means a missing tool quietly disables
whatever it powers, so keep this list current.

| Tool            | Purpose                                        | Installation                                                                                                                    |
| --------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `rtk`           | Bash command token optimization                | `paru -S rtk-ai-bin`                                                                                                            |
| `graphify`      | Knowledge graph CLI                            | zsh wrapper (`pass show ai/agy` for an API key) / `pip install graphify`                                                        |
| `codegraph`     | Code navigation (via the Executor MCP gateway) | `bun install -g @colbymchenry/codegraph`                                                                                        |
| `golangci-lint` | Go lint                                        | official install script                                                                                                         |
| `hadolint`      | Dockerfile lint                                | `paru -S hadolint-bin`                                                                                                          |
| `buf`           | Protobuf lint / breaking-change detection      | `go install github.com/bufbuild/buf/cmd/buf@latest`                                                                             |
| `dlv`           | Go debugger                                    | `go install github.com/go-delve/delve/cmd/dlv@latest`                                                                           |
| `jq`            | JSON processing (used by many hooks)           | `pacman -S jq`                                                                                                                  |
| `flock`         | File locking for budget counters (util-linux)  | usually preinstalled on Linux; `brew install flock` on macOS (the standalone formula, not the keg-only/shadowed util-linux one) |

`graphify`/`pass` depend on this personal environment's secret management (`pass show ai/agy`);
substitute your own API-key source to reproduce this setup elsewhere.

## Code Style Preferences

- Go: standard library first, minimal dependencies, table-driven tests
- Shell: POSIX-compatible where possible, prefer zsh builtins
- Comments: only when "why" is non-obvious; no docstrings for obvious functions
- No backwards-compatibility shims for dead code
- Trust internal invariants — validate only at system boundaries
- **Think before coding**: understand the full problem, identify constraints, plan the approach before touching code
- **Simplicity first**: the best code is no code; prefer the simplest solution that correctly solves the problem
- **Surgical changes**: make the minimal diff that achieves the goal — avoid unnecessary refactoring
- **Read before write**: search and read all relevant code before writing a single line — never guess structure
- **No scope drift**: stay within task boundaries; don't refactor, rename, or improve adjacent code unless asked
- **Verify independently**: run tests/build to confirm correctness — don't assume it works
- **No vibe coding**: if uncertain about a behavior, investigate (search, read, test) — never hallucinate an answer

## Tool Usage

- Prefer dedicated file read/write/edit tools over raw shell commands for file operations
- Run independent operations in parallel when there is no dependency between them
- Use `make` targets for installation and configuration tasks, never manual symlinks
- Use `gh` CLI for GitHub operations
- Write descriptive commit messages; run the relevant tests/lints before committing

## Specialized Subagents & Skills

This environment maintains a shared library of specialized subagents (Go/Rust/C++/Python/Nix/Zig
experts, `security-audit`, `code-reviewer`, `debugger`, `perf-analyzer`, `ci-investigator`, and 8
adversarial reviewers used at the SWARM Phase 5/G5 gate, among others) and domain-pattern skills
(language idioms, testing conventions, security review, deployment, protobuf, Kubernetes, Nix,
benchmarking) under `agent/agents/` and `agent/skills/` in the dotfiles repo. See the tool-specific
supplement for the exact invocation syntax and the full, current list.

## Vald Law (when working in `vdaas/vald`)

1. Never edit generated `*.pb.go` / `*_vtproto.pb.go` directly — edit `.proto` and run `make proto/all`.
2. Never run `go build` / `cargo build` / `kubectl apply` / `helm install` directly in `vdaas/vald` — use `make` targets.
3. Never introduce a bare `panic()` in a production code path.
4. Never call `log.Fatal()` outside `main()`.
5. Never silently discard an error (`_ = err`) — handle or propagate it.

## Multi-Agent Principles

- Isolate background or parallel work in a git worktree rather than sharing a working tree
- Independent subtasks may run concurrently; dependent ones must run in sequence
- Delegate specialized work (language experts, security review, performance analysis) to the
  matching subagent rather than doing it inline

## Security

- Never commit secrets, tokens, or credentials
- Destructive commands — recursive `rm`/`chmod` on system paths, force-push to protected branches,
  unverified `curl | sh`, mass `git add` (`-A`/`--all`/`.`), production-namespace `kubectl`/`helm`
  deletes — require confirmation or are blocked outright; see the tool-specific supplement for the
  exact enforcement mechanism
- Writes to credential/key paths (`~/.ssh/`, `~/.gnupg/`, `~/.aws/`, `~/.kube/config`, `.env*`,
  `*.pem`/`*.key`/`*.p12`/`*.pfx`, Terraform state/vars, `~/.cargo/credentials`, `~/.npmrc`, etc.)
  are blocked
- `.credentials.json` and equivalent session credentials are never managed in dotfiles — handled by
  each tool's own login flow
- A root session shares this configuration via symlink, not a separate copy
