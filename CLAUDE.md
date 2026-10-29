# Dotfiles Project — Claude Code Instructions

## Project Overview

This is kpango's personal dotfiles repository for Arch Linux (zen kernel) + Sway/Wayland environment. It manages configuration for: Zsh, Tmux, Ghostty, Helix, Sway, Waybar, Kanshi, Docker, systemd user services, Go environment, Nix, and Claude Code itself.

## Repository Structure

```
dotfiles/
├── Makefile              # Top-level; delegates to Makefile.d/
├── Makefile.d/           # Modular make targets
│   └── install.mk        # Primary install/link/copy logic
├── agent/                # Shared claude/pi/agy config (see "agent/ — 共通設定ディレクトリ" below)
│   ├── README.md         # Scope, provenance, migration history, and known gaps
│   ├── rules/             # claude/pi/agy 共通ルール(正典。$HOME側へ直接symlinkされる、リポジトリ内に中間symlinkは無い)
│   ├── skills/             # claude/pi/agy 共通スキル静的部分(37スキル、正典)。動的統計ファイルはclaude/pi/agy各skills/に実ファイルとして残る
│   ├── agents/             # claude/agy/pi 共通エージェント定義(26件、正典)。pi向けもagent/agentsへ直接symlink
│   │                         (tools:frontmatter変換はpi/extensions/subagents.tsの実行時変換、旧gen-pi-agents.shは廃止済み)
│   ├── hooks/claude/, hooks/agy/, hooks/pi/  # claude/agy/pi実体移動済みhookファイル(計30ファイル、正典。
│   │                         2026-09-24、findでの実カウント+各ファイルの呼び出し経路読み取りで再検証)。
│   │                         hooks/claude/(20件)はdecide.py委譲shim本体(5件: security-gate.sh・
│   │                         vald-law-gate.sh・vald-law2-gate.sh・vald-law345-check.sh・
│   │                         write-security-gate.sh、いずれも`DECIDE=`変数経由でdecide.pyを呼ぶ)+
│   │                         rtk-rewrite.sh(判定ロジック共有なしの薄いラッパー、1件)+claude固有の
│   │                         非shimロジック(evidence-reducer.sh・swarm-*.sh等14件、2026-09-04に
│   │                         claude/hooks/から実体移動)の混在。
│   │                         hooks/agy/(4件)はdecide.py委譲shim2件(security-gate.sh・
│   │                         vald-law-gate.sh)+rtk-rewrite.sh 1件+session-start.sh(非shim)1件、
│   │                         hooks/pi/(6件)はdecide.py委譲shim1件(security-gate.ts、
│   │                         lib/shared.tsの`callDecide`経由)+rtk-optimizer.ts 1件+
│   │                         auto-memory.ts(非shim)1件+共有ライブラリlib/配下3件
│   │                         (shared.ts, memory-adapter.ts, hook-cache.test.ts)の混在(いずれも
│   │                         decide.py shimのみではない)。
│   │                         claude/hooks・agy/hooks・pi/extensionsからper-file symlinkで統合される(下記参照)
│   ├── scripts/hooks/     # rule_engine.py・decide.py(hook判定ロジック本体、上記shimが呼び出す)
│   ├── scripts/sync-verify.sh    # $HOME側の配線(symlink先が正しいか)を機械検証
│   ├── models/            # 抽象モデルルーティング定義 (schema.json)
│   ├── harnesses/         # 各CLI/Harness固有設定・マッピング管理 (SSoT集約)
│   │   ├── claude/        # Claude Code config (-> ~/.claude/) & model-routing.json
│   │   ├── pi/            # Pi Coding Agent config (-> ~/.pi/agent/) & model-routing.json
│   │   ├── agy/           # Antigravity CLI config (-> ~/.agy/ & ~/.gemini/) & model-routing.json
│   │   ├── codex/         # OpenAI Codex config (-> ~/.codex/) & model-routing.json
│   │   └── primeagent/    # prime-agent 0.10.0 config (-> ~/.prime/agent/ via install.sh), model-routing.json,
│   │                         prime skills/machines, bin/pa-sandbox・pa-auto (-> ~/.local/bin/)
│   ├── SWARM.md          # 共通 Swarm 規約（Tier表記: Low, Medium, High, XHigh, Max, Inherit）
│   └── SWARM_REFERENCES.md
├── .claude/              # Project-level Claude config (NOT symlinked)
│   ├── settings.json     # Project plugin enablement
│   └── settings.local.json  # Project-specific permissions
├── sway/                 # Sway WM config
├── ghostty.conf          # Ghostty terminal config
├── tmux.conf             # Tmux config
├── zsh/                  # Zsh config files
├── zshrc / zshenv        # Zsh entry points
├── helix/                # Helix editor config
├── systemd/              # systemd user services
└── arch/                 # Arch-specific configs (waybar, etc.)
```

## Key Makefile Targets

- `make dotfiles/install` — symlink/copy all dotfiles to $HOME
- `make claude/install` — deploy Claude Code config (runs after dotfiles/install)
- `make pi/install` — deploy Pi Coding Agent config (runs after dotfiles/install)
- `make agy/install` — deploy Antigravity CLI config (runs after dotfiles/install)
- `make codex/install` — deploy Codex config (runs after dotfiles/install)
- `make primeagent/install` — deploy prime-agent config via `agent/harnesses/primeagent/install.sh` (runs after dotfiles/install)
- `make arch/install` — full Arch Linux setup (runs dotfiles/install + AUR packages)
- `make dotfiles/clean` — remove all symlinks

## Multi-Harness Config Deployment (SSoT: agent/)

**2026-09-04: リポジトリ内の各ハーネス設定は `agent/harnesses/` に集約され、内部中間 symlink は一切存在しない**。
`Makefile.d/install.mk`（および `nix/modules/home/dotfiles/agent-tools.nix`）が正典（`agent/` および `agent/harnesses/`）から `$HOME` 側へ**直接** symlink / 生成する。配線が正しいかは `agent/scripts/sync-verify.sh` で機械検証できる。

`settings.json` and `settings.local.json` in `agent/harnesses/claude/` are **symlinked** to `~/.claude/`.
`installed_plugins.json` is processed via `envsubst` and copied to `~/.claude/plugins/`.
`CLAUDE.md` in `agent/harnesses/claude/` is **symlinked** to `~/.claude/CLAUDE.md`.
`model-routing.json` in `agent/harnesses/claude/` is **symlinked** to `~/.claude/model-routing.json`.
`~/.claude/rules`・`~/.claude/agents`・`~/.claude/skills`・`~/.claude/RTK.md`・`~/.claude/SWARM.md`・
`~/.claude/SWARM_REFERENCES.md` は `agent/`（下記）から直接 symlink される。
`~/.claude/hooks` は `agent/harnesses/claude/hooks/` と `agent/hooks/claude/` の両方から個別ファイルsymlinkする「merged directory」として構成される。

`settings.json`, `models.json`, `AGENTS.md`, `SYSTEM.md`, `model-routing.json` in `agent/harnesses/pi/` are **symlinked** to `~/.pi/agent/`.
`prompts/` and `themes/` in `agent/harnesses/pi/` are **symlinked** to `~/.pi/agent/`.
`~/.pi/agent/agents/` は `agent/agents/` へ直接 symlink される。
`~/.pi/agent/extensions` は `agent/harnesses/pi/extensions/` と `agent/hooks/pi/` の両方から個別ファイルsymlinkする「merged directory」として構成される。
`~/.pi/agent/rules`・`~/.pi/agent/skills`・`~/.pi/agent/RTK.md`・`~/.pi/agent/SWARM.md`・
`~/.pi/agent/SWARM_REFERENCES.md` は `agent/` から直接 symlink される。

`settings.json`, `AGENTS.md`, `SYSTEM.md`, `policies/`, `model-routing.json`, and `mcp_config.json` in `agent/harnesses/agy/` are
**symlinked** to `~/.agy/` and `~/.gemini/`.
`~/.agy/hooks`・`~/.gemini/hooks` は `agent/harnesses/agy/hooks/` と `agent/hooks/agy/` の両方から個別ファイルsymlinkする「merged directory」として構成される。
`~/.agy/rules`・`~/.agy/agents`・`~/.agy/skills`・`~/.agy/RTK.md`・`~/.agy/SWARM.md`・
`~/.agy/SWARM_REFERENCES.md` は `agent/` から直接 symlink される。

`config.toml` and `model-routing.json` in `agent/harnesses/codex/` are **symlinked** to `~/.codex/`.
PrimeAgent (prime-agent 0.10.0): `AGENTS.md` (generated by `gen-agents-md.sh`), `models.json`, and `model-routing.json` in
`agent/harnesses/primeagent/` are **symlinked** to `~/.prime/agent/` by `dotfiles/install` (DOTFILES_MAP).
Everything else is done by `agent/harnesses/primeagent/install.sh` (`make primeagent/install`):
`settings.json` is **never a symlink** (the CLI replaces it on write) — it is a 0600 regular file merged with jq
(live `*` repo `settings.json` `*` keys derived from `model-routing.json`), the previous file kept as `settings.json.bak.<timestamp>`.
`skills/`, `machines/`, `bin/` are real directories of per-entry symlinks; `agents`, `themes`, `SWARM.md`,
`SWARM_REFERENCES.md`, `RTK.md` are symlinked; `pa-sandbox`/`pa-auto` are symlinked into `~/.local/bin/`.
No `SYSTEM.md` (it would replace prime's core prompt). Check with `bash agent/harnesses/primeagent/validate-harness.sh`.
Details: `agent/README.md` "PrimeAgent ハーネス", `CONTEXT.md` "primeagent-max-customize".

## agent/ — SSoT共通設定 & ハーネス統合ディレクトリ

`SWARM.md`・`SWARM_REFERENCES.md`・`rules/`・`skills/`（静的部分）・`agents/`・`models/` を単一ソース `agent/` へ集約。
さらに全ハーネスの設定を `agent/harnesses/` 配下で一元管理。5エコシステム（Claude, AGY, Pi, Codex, PrimeAgent）への配線は
`Makefile.d/install.mk`・Nix の両方が `agent/` から直接行う。各ハーネスのモデル差異は `model-routing.json` と抽象Tier（Low, Medium, High, XHigh, Max）により透過的に解決される。

The dotfiles root `CLAUDE.md` (this file) applies only when Claude Code is run from this directory.

## Working in This Repo

- Always use `make` targets for installation, never manual symlinks
- Test symlinks with `ls -la ~/<target>` before committing
- JSON files must be valid — check with `python3 -m json.tool`
- Zsh config changes: source files are in `zsh/` directory
- systemd services: use `systemctl --user` for user services
- Packages: prefer `pacman` over AUR when available; use `paru` for AUR
- **Action Fusion**: after editing a file, run its verification command (test/build/lint) before
  the next edit — don't stack unverified edits. Convention only, not machine-enforced: Pi Coding
  Agent's extension API (`@earendil-works/pi-coding-agent@0.84.4`, `dist/core/extensions/types.d.ts`)
  has no primitive to fuse edit+verify into one tool call. Sourced from SoL-Pi (arXiv:2609.20519);
  full citation trail, and the not-yet-applied ObservationPack/Evidence-Preserving Reducer hook
  proposals for `agent/hooks/pi/`, are in
  `~/.claude/session-data/swarm/evolve-proposals/2026-09-23-agent-pdf-deepresearch-draft.md`.

## Common Tasks

**Add new dotfile mapping:**

1. Add entry to `DOTFILES_MAP` in `Makefile.d/install.mk`
2. Run `make dotfiles/install`

**Update Claude settings:**

1. Edit `claude/settings.json` or `claude/settings.local.json`
2. Changes take effect immediately (hot-reload)

**Add new plugin:**

1. Add to `enabledPlugins` in `claude/settings.json`
2. Add marketplace to `extraKnownMarketplaces` if new source
3. Update `claude/installed_plugins.json` template

**Update systemd service:**

1. Edit file in `systemd/user/`
2. Run `systemctl --user daemon-reload && systemctl --user restart <service>`

## Style Notes

- No trailing whitespace in config files
- JSON: 2-space indentation
- Shell scripts: set -euo pipefail header
- Makefile: tabs for recipe lines, spaces for variable assignments

<!-- graft:start -->

## Graft — repo context graph

This repo is indexed in `graft/`: small linked markdown nodes that explain each
system and carry exact file:line spans, kept in sync with the code through git.

For ANY task here — understanding how something works, finding where code lives,
or scoping a change — get context from the graph before grepping or opening
source files. Re-ask freely (it's cheap) and reuse literal identifiers you
already have (symbol, error string, file name) as the query. New to this repo?
Run `graft map` first — a token-budgeted orientation (dir clusters, hubs,
hotspots), no LLM, no key.

- Run `graft ask "<your question>" --source` → ranked nodes with the relevant
  code spans inlined (each hit's ≤8-line crux by default; `--full` for whole
  definitions when the crux isn't enough). Match the tool to the task shape:
  for understanding or editing, the top node IS the answer — cite its
  `covers:` file:line spans and edit straight from `--source`. For
  exhaustive tasks ("every occurrence / every caller of this pattern"), ranked
  results are top-N, not complete — run `graft grep "<literal>"` instead
  (exhaustive over indexed files, grouped by enclosing symbol), falling back
  to raw `grep -rn` only for unindexed files.
- `graft skeleton <file>` → every definition's signature + span, ~10× cheaper
  than reading the file; use it to skim an API surface.
- `graft callers <symbol>` gives precomputed, exact edges — who calls this.
  Add `--direction out` for what it calls, or `--depth N` to walk
  transitively for the full blast radius. For structural questions, skip
  ranking and use this directly.
- Or browse: `graft/INDEX.md` lists every node; follow the links.
- Monorepos and folders of multiple repos rank fairly across sub-projects —
  hits carry `[scope/]` labels naming which one they're from. Narrow with
  `graft ask "<task>" --in <scope>/` once you know where you're working.

If a returned span is truncated ("+N more lines"), open the file at that exact
range before finalizing. Only open source files when a node genuinely lacks a
needed detail, and then at the exact file:line the node points to — never
re-read whole files.

After big code changes, refresh the graph with `graft build` (deterministic,
no API key, $0).

<!-- graft:end -->

**One-time setup**: `bun add -g @nanonets/graft` (or `npm install -g`; per-machine, no nixpkgs
derivation). Run `graft telemetry disable` once, then `graft build` to populate `graft/`
(git-ignored cache). Provenance/rebrand notes and telemetry citation: `CONTEXT.md`'s
`codegraph-tooling-consolidation (2026-09-18)` section.

**Note on the auto-generated section above**: `graft init`/`graft build` may overwrite the
`<!-- graft:start -->`/`<!-- graft:end -->` block; this note and everything below it live outside
it so a regeneration doesn't drop them.

**What's wired**: only the MCP server (`.mcp.json`) and the `Stop` hook — other automatic hooks
were removed as too costly; use `graft ask`/`callers`/`skeleton` on demand. Equivalent repo-local
(`--no-global`) wiring exists for Gemini CLI and OpenCode; global wiring is a separate,
out-of-scope decision (CONTEXT.md).

**Antigravity CLI is not covered** — graft hardcodes its Antigravity target to a global,
out-of-repo path, so `--no-global` drops it. Known upstream gap, not an oversight; don't "fix" it
without a deliberate global-wiring decision (CONTEXT.md).

**graphify is retired** (2026-09-18) — graft is now the sole code-graph tool. A stray `graphify`
reference anywhere is stale; remove it.

**Config-revert risk**: graft's upkeep mechanism can silently re-run `graft init` and overwrite
hand-patched files (`.claude/helpers/graft-{resolve,hooks,statusline}.cjs` and two
`permissions.allow` entries) whenever its git-ignored wiring-stamp cache is missing — always true
in a fresh `git worktree add` checkout, and also triggerable from the MCP server's boot path.
**Don't re-run `graft init` or hand-rewrite `graft-resolve.cjs`** — a revert discards that file's
**security fix** (project-tree exclusion + `package.json` `name` verification; see its SECURITY
comment) and the narrowed `permissions.allow` entries. `.claude/helpers/graft-integrity-check.cjs`
(wired on **both** `SessionStart` and `Stop`) instead restores those files from `git HEAD` and
repairs just the two known-bad `permissions.allow` entries (not the whole file, non-blocking).
Mechanism/history and known limitation: CONTEXT.md.

**Container builds**: `dockers/tools.Dockerfile` installs graft in the image. Telemetry opt-out
doesn't persist in a container, so set `DO_NOT_TRACK=1` or run `graft telemetry disable` on every
container start.
