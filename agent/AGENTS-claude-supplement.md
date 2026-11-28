## Custom Subagents (`~/.claude/agents/`)

Agents are listed natively with their descriptions; delegate by @-mention (`@"go-expert (agent)" ...`) or natural language.
The 8 `*-adversarial-reviewer` agents are invoked automatically by `/swarm --loop`/`--graph` right before the Phase 5/G5 gate
— never by manual @-mention or auto-delegation.

**When to delegate:**

| Trigger                                                                                                | Agent                                 |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| Implement / optimize / debug Go code                                                                   | `go-expert`                           |
| Rust ownership, lifetimes, unsafe, cargo                                                               | `rust-expert`                         |
| pacman, AUR, systemd, Sway, Wayland, Docker                                                            | `arch-ops`                            |
| UniFi, UDM Pro, GatewayConfigurationError, GeoIP                                                       | `unifi-expert`                        |
| Secret detection, OWASP audit, auth review                                                             | `security-audit`                      |
| pprof, perf, flamegraph, benchmark regression                                                          | `perf-analyzer`                       |
| Code review after writing or modifying code                                                            | `code-reviewer`                       |
| Test failure, panic, unexpected behavior                                                               | `debugger`                            |
| Edit `.proto` files or run `make proto/all`                                                            | `proto-expert`                        |
| Any change in `vald/` repo                                                                             | `vald-reviewer` (post-edit)           |
| ArcFlare/NGT/NGTAQ SIMD kernel or ann-benchmarks work                                                  | `ann-perf-engineer`                   |
| CI red but code looks correct / passes locally, fails in CI                                            | `ci-investigator`                     |
| Implement / optimize / debug Python or PyTorch code                                                    | `python-expert`                       |
| Implement / optimize / debug general C++ code (not ArcFlare/NGT SIMD work)                             | `cpp-expert`                          |
| General Kubernetes manifest/Helm/Kustomize work outside the vald repo                                  | `k8s-expert`                          |
| Nix flake/derivation/module/home-manager work                                                          | `nix-expert`                          |
| Author or restructure a new GitHub Actions workflow (not diagnosing an existing failure)               | `github-actions-expert`               |
| swarm-loop/swarm-graph Phase 5/G5 GATE — adversarial re-review (orchestrator auto-invokes, not manual) | the 8 `*-adversarial-reviewer` agents |

Rules:

- Use `code-reviewer` **proactively** after every non-trivial code change — don't wait to be asked
- Use `vald-reviewer` **proactively** after every edit inside `github.com/vdaas/vald`
- Use `debugger` **before** guessing at a fix — let it identify root cause first
- Use `ci-investigator` instead of `debugger` when the failure is in the CI pipeline/build environment layer rather than application logic
- `arch-ops` uses `low` tier (fast/cheap); use it freely for system ops
- `unifi-expert` operates against a production home-network device — it must get explicit human
  confirmation before any state-changing action (see its own agent definition); always load the
  `unifi-api` skill alongside it rather than duplicating endpoint/credential details in prompts
- Never use `go-expert` for Rust or `rust-expert` for Go — stay within language boundaries (same rule across `python-expert`/`cpp-expert`/`nix-expert`)
- Use `k8s-expert` for general Kubernetes work outside `vdaas/vald`; inside `vdaas/vald`, `vald-reviewer` already covers K8s resource rules alongside Vald Law/config-sync enforcement
- The 8 `*-adversarial-reviewer` agents are for the GATE-immediate adversarial re-review stage only

Agent frontmatter `effort` accepts `low`/`medium`/`high`/`xhigh`/`max`.

## Plugins & Skills Available

- `superpowers`: brainstorming, TDD, debugging, planning workflows
- `claude-mem`: persistent session memory and timeline
- `gopls-lsp`: Go LSP integration
- `clangd-lsp`: C/C++ LSP integration
- `github`: GitHub PR/issue management

@RTK.md

Skills live under `~/.claude/skills/` (34 shared skills — language patterns/testing per language,
security review/scan, deployment, Nix, protobuf, GitHub Actions, benchmarking, plus
the `swarm-*` orchestration family). Skills can be stacked, up to 5 leading skills per command (e.g.
`/golang-patterns /golang-testing implement X`). See `~/.claude/skills/*/SKILL.md` for the full,
current catalog and each skill's trigger.

`/swarm [--auto|--loop|--graph] <goal>` is the single human SWARM entry: it dispatches into `swarm-meta` / `swarm-loop` /
`swarm-graph` (scale → init → explore → plan → execute → checkpoint → adversarial review → gate), and also carries
`--architect`, `--evolve`, `--gate`, `--memory`, `--relay`, `--every`, `--until`, `--stop`. Phases and rules stay in the
delegated `~/.claude/skills/swarm-*/SKILL.md`.

## Hooks

Hooks run automatically; their block/ask messages are self-explanatory. Global: `security-gate.sh` and `write-security-gate.sh`
(Hard Floor, driven by `agent/security-rules.json`), `rtk-rewrite.sh` (test/build/status commands only),
`permission-request.sh`, `swarm-fable-gate.sh` / `swarm-parallel-gate.sh` (Max-model grants, max 3 parallel Makers),
`swarm-write-scope-gate.sh` (Tier B protected paths need a single-use grant), plus lifecycle logging.
Project-level: `swarm-post-edit-lint.sh` (immediate lint) and `swarm-stop-verify.sh` (verify touched files before stopping) in
dotfiles/vald; `vald-law-gate.sh` (Vald Laws 1–5) in vald.

## MCP Servers

MCP servers are consolidated behind a single [Executor](https://executor.sh/) gateway
(`mcpServers.executor`) rather than defined individually per tool — see `agent/README.md` for the
migration details. Tool-specific-only servers not covered by Executor: `lsp-rust`/`k8s`/`slack`.

Allowed filesystem paths: `/home/kpango/go/src/github.com/kpango`,
`/home/kpango/go/src/github.com/vdaas/vald` (`$HOME` itself is intentionally excluded from the
allow-list — see `agent/README.md`'s MCP section for why).

## Memory System

Auto memory is stored per-project under `~/.claude/projects/<project>/memory/`, indexed by
`MEMORY.md` and injected at session start. Update it with `/memory` or by writing directly.

## Multi-Agent Patterns

- **Fork mode**: `CLAUDE_CODE_FORK_SUBAGENT=1` — general-purpose tasks use fork (inherits context)
- **Background isolation**: git worktrees (`bgIsolation: "worktree"`)
- **Independent subtasks**: `superpowers:dispatching-parallel-agents`
- **Teammate mode**: "auto" (uses tmux when available)
- **@-mention**: `@"agent-name (agent)"` for explicit delegation

## Security (Claude Code specifics)

- Security gate hook blocks: `rm -rf /`, fork bombs, `dd` to block devices, force-push to protected
  branches, `curl|wget ... | sh/bash`, `git clean -fdx`, `git add -A/--all/./*` (specific path
  targeting only), kubectl/helm destructive ops in production namespaces
- Security gate hook asks for confirmation on: `git clean -f` (without `-dx`), `git checkout .`
- Write security gate and `permissions.deny` (settings.json) additionally block secret-shaped file
  globs (`.env*`, `*.pem`/`*.key`/`*.p12`/`*.pfx`, `id_rsa`/`id_ed25519`, `.ssh/**`, `.netrc`,
  `*.kubeconfig`, `.kube/config`, `*.tfstate`, `terraform.tfvars`, `.aws/credentials`,
  `.credentials.json`) anywhere on the filesystem, case-insensitively, through symlinks
- **Intentional broad allowances** (personal machine, accepted risk): `Bash(python3 *)`,
  `Bash(node *)`, `Bash(bun *)`, `Bash(bunx *)`, `Bash(cmake *)`, `Bash(make *)`, `Bash(gmake *)`,
  `Bash(ninja *)` — needed for everyday hook/build tooling; accepted rather than closed
- `~/.claude/rules/` holds path-scoped and always-loaded conventions
  (`harness-design.md`/`impact-scope.md`/`verify-before-assert.md`/`performance.md`)
- statusLine (`~/.claude/statusline-command.sh`) shows cwd/git branch+status/model/context-remaining%
