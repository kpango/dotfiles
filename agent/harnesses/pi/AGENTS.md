> Generated file — do not edit directly. Canonical sources: `agent/AGENTS.md`
> (generic core) + `agent/AGENTS-pi-supplement.md` (tool-specific supplement).
> Regenerate with `agent/scripts/gen-tool-agents.sh pi`.

# Global Agent Instructions

Shared instructions for any AI coding agent (Claude Code, Oh My Pi, Antigravity, Hermes Agent, or
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

| Tool            | Purpose                                                                                                                   | Installation                                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `rtk`           | Bash command token optimization                                                                                           | `paru -S rtk-ai-bin`                                                                                                            |
| `codegraph`     | Code navigation (via the Executor MCP gateway)                                                                            | `bun install -g @colbymchenry/codegraph`                                                                                        |
| `trail`         | Trail-Code code context graph CLI + `trail mcp` stdio server (Pi: `mcp.json`, AGY: `mcp_config.json`, Claude: hooks only) | `bun add -g @trailhq/trail-code`                                                                                                |
| `golangci-lint` | Go lint                                                                                                                   | official install script                                                                                                         |
| `hadolint`      | Dockerfile lint                                                                                                           | `paru -S hadolint-bin`                                                                                                          |
| `buf`           | Protobuf lint / breaking-change detection                                                                                 | `go install github.com/bufbuild/buf/cmd/buf@latest`                                                                             |
| `dlv`           | Go debugger                                                                                                               | `go install github.com/go-delve/delve/cmd/dlv@latest`                                                                           |
| `jq`            | JSON processing (used by many hooks)                                                                                      | `pacman -S jq`                                                                                                                  |
| `flock`         | File locking for budget counters (util-linux)                                                                             | usually preinstalled on Linux; `brew install flock` on macOS (the standalone formula, not the keg-only/shadowed util-linux one) |

`pass` itself depends on this personal environment's secret management (`pass show ai/agy` was
previously also graphify's API-key source before graphify's retirement); substitute your own
API-key source to reproduce this setup elsewhere.

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

## Standing Approval for Agent Configuration Maintenance

- During a user-requested task, proceed without another confirmation for scoped, reversible maintenance
  of repository-managed agent files: skill explanations and examples, tests that preserve coverage,
  and synchronization or compatibility fixes that preserve tool and approval behavior.
- Inspect the diff and run the relevant checks in the isolated checkout. For a protected file, use the
  existing write-scope procedure; this standing approval covers only edits within the scope above.
- Do not use this approval for changes to permissions, tool or MCP auto-enablement, approval policy,
  security hooks or gate criteria, or for self-modification by an active workflow. Keep their existing
  approval requirements. Deployment to live configuration, merge, and push remain separate decisions.

## Tool Usage

- Prefer dedicated file read/write/edit tools over raw shell commands for file operations
- Run independent operations in parallel when there is no dependency between them
- Use `make` targets for installation and configuration tasks, never manual symlinks
- Use `gh` CLI for GitHub operations
- Write descriptive commit messages; run the relevant tests/lints before committing

## Specialized Subagents & Skills

This environment maintains a shared library of specialized subagents (Go/Rust/C++/Python/Nix
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

Pi (`@earendil-works/pi-coding-agent`) can directly orchestrate and delegate to external CLI coding agents via built-in extension tools and slash commands:

| Tool              | CLI Command | Slash Command       | Purpose & Capabilities                                                                                                                                                                                                 |
| ----------------- | ----------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude_code`     | `claude`    | `/claude <prompt>`  | Anthropic Claude Code CLI with full agent reasoning, tool execution, and permissions bypass                                                                                                                            |
| `antigravity_cli` | `agy`       | `/agy-cli <prompt>` | Google Antigravity CLI with Gemini reasoning (gemini-4-hydrogen / gemini-4-argon), MCP servers, and edit modes (`/agy` + `antigravity` tool are reserved for `pi-antigravity-bridge` ACP interactive `/model` routing) |
| `hermes_query`    | `hermes`    | —                   | Hermes Agent / Oh My Hermes (OMH) multi-profile delegation (`chief`, `researcher`, `swe`, `perf`, `sec-reviewer`, `ops`)                                                                                               |

### Google AI Ultra / Antigravity Auth Policy

- Interactive `agy acp` / `/model` routing uses the pinned `npm:@estebanforge/pi-antigravity-bridge@1.16.0` package in `~/.pi/agent/settings.json`.
- Autonomous unattended SWARM loops MUST stay on official API / OAuth providers (`anthropic`, `openai-codex`, `opencode-go`, `ollama`) per Google Antigravity ToS Section 6.
- Upstream native Google AI Ultra auth issue tracking is recorded in `agent/context/pi-google-ai-ultra-tracking.md`.

## Tool Usage Discipline (Pi-specific)

- Prefer dedicated tools (`read`, `edit` with Hashline `anchor`, `write`) over raw shell commands for file modifications
- Use `role/*` virtual models (`role/default`, `role/slow`, `role/plan`, `role/good`, `role/smol`, `role/fast`, `role/review`, `role/judge`, `role/tiny`, `role/memory`) via the local `model-roles.ts` extension
- Use the `subagent` tool to delegate specialized tasks across isolated context windows

## Specialized Subagents (`~/.pi/agent/agents/`)

Delegate via the `subagent` tool (single, parallel, chain, or DAG mode; `agent: 'auto'`) or `/agent-list [name|auto] <task>`.
Agent names and descriptions come from `~/.pi/agent/agents/*.md`; routing guidance is in `agent/ROUTING_CATALOG.md`.
The 8 `*-adversarial-reviewer` agents run only at the swarm Phase 4.5/G4.5 gate.

`unifi-expert` operates against a production home-network device — it must get explicit human
confirmation before any state-changing action (see its own agent definition); always load the
`unifi-api` skill alongside it rather than duplicating endpoint/credential details in prompts.

## Teamwork-Preview Subagent Bridge

Pi maps to Antigravity `teamwork-preview` archetypes (explorer, orchestrator, spec_miner, test_writer, worker, reviewer,
challenger, auditor, critic); the role table is in `agent/SWARM.md` §9.1.

## Skills & Prompts (`~/.pi/agent/skills/` & `~/.pi/agent/prompts/`)

Skills are listed natively from `~/.pi/agent/skills/`. SWARM has a single human entry, `/swarm`
(`--auto`|`--loop`|`--graph`|`--architect`|`--evolve`|`--gate`|`--memory`|`--relay` <goal>, `--every`/`--until`/`--stop`), which
dispatches into the `swarm-*` protocol skills; the old `/swarm-loop`, `/swarm-graph`, `/swarm-meta` prompt templates are
removed (the protocol skills stay internal, `disable-model-invocation: true`). Other prompt commands: `/review`, `/audit`,
`/architect`, `/claude`, `/agy-cli`, `/agy`; per-language `/<name>-patterns` and `/<name>-testing` skills, plus
`/k8s-patterns`, `/nix-patterns`, `/security-review`, `/benchmark`.

## Self-Hosted Local Extensions & Advanced Capabilities

All Pi IDE/harness enhancements are self-hosted under `~/.pi/agent/extensions/`:

- **Hashline Edit (`hashline-edit.ts`)**: `LINE#HASH` content-addressed editing via `edit(path, anchor, ...)` and `read` annotated output.
- **LSP (`lsp-client.ts`)**: JSON-RPC 2.0 `lsp` tool driven by `~/.pi/agent/lsp.json` (`gopls`, `rust-analyzer`, `clangd`, `basedpyright`, `typescript-language-server`, `nixd`, `lua-language-server`, `bash-language-server`).
- **DAP (`dap-client.ts`)**: Debug Adapter Protocol `debug` tool driven by `~/.pi/agent/dap.json` (`dlv` TCP socket, `lldb-dap` stdio).
- **TTSR Guard (`ttsr-guard.ts`)**: Stream/tool regex rules from `agent/rules/*-ttsr.md` (Vald Laws 1–5).
- **Virtual Model Roles (`model-roles.ts`)**: `role/*` virtual models resolved from `agent/models/catalog.json` `pi_config.modelRoles`.
- **SWARM & GrokBot**: `daemon_spawn` (`/daemon`), `mesh_publish` / `mesh_query` (`/mesh`), `mesh_confidence`, `mesh_handoff`, `goal_loop` (`/loop`), `cancel_goal_loop` (`/loop stop`), `repl_filter` (`/repl`), `synthesize_skill` (`/synthesize`), `skill_state_declare` / `skill_state_update` / `skill_state_get` (`/state`), `run_consensus_verification` (`/consensus`), `run_adversarial_review` (`/adversarial-review`), `evidence-ledger.ts` (artifact SHA-256 verification), `ast_grep_search` (`/ast`), `open_in_helix` (`/hx`), `search_sessions` (`/sessions`), `harness_refine` (`/refine`).

## Security & Protection Rules (Pi-specific enforcement)

- **Protected Paths**: Writes to `~/.ssh/**`, `/etc/**`, `.env*`, `*.pem`, `*.key`, `*.kubeconfig`,
  `credentials.json`, `~/.cargo/credentials.toml`, `~/.npmrc` are blocked or require confirmation.
- **Protected Commands**: Destructive disk commands (`dd` to block devices, `mkfs`), force pushes to
  main/master, production namespace deletions, and piped unverified shell scripts (`curl | bash`)
  are blocked.
