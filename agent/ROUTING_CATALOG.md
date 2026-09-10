# SWARM & Pi Agent / Skill Routing Catalog

This catalog is the single source of truth for the complete multi-agent and skill routing topology across kpango's environment. It organizes all **25 specialized agents** and **36 skills** into a unified, autonomous routing matrix orchestrated via `/swarm-meta`.

---

## 1. Architectural Hierarchy & Entrypoints

```
                                      User Goal / Prompt
                                              │
                                              ▼
                                      ┌──────────────┐
                                      │  swarm-meta  │ (Primary Autonomous Meta-Router)
                                      └───────┬──────┘
                                              │ M0 PROFILE & M1 SELECT
                                              ▼
                        ┌───────────────────────────────────────────┐
                        │              Harness Choice               │
                        ├─────────────────────┬─────────────────────┤
                        │     swarm-loop      │     swarm-graph     │
                        │ (Linear State Mach) │ (DAG Compiled Front)│
                        └──────────┬──────────┴──────────┬──────────┘
                                   │                     │
                    ┌──────────────┴─────────────────────┴─────────────┐
                    │               Scale Classification               │
                    ├─────────────────┬─────────────────┬──────────────┤
                    │      Quick      │   Interactive   │   Mission    │
                    │ (Single Maker/  │ (Design Grill + │ (100 Haiku + │
                    │   Checker pass) │   Guided Loop)  │  Full Swarm) │
                    └─────────────────┴────────┬────────┴──────┬───────┘
                                               │               │
                                               ▼               ▼
                                    ┌─────────────────────────────┐
                                    │    Domain Agent Selection   │
                                    │  (Automatic or Specialized) │
                                    └──────────────┬──────────────┘
                                                   │
         ┌──────────────────┬──────────────────────┼──────────────────────┬──────────────────┐
         ▼                  ▼                      ▼                      ▼                  ▼
    Cluster A          Cluster B              Cluster C              Cluster D          Cluster E
 Language Experts   Infra & Systems      Quality & Diagnostic    Gate Adversarial   Orchestration &
 (Go, Rust, C++,    (K8s, Nix, Proto,    (Review, Security, Fix,  Reviewers (8)      Meta-Evolution
  Python, Zig)       CI/CD, ANN, Arch)    Perf, CI, Vald)
```

---

## 2. The 5 Functional Clusters

### Cluster A: Language Specialists (Implementation & Optimization)

| Specialized Agent | Paired Skills | Primary Focus & Capabilities | Default Tier / Model |
| :--- | :--- | :--- | :--- |
| `go-expert` | `golang-patterns`, `golang-testing`, `claude-api-go` | Go implementation, table-driven tests, concurrency, stdlib-first, Anthropic Go SDK | High / Sonnet |
| `rust-expert` | `rust-patterns`, `rust-testing` | Rust ownership, lifetimes, traits, unsafe audits, performance, async testing | High / Sonnet |
| `cpp-expert` | `cpp-patterns`, `cpp-testing` | Modern C++ Core Guidelines, GoogleTest, CMake, sanitizers, low-latency | High / Sonnet |
| `python-expert` | `python-patterns`, `python-testing`, `pytorch-patterns` | Pythonic idioms, pytest, fixtures, PyTorch deep learning pipelines, packaging | High / Sonnet |
| `zig-expert` | `zig-patterns` | Zig comptime, manual memory management, C interop, version tracking | High / Sonnet |

### Cluster B: Infrastructure, Systems & Tooling Specialists

| Specialized Agent | Paired Skills | Primary Focus & Capabilities | Default Tier / Model |
| :--- | :--- | :--- | :--- |
| `k8s-expert` | `k8s-patterns` | General Kubernetes manifests, Helm charts, Kustomize overlays, Operator design | High / Sonnet |
| `nix-expert` | `nix-patterns` | Nix flakes, derivations, overlays, home-manager, reproducible environments | High / Sonnet |
| `github-actions-expert` | `github-actions-patterns`, `deployment-patterns` | GitHub Actions workflow authoring, matrix builds, caching, security hardening | High / Sonnet |
| `proto-expert` | `protobuf-patterns` | Protobuf schema design, `buf lint/breaking`, gRPC service patterns, codegen | High / Sonnet |
| `ann-perf-engineer` | `ann-benchmark-patterns` | ANN vector search (ArcFlare/NGT) SIMD distance kernels, ann-benchmarks Pareto | High / Sonnet |
| `arch-ops` | — | Arch Linux operations (pacman/AUR, systemd, Sway/Wayland, Docker containerd) | Low / Haiku |
| — | `unifi-api` | Ubiquiti UniFi network devices, WiFi, firewall, operational scripts | Skill only |

### Cluster C: Quality, Performance & Diagnostics (First Line of Defense)

| Specialized Agent | Paired Skills | Primary Focus & Role | Default Tier / Model |
| :--- | :--- | :--- | :--- |
| `code-reviewer` | — | Proactive multi-language review (Go/Rust/C++/Python/Zig/K8s) before gate | High / Sonnet |
| `security-audit` | `security-review`, `security-scan`, `security-bounty-hunter` | Vulnerability scanning, OWASP, secret detection, input sanitization | High / Sonnet |
| `debugger` | — | Root-cause analysis, test failure investigation, clean-slate Fixer role | High / Sonnet |
| `perf-analyzer` | `benchmark` | Performance baselines, pprof, criterion, bottleneck identification | High / Sonnet |
| `ci-investigator` | `github-actions-patterns` | CI/build pipeline failure root-cause analysis, toolchain drift diagnosis | High / Sonnet |
| `vald-reviewer` | — (`vald-guard` ext) | Vald Law 1–5 enforcement, config sync protocol, K8s QoS verification | High / Sonnet |

### Cluster D: Gate 4.5 Adversarial Reviewers (Second Line of Defense)

All 8 adversarial reviewers are invoked immediately before the Phase 5 / G5 Gate on the complete candidate diff:

| Reviewer Agent | Paired Skill / Standard | Lens & Scrutiny Dimension | Model & Effort |
| :--- | :--- | :--- | :--- |
| `security-adversarial-reviewer` | `security-review` | Second-line security attack, permission bypasses, secret leaks | Sonnet (High effort) |
| `architecture-adversarial-reviewer`| `harness-design` | Architectural consistency, layer separation, dependency inversion | Sonnet (High effort) |
| `perf-simd-adversarial-reviewer` | `ann-benchmark-patterns` | Performance regressions, SIMD kernel validity, algorithmic complexity | Sonnet (High effort) |
| `code-quality-adversarial-reviewer`| `ponytail-patterns` | Ponytail 7-step anti-overengineering, bloat detection, YAGNI enforcement | Sonnet (High effort) |
| `docs-comment-adversarial-reviewer`| `verify-before-assert` | Documentation overclaims, stale comments, broken cross-references | Sonnet (High effort) |
| `systems-lang-adversarial-reviewer`| Language idioms | Strict Go, Rust, and C++ language specification compliance | Sonnet (High effort) |
| `shell-config-adversarial-reviewer`| POSIX / Zsh specs | Shell, Zsh, and Makefile syntax, portability (GNU vs BSD), set -e | Sonnet (High effort) |
| `infra-config-adversarial-reviewer`| Schema specs | Nix, Lua, YAML, and JSON syntax, schema validity, idiom compliance | Sonnet (High effort) |

### Cluster E: Orchestration, Governance & Meta-Evolution

| Component | Type | Responsibility & Invariant |
| :--- | :--- | :--- |
| `swarm-meta` | Skill & Prompt | 2-stage meta-harness router: extracts M0 profile, selects M1 harness, dispatches M2, records M3, feeds M4 |
| `swarm-loop` | Skill & Prompt | Linear self-driving state machine (SCALE -> INIT -> EXPLORE -> PLAN -> EXECUTE -> CHECKPOINT -> GATE) |
| `swarm-graph` | Skill & Prompt | DAG compiled frontier execution with dynamic replanning and worktree isolation |
| `swarm-explore` | Skill | Haiku wide-area distributed exploration (read-only survey) |
| `swarm-secretary`| Skill | Sonnet noise-reduction, deduplication, and Priority Queue structure generator |
| `swarm-implement`| Skill | Maker (Sonnet) & Checker (Opus) isolated execution loop (max 3 parallel tasks) |
| `swarm-architect`| Skill & Prompt | Fable / High-tier architectural diagnosis, ADR proposals, spot screening |
| `grill-interview`| Skill & Ext | Cognitive drift prevention design-tree interview synthesizing ADR and CONTEXT.md |
| `swarm-release-gate`| Skill | Final deterministic validation (`verify.sh`) and human signoff gate |
| `swarm-evolve` | Skill | Meta-evolution loop generating proposed diffs for SKILL.md and hooks from trajectory logs |
| `swarm-memory-sync`| Skill | Knowledge distillation from completed missions into persistent auto-memory |
| `swarm-relay` | Skill & Ext | Cross-session swarm messaging avoiding git index conflicts and sharing findings |
| `subagent-mesh` | Extension | P2P blackboard pub/sub, Bayesian confidence engine ($C \ge 0.95$), peer handoff state machine |
| `daemon-session` | Extension | Persistent headless background daemon surviving TTY disconnects |
| `loop-controller`| Extension | Turn-by-turn goal-driven iteration predicate evaluation (`goal_loop`) |

---

## 3. Automatic Routing Decision Matrix

When `/swarm-meta` receives a goal, it automatically analyzes keywords, file types, and task characteristics to compose the execution pipeline:

| Detected Goal Signatures | Target Domain | Auto-Dispatched Agent(s) | Associated Skill(s) | Recommended Lens / Verification |
| :--- | :--- | :--- | :--- | :--- |
| Go, golang, `*.go`, `go.mod` | Go Development | `go-expert` | `golang-patterns`, `golang-testing` | `systems-lang-adversarial-reviewer`, `golangci-lint` |
| Rust, cargo, `*.rs`, `Cargo.toml` | Rust Systems | `rust-expert` | `rust-patterns`, `rust-testing` | `systems-lang-adversarial-reviewer`, `cargo clippy/test` |
| C++, cmake, `*.cpp`, `*.h` | Modern C++ | `cpp-expert` | `cpp-patterns`, `cpp-testing` | `systems-lang-adversarial-reviewer`, cmake build |
| Python, pytorch, `*.py` | Python / ML | `python-expert` | `python-patterns`, `python-testing` | pytest, ruff, `code-quality-adversarial-reviewer` |
| Zig, `build.zig`, `*.zig` | Zig Systems | `zig-expert` | `zig-patterns` | `zig build/test` |
| K8s, Helm, manifests, `*.yaml` | Kubernetes | `k8s-expert` | `k8s-patterns` | `infra-config-adversarial-reviewer`, yamllint |
| Nix, flake, `*.nix` | Nix Infrastructure | `nix-expert` | `nix-patterns` | `infra-config-adversarial-reviewer`, `nix eval/build` |
| CI, Workflow, GitHub Actions | CI/CD Automation | `github-actions-expert` | `github-actions-patterns` | actionlint, `infra-config-adversarial-reviewer` |
| Protobuf, gRPC, `*.proto` | Interface Schema | `proto-expert` | `protobuf-patterns` | `buf lint`, `buf breaking`, Vald Law 1 |
| Benchmark, perf, pprof, SIMD | Performance Eng | `perf-analyzer` / `ann-perf-engineer` | `benchmark`, `ann-benchmark-patterns` | `perf-simd-adversarial-reviewer`, criterion |
| Security, CVE, auth, secret | Security Audit | `security-audit` | `security-review`, `security-scan` | `security-adversarial-reviewer` |
| Bug, failure, panic, crash | Root-Cause Fix | `debugger` | — (Fixer clean slate) | `make test`, independent verification |
| Vald, `vdaas/vald` | Vald Core | `vald-reviewer` | — (`vald-guard` ext) | Vald Laws 1–5, config sync, `make test` |
| Arch, pacman, systemd, Sway | OS / Environment | `arch-ops` | — | `systemctl --user`, pacman verify |
| Architecture, ADR, design | System Design | `swarm-architect` | `grill-interview` | `architecture-adversarial-reviewer` |
| Audit, scan, review | Multi-Perspective | `code-reviewer` + `security-audit` | — | 8-lens adversarial review, 3-model consensus |

---

## 4. End-to-End Orchestration Lifecycle

1. **Invocation**: User summons `/swarm-meta <goal>` (or provides natural language task).
2. **M0 PROFILE & M1 SELECT**:
   - `harness-select.sh` deterministically calculates signals (`parallel`, `sequential`, `risk`), estimates task count, identifies affected languages, and queries the historical registry.
   - Outputs harness selection (`swarm-loop` or `swarm-graph`), scale (Quick, Interactive, Mission), budget bounds, and domain agent lenses.
3. **M2 DISPATCH**:
   - Reads selected `SKILL.md` and follows inline state machine.
   - Allocates dedicated mission worktree (`.claude/worktrees/<scale>-<slug>-<timestamp>`), isolating the main tree.
   - In initializes `@fix_plan.md` with `- meta-managed: true` and the `## Harness Plan` block.
4. **Execution Loop**:
   - Swarm Explore (Haiku fan-out) surveys codebase -> Secretary structures Priority Queue.
   - Design Grill (Interactive) clarifies cognitive boundaries -> ADR / CONTEXT.md synthesis.
   - Maker (Sonnet) implements minimal surgical diffs adhering to the Ponytail 7-step logic ladder.
   - Checker (Opus) independently refutes candidate diffs without outcome disclosure.
   - Subagent Mesh orchestrates P2P blackboard events and propagates Bayesian confidence ($C \ge 0.95$).
5. **Phase 4.5 Adversarial Review**:
   - 8-Lens adversarial reviewer agents attack the candidate diff from disjoint orthogonal perspectives.
   - 3-Model unanimous consensus review (Claude Sonnet 5, Gemini 3.8, GPT-6) validates the changes.
6. **Phase 5 Release Gate**:
   - Deterministic verification (`verify.sh`) ensures 100% pass before human signoff.
   - Fast-forward merge to `main` with worktree release.
7. **M3 RECORD & M4 EVOLVE**:
   - `harness-record.sh` logs mission outcome into `harness-registry.tsv`.
   - `harness-status.sh` monitors outcome trends; repeated defects feed `/swarm-evolve` for autonomous harness refinement.
   - `swarm-memory-sync` distills generalizable domain knowledge into `~/.claude/memory/`.

---

## 5. Advanced Runtime Capabilities (Lens Catalog)

The Pi harness runtime layers a set of orthogonal capabilities on top of the routing catalog. Each lens is
independently testable and non-invasive to the routing decision matrix.

| Lens | Capability | Runtime Surface | Behavior |
| :--- | :--- | :--- | :--- |
| 1 | Context & Token Economy | `extensions/context-economy.ts`, `extensions/repl-context.ts`, `capTaskOutput()` in `extensions/subagents.ts` | Large subagent outputs are written to the REPL store (`repl_filter` bufferId hint) while a head/tail summary enters the context window; session token/cache/cost telemetry is exposed via `/economy`. |
| 2 | Fault Recovery & Circuit Breaker | `extensions/lib/cli-bridge.ts`, `extensions/bridge-claude.ts`, `extensions/bridge-antigravity.ts`, `extensions/bridge-codex.ts` | External CLI bridges (`claude`, `agy`, `codex`) get per-binary circuit breakers (3 consecutive failures -> OPEN, 30s cooldown) plus configurable execution timeouts (default 180s) with SIGTERM -> SIGKILL escalation and forced resolution so callers never hang. |
| 3 | Dynamic Capability Negotiation | `resolveAgentTools()` in `extensions/subagents.ts` | Subagents without an explicit `tools:` frontmatter receive a capability-derived default set (reviewer/auditor/security roles get a minimal set without Write/Edit; other roles get the full implementation set); tokens are normalized through `mapToolNames()` before the `--tools` CLI flag. |
| 4 | Mesh Telemetry & Causal DAG | `extensions/lib/subagent-mesh-core.ts` (`validateCausalDagMessages`, `detectStalledHandoffsMessages`) + `extensions/subagent-mesh.ts` | `mesh_query` responses include `dagValid`/`danglingParents`/`cycles` integrity metadata; `/mesh dag <id>` reports causal-DAG integrity and `/mesh stale [ms]` flags correlations idle beyond the threshold (default 5 min). |
| 5 | Editor Ergonomics | `extensions/helix-bridge.ts` | `open_in_helix` accepts a `split` (`h`/`v`) parameter to control tmux split orientation; fallback to standalone `hx` outside tmux remains unchanged. |
| 6 | Deterministic Health Gates | `agent/scripts/test-catalog-health.sh` (invoked via `harness_run_shared_test` by `agent/harnesses/{pi,claude,agy}/validate-harness.sh`) | Machine-checked invariants: every SKILL.md has name/description and its delegated agent references resolve to `agent/agents/*.md`; every agent has unique name, a valid tool vocabulary, and a resolvable model/tier. Coverage of the extension syntax/`execute`-contract check is now complete (all 42 top-level extensions). |
| 7 | Recovery & Duplicate-Run Prevention | `extensions/daemon-session.ts`, `extensions/context-economy.ts` | `daemon_spawn` reuses a live daemon with an identical objective instead of double-spawning; `/tokens` renders the economy report directly instead of round-tripping `sendUserMessage`. |
| 8 | Session-Recall Freshness | `extensions/session-search.ts` | Historical session search sorts by mtime descending before truncation, so `maxResults` always returns the newest matches (readdirSync's name-ascending order used to drop recent sessions); results also carry a `timestamp`. |
| 9 | Worktree-Safe Checkpoints | `extensions/session-tree.ts` | Checkpoint store resolves the git dir via `git rev-parse --git-dir`, so `/checkpoint`, `/cptree`, `/rewind` persist in linked worktrees where `.git` is a file (previously ENOTDIR and always failed). |
| 10 | Honest Consensus Pre-Screen | `extensions/consensus-verifier.ts` | `run_consensus_verification`/`/consensus` report deterministic heuristic results as a PRE-SCREEN (ModelVote.heuristic flag) instead of fabricating a 3-model unanimous consensus; true cross-model review is delegated to the external consensus workflow. |
| 11 | Stale-Read Journal Guard | `extensions/session-journal.ts`, `extensions/lib/session-journal-core.ts` | `checkReplay` accepts `maxAgeMs`: read-only tools (read/grep/find/ls/lsp/graphify) only replay completions newer than the TTL (30s), avoiding stale snapshots after filesystem edits; side-effecting tools keep durable replay. |
| 12 | Executor-Gateway MCP | `extensions/mcp-bridge.ts` | MCP servers are consolidated behind the Executor gateway (`pi/mcp.json` `mcpServers.executor` url); legacy per-server stdio (`command`) entries are also supported. The bridge speaks stateless MCP 2026-07-28 (`server/discover`, `id` on every request, `_meta` protocolVersion) over streamable HTTP with a legacy `initialize` fallback and id-matched SSE decoding; url endpoints are restricted to localhost/127.0.0.1/::1 and HTTP redirects are refused so a repository-controlled mcp.json cannot trigger SSRF. |
