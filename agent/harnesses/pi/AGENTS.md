> Generated file — do not edit directly. Canonical sources: `agent/AGENTS.md`
> (generic core) + `agent/AGENTS-pi-supplement.md` (tool-specific supplement).
> Regenerate with `agent/scripts/gen-tool-agents.sh pi`.

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

## External Coding Agent Bridges

Pi can directly orchestrate and delegate to external CLI coding agents via built-in extension tools and slash commands:

| Tool          | CLI Command | Slash Command      | Purpose & Capabilities                                                                                          |
| :------------ | :---------- | :----------------- | :-------------------------------------------------------------------------------------------------------------- |
| `claude_code` | `claude`    | `/claude <prompt>` | Anthropic Claude Code CLI with full agent reasoning, tool execution, and permissions bypass                     |
| `antigravity` | `agy`       | `/agy <prompt>`    | Google Antigravity CLI with Gemini reasoning (gemini-3-pro-preview / 2.5-pro), MCP servers, and plan/edit modes |
| `codex`       | `codex`     | `/codex <prompt>`  | OpenAI Codex CLI with execution sandboxing and live web search                                                  |

## Tool Usage Discipline (Pi-specific)

- Prefer dedicated tools (`read`, `edit`, `write`) over raw shell commands for file modifications
- Use the `subagent` tool to delegate specialized tasks across isolated context windows

## Specialized Subagents (`~/.pi/agent/agents/`)

Delegation via `subagent` tool (single, parallel, or chain mode) or `/agent <name> <task>`:

| Agent                               | Purpose                                                                                | Model                                |
| :---------------------------------- | :------------------------------------------------------------------------------------- | :----------------------------------- |
| `go-expert`                         | Go implementation, optimization, testing, debugging                                    | inherit                              |
| `rust-expert`                       | Rust ownership/lifetimes, unsafe code review, cargo                                    | inherit                              |
| `arch-ops`                          | Arch Linux, pacman, systemd, Sway, Docker/containers                                   | anthropic/claude-3-5-haiku-20241022  |
| `security-audit`                    | Vulnerability audit, OWASP, secret detection                                           | anthropic/claude-3-7-sonnet-20250219 |
| `perf-analyzer`                     | pprof, criterion, perf, bottleneck analysis                                            | inherit                              |
| `code-reviewer`                     | Code quality, maintainability, security review (Go/Rust/C++/Python/Zig/K8s)            | anthropic/claude-3-7-sonnet-20250219 |
| `debugger`                          | Root cause analysis, test failure investigation                                        | inherit                              |
| `proto-expert`                      | Protobuf/.proto editing, make proto/all, breaking change detection                     | inherit                              |
| `vald-reviewer`                     | Vald Law enforcement, config sync, K8s resource rules                                  | anthropic/claude-3-7-sonnet-20250219 |
| `ann-perf-engineer`                 | ANN vector search (ArcFlare/NGT/NGTAQ) SIMD kernel opt, ann-benchmarks Pareto analysis | inherit                              |
| `ci-investigator`                   | CI/build pipeline root-cause analysis                                                  | inherit                              |
| `python-expert`                     | Python/PyTorch implementation, packaging, testing, training pipelines                  | inherit                              |
| `cpp-expert`                        | C++ implementation, build-system (CMake/vcpkg/Conan), sanitizers                       | inherit                              |
| `k8s-expert`                        | General Kubernetes manifest/Helm/Kustomize implementation                              | inherit                              |
| `nix-expert`                        | Nix/NixOS/nix-darwin/home-manager implementation                                       | inherit                              |
| `zig-expert`                        | Zig implementation, version-sensitive breaking change awareness                        | inherit                              |
| `github-actions-expert`             | GitHub Actions workflow authoring/design                                               | inherit                              |
| `security-adversarial-reviewer`     | Adversarial security re-review (second line of defense)                                | anthropic/claude-3-7-sonnet-20250219 |
| `architecture-adversarial-reviewer` | Adversarial architecture-consistency review                                            | anthropic/claude-3-7-sonnet-20250219 |
| `perf-simd-adversarial-reviewer`    | Adversarial perf/SIMD re-review                                                        | anthropic/claude-3-7-sonnet-20250219 |
| `code-quality-adversarial-reviewer` | Adversarial code-quality re-review                                                     | anthropic/claude-3-7-sonnet-20250219 |
| `docs-comment-adversarial-reviewer` | Adversarial technical-doc/comment quality review                                       | anthropic/claude-3-7-sonnet-20250219 |
| `systems-lang-adversarial-reviewer` | Adversarial Go/Rust/C++ language-spec review                                           | anthropic/claude-3-7-sonnet-20250219 |
| `shell-config-adversarial-reviewer` | Adversarial Shell/Zsh/Makefile language-spec review                                    | anthropic/claude-3-7-sonnet-20250219 |
| `infra-config-adversarial-reviewer` | Adversarial Nix/Lua/YAML/JSON syntax & schema review                                   | anthropic/claude-3-7-sonnet-20250219 |

## Teamwork-Preview Subagent Bridge

Pi seamlessly maps to Antigravity `teamwork-preview` subagents and Swarm protocol roles:

| Subagent Archetype              | Swarm Protocol Role         | Purpose & Permissions                                                    |
| :------------------------------ | :-------------------------- | :----------------------------------------------------------------------- |
| `teamwork_preview_explorer`     | Haiku Swarm Exploration     | Read-only survey, wide-area search, and log analysis                     |
| `teamwork_preview_orchestrator` | Secretary & Loop Controller | Aggregation, MAST deduplication, Priority Queue, and `@fix_plan.md`      |
| `teamwork_preview_spec_miner`   | Specification Miner         | Contract, precondition, and invariant extraction                         |
| `teamwork_preview_test_writer`  | TDAD Test Maker (RED)       | Author table-driven unit & integration tests before implementation       |
| `teamwork_preview_worker`       | Maker Implementation        | Minimal surgical code edits in isolated worktrees (GREEN -> REFACTOR)    |
| `teamwork_preview_reviewer`     | Opus Checker                | Independent refutational PASS/FAIL verification (outcome non-disclosure) |
| `teamwork_preview_challenger`   | Adversarial Reviewer        | 8 multi-lens adversarial attacks on candidate diffs                      |
| `teamwork_preview_auditor`      | Law & Invariant Auditor     | Vald Laws 1–5 and repository boundary compliance audit                   |
| `teamwork_preview_critic`       | Fable Architect             | Architecture proposals and spot diagnosis (4 trigger conditions)         |

## Skills & Prompts (`~/.pi/agent/skills/` & `~/.pi/agent/prompts/`)

| Skill / Prompt    | Trigger               | Purpose                                                                                                                                                                                     |
| :---------------- | :-------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `swarm-loop`      | `/swarm-loop <goal>`  | Single entrypoint for autonomous SWARM loop across Scale Assessment, Worktree Isolation, Haiku Exploration, Plan, Maker/Checker Execution, Checkpoint, Adversarial Review, and Release Gate |
| `swarm-graph`     | `/swarm-graph <goal>` | DAG compiled frontier execution with staleness propagation                                                                                                                                  |
| `swarm-meta`      | `/swarm-meta <goal>`  | Meta-harness router selecting swarm-loop vs swarm-graph based on deterministic profiles                                                                                                     |
| `review`          | `/review`             | Multi-perspective code review using `code-reviewer`                                                                                                                                         |
| `audit`           | `/audit`              | Comprehensive security and vulnerability scan                                                                                                                                               |
| `claude`          | `/claude <prompt>`    | Delegate directly to Claude Code CLI                                                                                                                                                        |
| `agy`             | `/agy <prompt>`       | Delegate directly to Google Antigravity CLI                                                                                                                                                 |
| `codex`           | `/codex <prompt>`     | Delegate directly to OpenAI Codex CLI                                                                                                                                                       |
| `architect`       | `/architect`          | Architectural diagnosis and design screening                                                                                                                                                |
| `golang-patterns` | `/golang-patterns`    | Idiomatic Go patterns and best practices                                                                                                                                                    |
| `golang-testing`  | `/golang-testing`     | Go table-driven tests, benchmarks, fuzzing                                                                                                                                                  |
| `rust-patterns`   | `/rust-patterns`      | Rust ownership, traits, concurrency                                                                                                                                                         |
| `rust-testing`    | `/rust-testing`       | Rust unit/integration/async tests                                                                                                                                                           |
| `cpp-patterns`    | `/cpp-patterns`       | Modern C++ idioms, Core Guidelines                                                                                                                                                          |
| `cpp-testing`     | `/cpp-testing`        | GoogleTest/CTest, sanitizers                                                                                                                                                                |
| `python-patterns` | `/python-patterns`    | Pythonic idioms, type hints, PEP 8                                                                                                                                                          |
| `python-testing`  | `/python-testing`     | pytest, fixtures, parametrization                                                                                                                                                           |
| `k8s-patterns`    | `/k8s-patterns`       | Kubernetes manifests, Helm, Operators                                                                                                                                                       |
| `nix-patterns`    | `/nix-patterns`       | Nix flakes, derivations, overlays, home-manager                                                                                                                                             |
| `security-review` | `/security-review`    | OWASP, auth, input validation checklist                                                                                                                                                     |
| `benchmark`       | `/benchmark`          | Performance baselines and regression detection                                                                                                                                              |

## Security & Protection Rules (Pi-specific enforcement)

- **Protected Paths**: Writes to `~/.ssh/**`, `/etc/**`, `.env*`, `*.pem`, `*.key`, `*.kubeconfig`,
  `credentials.json`, `~/.cargo/credentials.toml`, `~/.npmrc` are blocked or require confirmation.
- **Protected Commands**: Destructive disk commands (`dd` to block devices, `mkfs`), force pushes to
  main/master, production namespace deletions, and piped unverified shell scripts (`curl | bash`)
  are blocked.
