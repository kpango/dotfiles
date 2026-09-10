## Custom Subagents (`~/.claude/agents/`)

Specialized agents available for delegation — use @-mention or natural language:

| Agent                               | Purpose                                                                                                                                                                            | Model                 |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| `go-expert`                         | Go implementation, optimization, testing, debugging                                                                                                                                | inherit (high effort) |
| `rust-expert`                       | Rust ownership/lifetimes, unsafe code review, cargo                                                                                                                                | inherit (high effort) |
| `arch-ops`                          | Arch Linux, pacman, systemd, Sway, Docker/containers                                                                                                                               | haiku                 |
| `security-audit`                    | Vulnerability audit, OWASP, secret detection                                                                                                                                       | sonnet                |
| `perf-analyzer`                     | pprof, criterion, perf, bottleneck analysis                                                                                                                                        | inherit               |
| `code-reviewer`                     | Code quality, maintainability, security review (Go/Rust/C++/Python/Zig/K8s)                                                                                                        | sonnet                |
| `debugger`                          | Root cause analysis, test failure investigation                                                                                                                                    | inherit               |
| `proto-expert`                      | Protobuf/.proto editing, make proto/all, breaking change detection                                                                                                                 | inherit               |
| `vald-reviewer`                     | Vald Law enforcement, config sync, K8s resource rules                                                                                                                              | sonnet                |
| `ann-perf-engineer`                 | ANN vector search (ArcFlare/NGT/NGTAQ) SIMD kernel opt, ann-benchmarks Pareto analysis                                                                                             | inherit (high effort) |
| `ci-investigator`                   | CI/build pipeline root-cause analysis (vald/dotfiles), distinct from debugger                                                                                                      | inherit (high effort) |
| `python-expert`                     | Python/PyTorch implementation, packaging, testing, training pipelines                                                                                                              | inherit (high effort) |
| `cpp-expert`                        | C++ implementation, build-system (CMake/vcpkg/Conan), sanitizers                                                                                                                   | inherit (high effort) |
| `k8s-expert`                        | General Kubernetes manifest/Helm/Kustomize implementation, distinct from vald-reviewer                                                                                             | inherit (high effort) |
| `nix-expert`                        | Nix/NixOS/nix-darwin/home-manager implementation                                                                                                                                   | inherit (high effort) |
| `zig-expert`                        | Zig implementation, version-sensitive (breaking changes frequent)                                                                                                                  | inherit (high effort) |
| `github-actions-expert`             | GitHub Actions workflow authoring/design, distinct from ci-investigator                                                                                                            | inherit (high effort) |
| `security-adversarial-reviewer`     | Adversarial security re-review — second line of defense with `security-audit`                                                                                                      | sonnet                |
| `architecture-adversarial-reviewer` | Adversarial architecture-consistency review — new coverage area                                                                                                                    | sonnet                |
| `perf-simd-adversarial-reviewer`    | Adversarial perf/SIMD re-review — second line of defense with `perf-analyzer`/`ann-perf-engineer`                                                                                  | sonnet                |
| `code-quality-adversarial-reviewer` | Adversarial code-quality re-review — second line of defense with `code-reviewer`                                                                                                   | sonnet                |
| `docs-comment-adversarial-reviewer` | Adversarial technical-doc/comment quality review — new coverage area                                                                                                               | sonnet                |
| `systems-lang-adversarial-reviewer` | Adversarial Go/Rust/C++ language-spec review — second line of defense with `go-expert`/`rust-expert`/`cpp-expert`/`code-reviewer`                                                  | sonnet                |
| `shell-config-adversarial-reviewer` | Adversarial Shell/Zsh/Makefile language-spec review — new coverage area                                                                                                            | sonnet                |
| `infra-config-adversarial-reviewer` | Adversarial Nix/Lua/YAML/JSON syntax & schema review — second line of defense with `nix-expert` for Nix, new coverage area for Lua/YAML/JSON; non-overlapping with `vald-reviewer` | sonnet                |

Of the 8 `*-adversarial-reviewer` agents above, 5 (`security`/`perf-simd`/`code-quality`/`systems-lang`/`infra-config`) are the second stage of a two-stage defense, at least for part of their scope (existing `code-reviewer`/`security-audit`/`perf-analyzer`/`ann-perf-engineer`/`go-expert`/`rust-expert`/`cpp-expert`/`nix-expert` remain the first stage for ordinary in-progress review; `infra-config-adversarial-reviewer`'s Lua/YAML/JSON tracks still have no first-stage counterpart — only its Nix track does, via `nix-expert`); the other 3 (`architecture`/`docs-comment`/`shell-config`) cover new territory with no existing first-stage counterpart. All 8 are invoked automatically by `/swarm-loop`/`/swarm-graph` immediately before the Phase 5/G5 GATE and are not intended for manual `@-mention` or auto-delegation like the rest of this table.

**Usage patterns:**

```
# Auto-delegation (Claude decides)
Implement the Go code

# Explicit @-mention
@"go-expert (agent)" Optimize this package

# Background execution
Run a security audit in the background
```

**When to delegate:**

| Trigger                                                                                                | Agent                                 |
| ------------------------------------------------------------------------------------------------------ | ------------------------------------- |
| Implement / optimize / debug Go code                                                                   | `go-expert`                           |
| Rust ownership, lifetimes, unsafe, cargo                                                               | `rust-expert`                         |
| pacman, AUR, systemd, Sway, Wayland, Docker                                                            | `arch-ops`                            |
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
| Implement / optimize / debug Zig code                                                                  | `zig-expert`                          |
| Author or restructure a new GitHub Actions workflow (not diagnosing an existing failure)               | `github-actions-expert`               |
| swarm-loop/swarm-graph Phase 5/G5 GATE — adversarial re-review (orchestrator auto-invokes, not manual) | the 8 `*-adversarial-reviewer` agents |

Rules:

- Use `code-reviewer` **proactively** after every non-trivial code change — don't wait to be asked
- Use `vald-reviewer` **proactively** after every edit inside `github.com/vdaas/vald`
- Use `debugger` **before** guessing at a fix — let it identify root cause first
- Use `ci-investigator` instead of `debugger` when the failure is in the CI pipeline/build environment layer rather than application logic
- `arch-ops` uses `haiku` (fast/cheap); use it freely for system ops
- Never use `go-expert` for Rust or `rust-expert` for Go — stay within language boundaries (same rule across `python-expert`/`cpp-expert`/`nix-expert`/`zig-expert`)
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

Skills live under `~/.claude/skills/` (33 shared skills — language patterns/testing per language,
security review/scan/bounty-hunter, deployment, Nix, protobuf, GitHub Actions, benchmarking, plus
the `swarm-*` orchestration family). Skills can be stacked, up to 5 leading skills per command (e.g.
`/golang-patterns /golang-testing implement X`). See `~/.claude/skills/*/SKILL.md` for the full,
current catalog and each skill's trigger.

**`/swarm-loop` usage:**

```
/swarm-loop <目標>             # 規模を自動判定し、SCALE判定→INIT→EXPLORE→PLAN→EXECUTE→CHECKPOINT→ADVERSARIAL REVIEW→GATEで完走
/swarm-loop                    # 目標未指定の場合、規模判定の確認からスタート
```

Phase -1 (SCALE判定: Quick/Interactive/Mission、判定は昇格のみ) → Phase 0 (worktree隔離・状態初期化)
→ Phase 1 (探索: Quick省略/Interactive単体haiku/Mission Haiku100体) → Phase 2 (PLAN、Interactiveは対話的
設計インタビュー、Missionは`/swarm-architect`招集) → Phase 3 (EXECUTE、複雑度ガード+TDAD Iron Law)
→ Phase 4 (CHECKPOINT、MAST分類・Fixer) → Phase 4.5 (ADVERSARIAL REVIEW、8 Agent敵対的レビュー) →
Phase 5 (GATE→REPORT、ブランチ完了メニュー)

## Hooks Active

| Hook                                         | Script                    | Purpose                                                                                                                                                                       |
| -------------------------------------------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SessionStart                                 | session-start.sh          | Memory injection, session logging                                                                                                                                             |
| UserPromptSubmit                             | user-prompt-submit.sh     | Inject git branch/commit, CWD context, tmux session, timestamp                                                                                                                |
| PreToolUse:Bash                              | rtk-rewrite.sh            | RTK command auto-optimization                                                                                                                                                 |
| PreToolUse:Bash                              | graphify-hint.sh          | Suggest graphify when grep/find detected (project-level)                                                                                                                      |
| PreToolUse:Bash                              | security-gate.sh          | Block destructive commands                                                                                                                                                    |
| PreToolUse:Write/Edit                        | write-security-gate.sh    | Block writes to sensitive paths                                                                                                                                               |
| PostToolUse:Write/Edit/MultiEdit             | post-write.sh             | JSON validation, write logging                                                                                                                                                |
| PostToolUseFailure                           | post-tool-failure.sh      | Tool failure notification and logging                                                                                                                                         |
| PermissionRequest                            | permission-request.sh     | Auto-approve Read/Glob/Grep/LS and a fixed set of read-only Bash command verbs; falls through to the normal permission flow for anything else (see agent/security-rules.json) |
| PreCompact                                   | pre-compact.sh            | graphify update + state logging before compaction                                                                                                                             |
| StopFailure                                  | stop-failure.sh           | Log agent stop failures (timeout, max turns)                                                                                                                                  |
| SessionEnd                                   | session-end.sh            | Session end logging                                                                                                                                                           |
| PreToolUse:Task/Agent                        | swarm-fable-gate.sh       | Blocks `model:'fable'` launches without a budget-guard grant                                                                                                                  |
| PreToolUse:Task/Agent                        | swarm-parallel-gate.sh    | Blocks a 4th distinct `[parallel-task:<id>]` marker (max 3 parallel)                                                                                                          |
| PreToolUse:Write/Edit/MultiEdit/NotebookEdit | swarm-write-scope-gate.sh | Blocks direct writes to Tier B protected paths (SKILL.md/hooks/SWARM.md/settings.json etc.) without a grant                                                                   |

Also available but not wired up: `PostCompact`, `TaskCreated`, `WorktreeCreate`/`WorktreeRemove`,
`InstructionsLoaded`, `PermissionDenied`, `Elicitation`/`ElicitationResult`.

### Project-level hooks (`dotfiles`/`vald` `.claude/settings.json` — not in the global settings)

| Hook                             | Script                  | Purpose                                                                                                       |
| -------------------------------- | ----------------------- | ------------------------------------------------------------------------------------------------------------- |
| PostToolUse:Write/Edit/MultiEdit | swarm-post-edit-lint.sh | Immediate lint after edit (dotfiles: hadolint; vald: golangci-lint scoped to the edited package)              |
| Stop                             | swarm-stop-verify.sh    | Verify all files touched this session (JSON/hadolint/`zsh -n`/gofmt/golangci-lint); failures loop back to fix |

### Vald project hooks (`vald/.claude/settings.json` only)

| Hook                            | Script               | Purpose                                                                                 |
| ------------------------------- | -------------------- | --------------------------------------------------------------------------------------- |
| PreToolUse:Bash                 | vald-law2-gate.sh    | Block `go build`/`cargo build`/`kubectl apply`/`helm install` (Law 2)                   |
| PreToolUse:Write/Edit           | vald-law-gate.sh     | Block edits to `*.pb.go`/`*_vtproto.pb.go` (Law 1)                                      |
| PreToolUse:Write/Edit/MultiEdit | vald-law345-check.sh | Ask on `panic`/`log.Fatal`/`_ = err`/stdlib imports introduced by the change (Laws 3-5) |

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
