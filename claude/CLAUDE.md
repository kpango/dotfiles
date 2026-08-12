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

## Required External Tools（オンボーディング）

hooks/skills が利用する外部ツール。大半の hook は `command -v <tool>` チェックで未導入時に
fail-open（該当機能のみスキップ、致命的にはならない）するが、機能が黙って無効化されるため
導入状況は把握しておくこと。

| Tool            | 用途                                             | 入手方法                                                                                              |
| --------------- | ------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| `rtk`           | Bash コマンドのトークン最適化(詳細は [[RTK.md]]) | `paru -S rtk-ai-bin`                                                                                  |
| `codegraph`     | コードナビゲーション MCP server                  | npm グローバルパッケージ `@colbymchenry/codegraph`                                                    |
| `graphify`      | ナレッジグラフ CLI                               | zsh 関数ラッパー経由（`pass show ai/gemini` から API キー取得、`pass` に `ai/gemini` エントリが必要） |
| `golangci-lint` | Go lint(`swarm-post-edit-lint.sh` 等)            | 公式インストールスクリプト                                                                            |
| `hadolint`      | Dockerfile lint                                  | `paru -S hadolint-bin`                                                                                |
| `buf`           | protobuf lint/breaking change 検出               | `go install github.com/bufbuild/buf/cmd/buf@latest`                                                   |
| `dlv`           | Go デバッガ                                      | `go install github.com/go-delve/delve/cmd/dlv@latest`                                                 |
| `jq`            | JSON 処理(多数の hook が使用)                    | `pacman -S jq`                                                                                        |
| `flock`         | 予算カウンタのファイルロック(util-linux)         | Linux/NixOS では通常プリインストール。macOS では欠落する場合がある(下記注記参照)                      |

`graphify`/`pass` はこの個人環境固有の秘密情報管理に依存する。同等の設定を別環境で再現する場合は
`pass show ai/gemini` を自身の API キー取得手段に置き換えること。

macOS で `flock` が欠落する場合は `brew install flock` で導入する(util-linux は keg-only/shadowed
のため `brew link` では導入できない。導入済みの単独 formula を使う)。`budget-guard.sh` /
`self-improve-register.sh` / `harness-record.sh` の3スクリプトは未導入時にクラッシュせず、
actionable な `FLOCK_MISSING` メッセージで fail-closed する。

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
- Periodically run `/doctor` to catch CLAUDE.md bloat (content Claude could already derive from the codebase)

## Custom Subagents (~/.claude/agents/)

Specialized agents available for delegation — use @-mention or natural language:

| Agent               | Purpose                                                                                | Model                 |
| ------------------- | -------------------------------------------------------------------------------------- | --------------------- |
| `go-expert`         | Go implementation, optimization, testing, debugging                                    | inherit (high effort) |
| `rust-expert`       | Rust ownership/lifetimes, unsafe code review, cargo                                    | inherit (high effort) |
| `arch-ops`          | Arch Linux, pacman, systemd, Sway, Docker/containers                                   | haiku                 |
| `security-audit`    | Vulnerability audit, OWASP, secret detection                                           | sonnet                |
| `perf-analyzer`     | pprof, criterion, perf, bottleneck analysis                                            | inherit               |
| `code-reviewer`     | Code quality, maintainability, security review (Go/Rust/C++/Python/Zig/K8s)            | sonnet                |
| `debugger`          | Root cause analysis, test failure investigation                                        | inherit               |
| `proto-expert`      | Protobuf/.proto editing, make proto/all, breaking change detection                     | inherit               |
| `vald-reviewer`     | Vald Law enforcement, config sync, K8s resource rules                                  | sonnet                |
| `ann-perf-engineer` | ANN vector search (ArcFlare/NGT/NGTAQ) SIMD kernel opt, ann-benchmarks Pareto analysis | inherit (high effort) |
| `ci-investigator`   | CI/build pipeline root-cause analysis (vald/dotfiles), distinct from debugger          | inherit (high effort) |

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

| Trigger                                                     | Agent                       |
| ----------------------------------------------------------- | --------------------------- |
| Implement / optimize / debug Go code                        | `go-expert`                 |
| Rust ownership, lifetimes, unsafe, cargo                    | `rust-expert`               |
| pacman, AUR, systemd, Sway, Wayland, Docker                 | `arch-ops`                  |
| Secret detection, OWASP audit, auth review                  | `security-audit`            |
| pprof, perf, flamegraph, benchmark regression               | `perf-analyzer`             |
| Code review after writing or modifying code                 | `code-reviewer`             |
| Test failure, panic, unexpected behavior                    | `debugger`                  |
| Edit `.proto` files or run `make proto/all`                 | `proto-expert`              |
| Any change in `vald/` repo                                  | `vald-reviewer` (post-edit) |
| ArcFlare/NGT/NGTAQ SIMD kernel or ann-benchmarks work       | `ann-perf-engineer`         |
| CI red but code looks correct / passes locally, fails in CI | `ci-investigator`           |

Rules:

- Use `code-reviewer` **proactively** after every non-trivial code change — don't wait to be asked
- Use `vald-reviewer` **proactively** after every edit inside `github.com/vdaas/vald`
- Use `debugger` **before** guessing at a fix — let it identify root cause first
- Use `ci-investigator` instead of `debugger` when the failure is in the CI pipeline/build environment layer (workflow YAML, Docker image, toolchain, Makefile prerequisites) rather than application logic
- `arch-ops` uses `haiku` (fast/cheap); use it freely for system ops
- Never use `go-expert` for Rust or `rust-expert` for Go — stay within language boundaries

Agent frontmatter `effort` accepts `low`/`medium`/`high`/`xhigh`/`max` (`xhigh` sits between `high` and `max`).

## Plugins & Skills Available

- `superpowers`: brainstorming, TDD, debugging, planning workflows
- `claude-mem`: persistent session memory and timeline
- `gopls-lsp`: Go LSP integration
- `clangd-lsp`: C/C++ LSP integration
- `github`: GitHub PR/issue management

@RTK.md

## Skills (~/.claude/skills/)

| Skill                     | Trigger                                             | Purpose                                                                                                                                                                                                                                                                                             |
| ------------------------- | --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `swarm-loop`              | `/swarm-loop`                                       | 自走ループの単一エントリポイント。Quick(1行修正)/Interactive(対話設計+TDAD)/Mission(100体探索・複数セッション自律)を自動判定し同じ状態機械で処理                                                                                                                                                    |
| `swarm-graph`             | `/swarm-graph`（人間招集限定）                      | swarm-loopの1段階進化。@fix_plan.mdのTasksテーブルをDAGへ機械コンパイルしフロンティア実行（GRAPH-FIT採用ゲート/plan version不変+replan≤2/stale伝播再検証/graph-status.sh専用）。UNFITはswarm-loopへ保守的降格                                                                                       |
| `swarm-meta`              | `/swarm-meta`（人間招集限定）                       | **迷ったらこれが推奨入口**。2段階進化のメタハーネス層 — 決定論プロファイルで swarm-loop/swarm-graph を自動選択し委譲・harness-lintで検証床強制・実績をregistryへ記録（使い分け判断は不要。loop/graph の直接招集はハーネスを明示指定したい場合のみ）。実行中の自己改変はせずTier B変更はswarm-evolve |
| `swarm-explore`           | (swarm-loop内部/直接)                               | Haiku 100体分散探索→秘書集約                                                                                                                                                                                                                                                                        |
| `swarm-implement`         | (swarm-loop内部/直接)                               | Maker(Sonnet)/Checker(Opus)分離実装ループ・Fixerパターン                                                                                                                                                                                                                                            |
| `swarm-architect`         | `/swarm-architect`（スポット診断は内部条件発火）    | 高級カード（Fable）。フル設計モード=コア設計変更・難局突破の提案書（人間招集限定）。スポット診断モード=SWARM.md §1 の発動4条件+budget-guard --fable 通過時のみ自動起動（1タスク1回・1ミッション2回、診断書のみ）                                                                                    |
| `swarm-release-gate`      | `/swarm-release-gate`                               | マージ/デプロイ前の強制検証ゲート（人間招集限定）                                                                                                                                                                                                                                                   |
| `swarm-evolve`            | `/swarm-evolve`                                     | Skill自体のメタ進化ループ。軌跡ログ+hook rejectionログの繰り返しパターンをDrafter(Sonnet)/Checker(Opus)で検証しSKILL.md差分を起案。人間承認なしには適用しない（人間招集限定）                                                                                                                       |
| `swarm-memory-sync`       | `/swarm-memory-sync`（swarm-loop GATE内部呼出も可） | ドメイン知識の蒸留（swarm-evolveと対）。軌跡ログ/@fix_plan.mdの学びのうち一般化可能なものをauto-memory(~/.claude/memory/)へ振り分け。SKILL.md/hooks自体は変更しないため人間承認不要                                                                                                                 |
| `golang-patterns`         | `/golang-patterns`                                  | Idiomatic Go patterns and best practices                                                                                                                                                                                                                                                            |
| `golang-testing`          | `/golang-testing`                                   | Go table-driven tests, benchmarks, fuzzing                                                                                                                                                                                                                                                          |
| `rust-patterns`           | `/rust-patterns`                                    | Rust ownership, traits, concurrency                                                                                                                                                                                                                                                                 |
| `rust-testing`            | `/rust-testing`                                     | Rust unit/integration/async tests                                                                                                                                                                                                                                                                   |
| `cpp-patterns`            | `/cpp-patterns`                                     | C++ Core Guidelines, modern C++ idioms                                                                                                                                                                                                                                                              |
| `cpp-testing`             | `/cpp-testing`                                      | GoogleTest/CTest, sanitizers                                                                                                                                                                                                                                                                        |
| `python-patterns`         | `/python-patterns`                                  | Pythonic idioms, type hints, PEP 8                                                                                                                                                                                                                                                                  |
| `python-testing`          | `/python-testing`                                   | pytest, fixtures, parametrization                                                                                                                                                                                                                                                                   |
| `pytorch-patterns`        | `/pytorch-patterns`                                 | Training pipelines, model architecture                                                                                                                                                                                                                                                              |
| `zig-patterns`            | `/zig-patterns`                                     | Zig comptime, allocators, C interop                                                                                                                                                                                                                                                                 |
| `k8s-patterns`            | `/k8s-patterns`                                     | Kubernetes manifests, Helm, Operators                                                                                                                                                                                                                                                               |
| `claude-api-go`           | `/claude-api-go`                                    | Anthropic Go SDK, caching, streaming, tools                                                                                                                                                                                                                                                         |
| `security-review`         | `/security-review`                                  | OWASP, auth, input validation checklist                                                                                                                                                                                                                                                             |
| `security-scan`           | `/security-scan`                                    | Claude config security audit                                                                                                                                                                                                                                                                        |
| `security-bounty-hunter`  | `/security-bounty-hunter`                           | Exploitable vulnerability hunting                                                                                                                                                                                                                                                                   |
| `deployment-patterns`     | `/deployment-patterns`                              | CI/CD, Docker, health checks, rollback                                                                                                                                                                                                                                                              |
| `nix-patterns`            | `/nix-patterns`                                     | Nix flakes, derivations, overlays, home-manager                                                                                                                                                                                                                                                     |
| `protobuf-patterns`       | `/protobuf-patterns`                                | .proto design, buf lint/breaking, gRPC patterns                                                                                                                                                                                                                                                     |
| `github-actions-patterns` | `/github-actions-patterns`                          | Workflow design, matrix build, secrets, vald CI                                                                                                                                                                                                                                                     |
| `benchmark`               | `/benchmark`                                        | Performance baselines and regression detection                                                                                                                                                                                                                                                      |
| `ann-benchmark-patterns`  | `/ann-benchmark-patterns`                           | ann-benchmarks conventions, Pareto frontier analysis, SIMD kernel pitfalls (ArcFlare/NGT/NGTAQ)                                                                                                                                                                                                     |

Skills can be stacked, up to 5 leading skills per command (e.g. `/golang-patterns /golang-testing implement X`).

**swarm-loop usage:**

```
/swarm-loop <目標>             # 規模を自動判定し、SCALE判定→INIT→EXPLORE→PLAN→EXECUTE→CHECKPOINT→GATEで完走
/swarm-loop                    # 目標未指定の場合、規模判定の確認からスタート
```

Phase -1 (SCALE判定: Quick/Interactive/Mission、判定は昇格のみ) → Phase 0 (worktree隔離・状態初期化)
→ Phase 1 (探索: Quick省略/Interactive単体haiku/Mission Haiku100体) → Phase 2 (PLAN、Interactiveは対話的
設計インタビュー、Missionは/swarm-architect招集) → Phase 3 (EXECUTE、複雑度ガード+TDAD Iron Law)
→ Phase 4 (CHECKPOINT、MAST分類・Fixer) → Phase 5 (GATE→REPORT、ブランチ完了メニュー)

## Hooks Active

| Hook                                         | Script                    | Purpose                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| SessionStart                                 | session-start.sh          | Memory injection, session logging                                                                                                                                                                                                                                                                                                                                                                                                          |
| UserPromptSubmit                             | user-prompt-submit.sh     | Inject git branch/commit, CWD context, tmux session, timestamp                                                                                                                                                                                                                                                                                                                                                                             |
| PreToolUse:Bash                              | rtk-rewrite.sh            | RTK command auto-optimization                                                                                                                                                                                                                                                                                                                                                                                                              |
| PreToolUse:Bash                              | graphify-hint.sh          | Suggest graphify when grep/find detected (project-level)                                                                                                                                                                                                                                                                                                                                                                                   |
| PreToolUse:Bash                              | security-gate.sh          | Block destructive commands                                                                                                                                                                                                                                                                                                                                                                                                                 |
| PreToolUse:Write/Edit                        | write-security-gate.sh    | Block writes to sensitive paths (~/.ssh/, /etc/)                                                                                                                                                                                                                                                                                                                                                                                           |
| PostToolUse:Write/Edit/MultiEdit             | post-write.sh             | JSON validation, write logging                                                                                                                                                                                                                                                                                                                                                                                                             |
| PostToolUseFailure                           | post-tool-failure.sh      | Tool failure notification and logging                                                                                                                                                                                                                                                                                                                                                                                                      |
| PermissionRequest                            | permission-request.sh     | Auto-approve: Read/Glob/Grep/LS tools; Bash read-only commands (git, ls/grep/find/jq, make targets, kubectl/docker/helm/paru read ops, systemctl status, journalctl, rtk gain/discover, codegraph/graphify queries, pass show, buf lint/breaking, go env/list, cargo check/clippy/fmt-check, tmux list-\*, rustup show, npm list/audit). Overlaps with native Auto mode (`--permission-mode auto`); the hook allowlist stays authoritative |
| PreCompact                                   | pre-compact.sh            | graphify update + state logging before compaction                                                                                                                                                                                                                                                                                                                                                                                          |
| StopFailure                                  | stop-failure.sh           | Log agent stop failures (timeout, max turns)                                                                                                                                                                                                                                                                                                                                                                                               |
| SessionEnd                                   | session-end.sh            | Session end logging                                                                                                                                                                                                                                                                                                                                                                                                                        |
| PreToolUse:Task/Agent                        | swarm-fable-gate.sh       | `model:'fable'` 起動時、未消費grant(budget-guard.sh --fable発行)が無ければexit 2でブロック(SWARM.md §1)。`subagent_type:debugger`をmodel未指定で起動した場合のみ警告のみ(非ブロッキング、Fixerがmodel:sonnet明示を怠った際の注意喚起)                                                                                                                                                                                                      |
| PreToolUse:Task/Agent                        | swarm-parallel-gate.sh    | prompt内`[parallel-task:<task-id>]`マーカーを検出した場合のみ、distinct task-idが4件目でexit 2でブロック(SWARM.md §1「最大3並列」)。マーカー無しは無干渉                                                                                                                                                                                                                                                                                   |
| PreToolUse:Write/Edit/MultiEdit/NotebookEdit | swarm-write-scope-gate.sh | Tier B保護パス(SKILL.md/hooks/SWARM.md/settings.json等)への直接書き込みをexit 2でブロック。budget-guard.sh --write-scope-grant発行済みの単発grantが無ければ拒否(SWARM.md §2)                                                                                                                                                                                                                                                               |

Also available but not wired up: `PostCompact`, `TaskCreated`, `WorktreeCreate`/`WorktreeRemove`, `InstructionsLoaded`, `PermissionDenied`, `Elicitation`/`ElicitationResult`.

### Project-level Hooks (dotfiles/vald 両方の `.claude/settings.json` — グローバル settings.json には無い)

`~/.claude/settings.json`(グローバル)には配線されておらず、`kpango/dotfiles/.claude/settings.json` と
`vdaas/vald/.claude/settings.json` それぞれのproject-level設定でのみ有効(SWARM.md §6のクローズドループを
実際に強制している場所はここ)。

| Hook                             | Script                  | Purpose                                                                                                          |
| -------------------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------- |
| PostToolUse:Write/Edit/MultiEdit | swarm-post-edit-lint.sh | 編集直後の即時lint(dotfiles: hadolint、vald: 編集パッケージ限定golangci-lint)。失敗はexit 2で差し戻す            |
| Stop                             | swarm-stop-verify.sh    | セッション中に編集したファイルを対象に検証(JSON/hadolint/zsh -n/gofmt/golangci-lint)。失敗は修正ループへ差し戻す |

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

Allowed filesystem paths: `/home/kpango/go/src/github.com/kpango`, `/home/kpango/go/src/github.com/vdaas/vald`
(2026-08-12: `/home/kpango` 全体を許可ルートから除外 — `permissions.deny` の secret系ファイル
Read 禁止が `mcp__filesystem__*` ツールには適用されず、許可ルートに `$HOME` 全体を含めるとバイパス
経路になるため。ホームディレクトリ直下のファイルは組み込み `Read`/`Edit`/`Write` 経由でのみアクセスする)

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
- Security gate hook blocks: `rm -rf /`, fork bombs, `dd` to block devices, force-push to protected branches, `curl|wget ... | sh/bash`, `git clean -fdx`, `git add -A/--all/./*` (specific path指定のみ), kubectl/helm destructive ops in production namespaces
- Security gate hook asks for confirmation on: `git clean -f` (without `-dx`), `git checkout .` — discarding uncommitted changes outside the always-block cases above
- Write security gate blocks writes to: `~/.ssh/`, `~/.gnupg/`, `~/.aws/`, `~/.kube/config`, `~/.netrc`, `~/.cargo/credentials`, `~/.npmrc`, `/etc/`, `/boot/`, `/dev/`, `/proc/`, `/sys/`
- `permissions.deny` (settings.json) additionally blocks Read/Edit on secret-shaped file globs anywhere on the filesystem (`//**/.env*`, `//**/*.pem`, `//**/*.key`, `//**/*.p12`, `//**/*.pfx`, `//**/id_rsa`, `//**/id_ed25519`, `//**/.ssh/**`, `//**/.netrc`, `//**/*.kubeconfig`, `//**/.kube/config`, `//**/*.tfstate`, `//**/terraform.tfvars`, `//**/.aws/credentials`) — the `//` prefix anchors at the filesystem root (a bare `**/` pattern only matches under the current working directory); `Write`/`NotebookEdit` path rules are never consulted by Claude Code, so `Read` (which also covers `Edit`) is the only rule that matters here. Applies only to the built-in Read/Edit tool names, not to MCP server tools (see `mcpServers.filesystem` note above)
- **Intentional broad allowances** (personal machine, accepted risk): `Bash(python3 *)`, `Bash(node *)`, `Bash(bun *)`, `Bash(bunx *)` — needed for hook scripts, inline JSON processing, and build tooling
- `~/.claude/rules/` holds path-scoped and always-loaded conventions (`harness-design.md` / `impact-scope.md` / `verify-before-assert.md` / `performance.md`) — see the official [Rules](https://code.claude.com/docs/en/memory#organize-rules-with-claude/rules/) feature
- statusLine (`~/.claude/statusline-command.sh`) shows cwd/git branch+status/model/context-remaining%
