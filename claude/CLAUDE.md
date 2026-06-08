# Global Claude Code Instructions

## Identity & Context

- User: kpango (Yusuke Kato, yusukato@lycorp.co.jp)
- Platform: Arch Linux (zen kernel), Wayland/Sway, Ghostty terminal, Tmux
- Languages: Go (primary), Rust, C/C++, Python, TypeScript, Nix, Zsh
- Editors: Helix (primary), VS Code (secondary)
- Shell: Zsh with Sheldon plugin manager, Atuin history

## Response Style

- Respond in Japanese by default; switch to English for code, commands, and technical identifiers
- Be concise and direct — no unnecessary preamble or trailing summaries
- Prefer code over prose for technical explanations
- No emojis unless explicitly requested

## Development Environment

- Package manager: pacman / AUR (paru)
- Container runtime: Docker (containerd backend)
- Build tools: Make (with Makefile.d/ modular structure), Go toolchain, Bun
- Version control: Git with gh CLI
- Dotfiles: `/home/kpango/go/src/github.com/kpango/dotfiles`
- Go workspace: `/home/kpango/go/src/github.com/kpango/`

## Code Style Preferences

- Go: standard library first, minimal dependencies, table-driven tests
- Shell: POSIX-compatible where possible, prefer zsh builtins
- Comments: only when "why" is non-obvious
- No docstrings for obvious functions
- No backwards-compatibility shims for dead code
- Trust internal invariants — validate only at system boundaries
- **Think before coding**: understand the full problem, identify constraints, plan the approach before touching code
- **Simplicity first**: the best code is no code; prefer the simplest solution that correctly solves the problem
- **Surgical changes**: make the minimal diff that achieves the goal — avoid unnecessary refactoring
- **Read before write**: grep and read all relevant code before writing a single line — never guess structure
- **No scope drift**: stay within task boundaries; don't refactor, rename, or improve adjacent code unless asked
- **Verify independently**: run tests/build to confirm correctness — don't assume it works
- **No vibe coding**: if uncertain about a behavior, investigate (grep, read, test) — never hallucinate an answer

## Tool Usage

- Prefer dedicated tools (Read, Edit, Write) over Bash for file operations
- Use parallel tool calls when tasks are independent
- Use `make` targets for installation and configuration tasks
- Use `gh` CLI for GitHub operations

## Custom Subagents (~/.claude/agents/)

Specialized agents available for delegation — use @-mention or natural language:

| Agent            | Purpose                                                                     | Model                 |
| ---------------- | --------------------------------------------------------------------------- | --------------------- |
| `go-expert`      | Go implementation, optimization, testing, debugging                         | inherit (high effort) |
| `rust-expert`    | Rust ownership/lifetimes, unsafe code review, cargo                         | inherit (high effort) |
| `arch-ops`       | Arch Linux, pacman, systemd, Sway, Docker/containers                        | haiku                 |
| `security-audit` | Vulnerability audit, OWASP, secret detection                                | sonnet                |
| `perf-analyzer`  | pprof, criterion, perf, bottleneck analysis                                 | inherit               |
| `code-reviewer`  | Code quality, maintainability, security review (Go/Rust/C++/Python/Zig/K8s) | sonnet                |
| `debugger`       | Root cause analysis, test failure investigation                             | inherit               |
| `proto-expert`   | Protobuf/.proto editing, make proto/all, breaking change detection          | inherit               |
| `vald-reviewer`  | Vald Law enforcement, config sync, K8s resource rules                       | sonnet                |

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

| Trigger                                       | Agent                       |
| --------------------------------------------- | --------------------------- |
| Implement / optimize / debug Go code          | `go-expert`                 |
| Rust ownership, lifetimes, unsafe, cargo      | `rust-expert`               |
| pacman, AUR, systemd, Sway, Wayland, Docker   | `arch-ops`                  |
| Secret detection, OWASP audit, auth review    | `security-audit`            |
| pprof, perf, flamegraph, benchmark regression | `perf-analyzer`             |
| Code review after writing or modifying code   | `code-reviewer`             |
| Test failure, panic, unexpected behavior      | `debugger`                  |
| Edit `.proto` files or run `make proto/all`   | `proto-expert`              |
| Any change in `vald/` repo                    | `vald-reviewer` (post-edit) |

Rules:

- Use `code-reviewer` **proactively** after every non-trivial code change — don't wait to be asked
- Use `vald-reviewer` **proactively** after every edit inside `github.com/vdaas/vald`
- Use `debugger` **before** guessing at a fix — let it identify root cause first
- `arch-ops` uses `haiku` (fast/cheap); use it freely for system ops
- Never use `go-expert` for Rust or `rust-expert` for Go — stay within language boundaries

## Plugins & Skills Available

- `superpowers`: brainstorming, TDD, debugging, planning workflows
- `claude-mem`: persistent session memory and timeline
- `gopls-lsp`: Go LSP integration
- `clangd-lsp`: C/C++ LSP integration
- `github`: GitHub PR/issue management

@RTK.md

## Skills (~/.claude/skills/)

| Skill                     | Trigger                    | Purpose                                           |
| ------------------------- | -------------------------- | ------------------------------------------------- |
| `graphify`                | `/graphify`                | Code/docs → knowledge graph (71x token reduction) |
| `grill-me`                | `/grill-me`                | Pre-design interview and stress-test              |
| `codegraph-graphify`      | `/codegraph-graphify`      | codegraph + graphify combined usage guide         |
| `golang-patterns`         | `/golang-patterns`         | Idiomatic Go patterns and best practices          |
| `golang-testing`          | `/golang-testing`          | Go table-driven tests, benchmarks, fuzzing        |
| `rust-patterns`           | `/rust-patterns`           | Rust ownership, traits, concurrency               |
| `rust-testing`            | `/rust-testing`            | Rust unit/integration/async tests                 |
| `cpp-patterns`            | `/cpp-patterns`            | C++ Core Guidelines, modern C++ idioms            |
| `cpp-testing`             | `/cpp-testing`             | GoogleTest/CTest, sanitizers                      |
| `python-patterns`         | `/python-patterns`         | Pythonic idioms, type hints, PEP 8                |
| `python-testing`          | `/python-testing`          | pytest, fixtures, parametrization                 |
| `pytorch-patterns`        | `/pytorch-patterns`        | Training pipelines, model architecture            |
| `zig-patterns`            | `/zig-patterns`            | Zig comptime, allocators, C interop               |
| `k8s-patterns`            | `/k8s-patterns`            | Kubernetes manifests, Helm, Operators             |
| `claude-api-go`           | `/claude-api-go`           | Anthropic Go SDK, caching, streaming, tools       |
| `security-review`         | `/security-review`         | OWASP, auth, input validation checklist           |
| `security-scan`           | `/security-scan`           | Claude config security audit                      |
| `security-bounty-hunter`  | `/security-bounty-hunter`  | Exploitable vulnerability hunting                 |
| `deployment-patterns`     | `/deployment-patterns`     | CI/CD, Docker, health checks, rollback            |
| `nix-patterns`            | `/nix-patterns`            | Nix flakes, derivations, overlays, home-manager   |
| `protobuf-patterns`       | `/protobuf-patterns`       | .proto design, buf lint/breaking, gRPC patterns   |
| `github-actions-patterns` | `/github-actions-patterns` | Workflow design, matrix build, secrets, vald CI   |
| `tdd-workflow`            | `/tdd-workflow`            | TDD with 80%+ coverage enforcement                |
| `benchmark`               | `/benchmark`               | Performance baselines and regression detection    |

**graphify usage:**

```
/graphify .                    # Graph the current directory
/graphify . --update           # Update changed files only
/graphify query "..."          # Query the graph
graphify hook install          # Auto-update after git commit
```

## Hooks Active

| Hook                   | Script                 | Purpose                                                                                                                                                                                                                                                                                                                                 |
| ---------------------- | ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| SessionStart           | session-start.sh       | Memory injection, session logging                                                                                                                                                                                                                                                                                                       |
| UserPromptSubmit       | user-prompt-submit.sh  | Inject git branch/commit, CWD context, tmux session, timestamp                                                                                                                                                                                                                                                                          |
| PreToolUse:Bash        | rtk-rewrite.sh         | RTK command auto-optimization                                                                                                                                                                                                                                                                                                           |
| PreToolUse:Bash        | graphify-hint.sh       | Suggest graphify when grep/find detected (project-level)                                                                                                                                                                                                                                                                                |
| PreToolUse:Bash        | security-gate.sh       | Block destructive commands                                                                                                                                                                                                                                                                                                              |
| PreToolUse:Write/Edit  | write-security-gate.sh | Block writes to sensitive paths (~/.ssh/, /etc/)                                                                                                                                                                                                                                                                                        |
| PostToolUse:Write/Edit | post-write.sh          | JSON validation, write logging                                                                                                                                                                                                                                                                                                          |
| PostToolUseFailure     | post-tool-failure.sh   | Tool failure notification and logging                                                                                                                                                                                                                                                                                                   |
| PermissionRequest      | permission-request.sh  | Auto-approve: Read/Glob/Grep/LS tools; Bash read-only commands (git, ls/grep/find/jq, make targets, kubectl/docker/helm/paru read ops, systemctl status, journalctl, rtk gain/discover, codegraph/graphify queries, pass show, buf lint/breaking, go env/list, cargo check/clippy/fmt-check, tmux list-\*, rustup show, npm list/audit) |
| PreCompact             | pre-compact.sh         | graphify update + state logging before compaction                                                                                                                                                                                                                                                                                       |
| StopFailure            | stop-failure.sh        | Log agent stop failures (timeout, max turns)                                                                                                                                                                                                                                                                                            |
| SessionEnd             | session-end.sh         | Session end logging                                                                                                                                                                                                                                                                                                                     |

### Vald Project Hooks (vald/.claude/settings.json only)

| Hook                   | Script               | Purpose                                                    |
| ---------------------- | -------------------- | ---------------------------------------------------------- |
| PreToolUse:Bash        | vald-law2-gate.sh    | Block go build/cargo build/kubectl apply/helm install      |
| PreToolUse:Write/Edit  | vald-law-gate.sh     | Block edits to _.pb.go / _\_vtproto.pb.go (Law 1)          |
| PostToolUse:Write/Edit | vald-law345-check.sh | Warn on panic/log.Fatal/\_ = err/stdlib imports (Laws 3-5) |

## MCP Servers

| Server       | Command                                           | Purpose                                                                                                |
| ------------ | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `codegraph`  | `codegraph serve --mcp`                           | Code navigation: search/context/callers/callees                                                        |
| `filesystem` | `bunx @modelcontextprotocol/server-filesystem`    | File access (restricted to allowed paths)                                                              |
| `memory`     | `bunx @modelcontextprotocol/server-memory`        | Knowledge graph persistent memory                                                                      |
| `lsp-rust`   | `mcp-language-server -lsp rust-analyzer`          | Rust LSP: definition/references/hover (vald workspace) — requires `rustup component add rust-analyzer` |
| `k8s`        | `docker run quay.io/manusa/kubernetes_mcp_server` | Kubernetes read ops: pods/deployments/logs (Docker, cap-drop=ALL)                                      |
| `slack`      | `docker run mcp/slack`                            | Slack read ops: channels/history/search — requires `SLACK_BOT_TOKEN` env var                           |

Allowed filesystem paths: `/home/kpango`, `/home/kpango/go/src/github.com/kpango`, `/home/kpango/go/src/github.com/vdaas/vald`

## Memory System

Auto memory stored in `~/.claude/memory/`. Session logs in `~/.claude/session-data/`.

At session start, MEMORY.md is automatically injected as context. Update memory with:

```
/memory update  # or write directly to ~/.claude/memory/
```

## Multi-Agent Patterns

- **Fork mode**: `CLAUDE_CODE_FORK_SUBAGENT=1` — general-purpose tasks use fork (inherits context)
- **Background isolation**: git worktrees (`bgIsolation: "worktree"`)
- **Independent subtasks**: `superpowers:dispatching-parallel-agents`
- **Teammate mode**: "auto" (uses tmux when available)
- **@-mention**: `@"agent-name (agent)"` for explicit delegation

## Security

- Never commit secrets, tokens, or credentials
- `.credentials.json` is NOT managed in dotfiles — handled by SSO login
- Root session shares `~/.claude` via symlink (not separate config)
- Security gate hook blocks: `rm -rf /`, fork bombs, `dd` to block devices, force-push to protected branches, `curl|wget ... | sh/bash`, `git clean -fdx`, kubectl/helm destructive ops in production namespaces
- Write security gate blocks writes to: `~/.ssh/`, `~/.gnupg/`, `~/.aws/`, `~/.kube/config`, `~/.netrc`, `~/.cargo/credentials`, `~/.npmrc`, `/etc/`, `/boot/`, `/dev/`, `/proc/`, `/sys/`
- **Intentional broad allowances** (personal machine, accepted risk): `Bash(python3 *)`, `Bash(node *)`, `Bash(bun *)`, `Bash(bunx *)` — needed for hook scripts, inline JSON processing, and build tooling
