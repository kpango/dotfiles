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

Delegation via `subagent` tool (single, parallel, chain, or DAG workflow mode; supports `agent: 'auto'`) or `/agent [name|auto] <task>` (reference: `agent/ROUTING_CATALOG.md`):

| Agent                               | Purpose                                                                                | Model                                |
| :---------------------------------- | :------------------------------------------------------------------------------------- | :----------------------------------- |
| `go-expert`                         | Go implementation, optimization, testing, debugging                                    | inherit                              |
| `rust-expert`                       | Rust ownership/lifetimes, unsafe code review, cargo                                    | inherit                              |
| `arch-ops`                          | Arch Linux, pacman, systemd, Sway, Docker/containers                                   | haiku                                |
| `security-audit`                    | Vulnerability audit, OWASP, secret detection                                           | sonnet                               |
| `perf-analyzer`                     | pprof, criterion, perf, bottleneck analysis                                            | inherit                              |
| `code-reviewer`                     | Code quality, maintainability, security review (Go/Rust/C++/Python/Zig/K8s)            | sonnet                               |
| `debugger`                          | Root cause analysis, test failure investigation                                        | inherit                              |
| `proto-expert`                      | Protobuf/.proto editing, make proto/all, breaking change detection                     | inherit                              |
| `vald-reviewer`                     | Vald Law enforcement, config sync, K8s resource rules                                  | sonnet                               |
| `ann-perf-engineer`                 | ANN vector search (ArcFlare/NGT/NGTAQ) SIMD kernel opt, ann-benchmarks Pareto analysis | inherit                              |
| `ci-investigator`                   | CI/build pipeline root-cause analysis                                                  | inherit                              |
| `python-expert`                     | Python/PyTorch implementation, packaging, testing, training pipelines                  | inherit                              |
| `cpp-expert`                        | C++ implementation, build-system (CMake/vcpkg/Conan), sanitizers                       | inherit                              |
| `k8s-expert`                        | General Kubernetes manifest/Helm/Kustomize implementation                              | inherit                              |
| `nix-expert`                        | Nix/NixOS/nix-darwin/home-manager implementation                                       | inherit                              |
| `zig-expert`                        | Zig implementation, version-sensitive breaking change awareness                        | inherit                              |
| `github-actions-expert`             | GitHub Actions workflow authoring/design                                               | inherit                              |
| `security-adversarial-reviewer`     | Adversarial security re-review (second line of defense)                                | sonnet                               |
| `architecture-adversarial-reviewer` | Adversarial architecture-consistency review                                            | sonnet                               |
| `perf-simd-adversarial-reviewer`    | Adversarial perf/SIMD re-review                                                        | sonnet                               |
| `code-quality-adversarial-reviewer` | Adversarial code-quality re-review                                                     | sonnet                               |
| `docs-comment-adversarial-reviewer` | Adversarial technical-doc/comment quality review                                       | sonnet                               |
| `systems-lang-adversarial-reviewer` | Adversarial Go/Rust/C++ language-spec review                                           | sonnet                               |
| `shell-config-adversarial-reviewer` | Adversarial Shell/Zsh/Makefile language-spec review                                    | sonnet                               |
| `infra-config-adversarial-reviewer` | Adversarial Nix/Lua/YAML/JSON syntax & schema review                                   | sonnet                               |

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

## Advanced Extension Tools & GrokBot Capabilities

Pi provides an extensive suite of built-in TypeScript extensions and GrokBot-inspired autonomous capabilities:

| Tool                         | Slash Command          | Description & Purpose                                                                                    |
| :--------------------------- | :--------------------- | :------------------------------------------------------------------------------------------------------- |
| `daemon_spawn`               | `/daemon [spawn|...]` | GrokBot-style persistent headless background daemon surviving TTY disconnects with state/log tracking    |
| `mesh_publish`               | `/mesh`                | Publish topic messages (`spec`, `draft`, `critique`, `verification`, `blocker`) to P2P blackboard stream |
| `mesh_query`                 | `/mesh`                | Query correlation event stream on decentralized blackboard                                               |
| `mesh_confidence`            | —                      | Bayesian confidence engine with prior log-odds, tool delta, peer review, and sycophancy penalty          |
| `mesh_handoff`               | —                      | Autonomous peer task handoff finite state machine (`DRAFTING` -> `VERIFYING` -> `REMEDIATING`)           |
| `goal_loop`                  | `/loop`                | Goal-driven iterative loop evaluated after each agent turn with predicate evaluation                     |
| `cancel_goal_loop`           | `/loop stop`           | Cancel active goal loops by ID or all active loops                                                       |
| `repl_filter`                | `/repl`                | High-speed slice/filter/grep for large intercepted command buffers without context pollution             |
| `synthesize_skill`           | `/synthesize`          | Synthesize reusable `SKILL.md` specification from session trace (commands, diffs, evidence)               |
| `skill_state_declare`        | —                      | SKILL.state (arXiv:2608.26263): declare a domain's structured execution-state schema once (paper §3.1)    |
| `skill_state_update`         | —                      | Apply a `ΔΣ` patch (`Σ ⊕ ΔΣ`, null-deletion); runtime-validated with rollback-retry, reasoning discarded  |
| `skill_state_get`            | `/state show`          | Read the current execution state `Σ` (per-turn footprint bounded in turn count vs append-only history)     |
| `skill_state` (auto-context) | `/state autocontext`   | Default ON: a `before_agent_start` hook auto-injects a bounded `Σ` digest each turn (`/state autocontext off`) |
| `run_consensus_verification` | `/consensus`           | 3-model unanimous consensus review (Claude Sonnet 5, Gemini 3.8, GPT-6) on candidate git diff            |
| `run_adversarial_review`     | `/adversarial-review`  | 8-lens multi-perspective adversarial review on current diff before commit/release                         |
| `ast_grep_search`            | `/ast`                 | AST structural code search via tree-sitter patterns                                                       |
| `graphify_query`             | `/graphify query`      | Semantic code entity and community search in `.claude/graph/graphify/graph.json`                         |
| `graphify_explain`           | `/graphify explain`    | Neighborhood relationship and architectural cluster explanation                                          |
| `open_in_helix`              | `/hx <file> [line]`    | Split-pane file navigation in Helix (`hx`) editor via tmux                                               |
| `search_sessions`            | `/sessions <query>`    | Search past conversation sessions in `~/.pi/agent/sessions/` for solutions and decisions                 |
| `harness_refine`             | `/refine`              | Continual harness self-tuning from session error signatures                                              |

## Security & Protection Rules (Pi-specific enforcement)

- **Protected Paths**: Writes to `~/.ssh/**`, `/etc/**`, `.env*`, `*.pem`, `*.key`, `*.kubeconfig`,
  `credentials.json`, `~/.cargo/credentials.toml`, `~/.npmrc` are blocked or require confirmation.
- **Protected Commands**: Destructive disk commands (`dd` to block devices, `mkfs`), force pushes to
  main/master, production namespace deletions, and piped unverified shell scripts (`curl | bash`)
  are blocked.
