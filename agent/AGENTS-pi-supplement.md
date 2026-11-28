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
