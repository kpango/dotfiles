## External Coding Agent Bridges

Oh My Pi (OMP) can directly orchestrate and delegate to external CLI coding agents via built-in extension tools and slash commands:

| Tool           | CLI Command | Slash Command      | Purpose & Capabilities                                                                                                   |
| -------------- | ----------- | ------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| `claude_code`  | `claude`    | `/claude <prompt>` | Anthropic Claude Code CLI with full agent reasoning, tool execution, and permissions bypass                              |
| `antigravity`  | `agy`       | `/agy <prompt>`    | Google Antigravity CLI with Gemini reasoning (gemini-4-hydrogen / gemini-4-argon), MCP servers, and edit modes           |
| `hermes_query` | `hermes`    | —                  | Hermes Agent / Oh My Hermes (OMH) multi-profile delegation (`chief`, `researcher`, `swe`, `perf`, `sec-reviewer`, `ops`) |

## Tool Usage Discipline (OMP-specific)

- Prefer dedicated tools (`read`, `edit`, `write`) over raw shell commands for file modifications
- Use the `subagent` tool to delegate specialized tasks across isolated context windows

## Specialized Subagents (`~/.omp/agent/agents/`)

Delegate via the `subagent` tool (single, parallel, chain, or DAG mode; `agent: 'auto'`) or `/agent [name|auto] <task>`.
Agent names and descriptions come from `~/.omp/agent/agents/*.md`; routing guidance is in `agent/ROUTING_CATALOG.md`.
The 8 `*-adversarial-reviewer` agents run only at the swarm Phase 5/G5 gate.

`unifi-expert` operates against a production home-network device — it must get explicit human
confirmation before any state-changing action (see its own agent definition); always load the
`unifi-api` skill alongside it rather than duplicating endpoint/credential details in prompts.

## Teamwork-Preview Subagent Bridge

OMP maps to Antigravity `teamwork-preview` archetypes (explorer, orchestrator, spec_miner, test_writer, worker, reviewer,
challenger, auditor, critic); the role table is in `agent/SWARM.md` §9.1.

## Skills & Prompts (`~/.omp/agent/skills/` & `~/.omp/agent/prompts/`)

Skills are listed natively from `~/.omp/agent/skills/`. SWARM has a single human entry, `/swarm`
(`--auto`|`--loop`|`--graph`|`--architect`|`--evolve`|`--gate`|`--memory`|`--relay` <goal>, `--every`/`--until`/`--stop`), which
dispatches into the `swarm-*` protocol skills; the old `/swarm-loop`, `/swarm-graph`, `/swarm-meta` prompt templates are
removed (the protocol skills stay internal, `disable-model-invocation: true`). Other prompt commands: `/review`, `/audit`,
`/architect`, `/claude`, `/agy`; per-language `/<name>-patterns` and `/<name>-testing` skills, plus
`/k8s-patterns`, `/nix-patterns`, `/security-review`, `/benchmark`.

## Advanced Extension Tools & GrokBot Capabilities

Built-in extension tools (schemas are provided by the harness; slash command in parentheses): `daemon_spawn` (`/daemon`),
`mesh_publish` / `mesh_query` (`/mesh`), `mesh_confidence`, `mesh_handoff`, `goal_loop` (`/loop`), `cancel_goal_loop` (`/loop stop`),
`repl_filter` (`/repl`), `synthesize_skill` (`/synthesize`), `skill_state_declare` / `skill_state_update` / `skill_state_get`
(`/state`; Σ digest auto-injected each turn, `/state autocontext off`), `run_consensus_verification` (`/consensus`),
`run_adversarial_review` (`/adversarial-review`), `ast_grep_search` (`/ast`), `open_in_helix` (`/hx`), `search_sessions` (`/sessions`),
`harness_refine` (`/refine`).

## Security & Protection Rules (OMP-specific enforcement)

- **Protected Paths**: Writes to `~/.ssh/**`, `/etc/**`, `.env*`, `*.pem`, `*.key`, `*.kubeconfig`,
  `credentials.json`, `~/.cargo/credentials.toml`, `~/.npmrc` are blocked or require confirmation.
- **Protected Commands**: Destructive disk commands (`dd` to block devices, `mkfs`), force pushes to
  main/master, production namespace deletions, and piped unverified shell scripts (`curl | bash`)
  are blocked.
