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
