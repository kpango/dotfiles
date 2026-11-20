# Dotfiles Project — Agent Instructions

## Project Overview

This is kpango's personal dotfiles repository for Arch Linux (zen kernel) + Sway/Wayland environment. It manages configuration for: Zsh, Tmux, Ghostty, Helix, Sway, Waybar, Kanshi, Docker, systemd user services, Go environment, Nix, and Claude Code itself.

## Repository Structure

```
dotfiles/
├── Makefile              # Top-level; delegates to Makefile.d/
├── Makefile.d/           # Modular make targets
│   └── install.mk        # Primary install/link/copy logic
├── agent/                # Shared claude/omp/agy/hermes config (see "agent/ — 共通設定ディレクトリ" below)
│   ├── README.md         # Scope, provenance, migration history, and known gaps
│   ├── rules/            # 共通ルール(正典。$HOME側へ直接symlinkされる。omp用TTSR `vald-law-ttsr.md` 含む)
│   ├── skills/           # 共通スキル静的部分(34スキル、正典、frontmatter description <= 160文字)
│   ├── agents/           # 共通エージェント定義(25件、正典)。omp向けもagent/agentsへ直接symlink
│   │                       (tools:frontmatter変換はomp/extensions/subagents.tsの実行時変換)
│   ├── hooks/claude/, hooks/agy/, hooks/omp/  # ハーネス別hook正典:
│   │                       hooks/claude/(17件): decide.py委譲shim(security-gate.sh, vald-law-gate.sh,
│   │                       write-security-gate.sh) + rtk-rewrite.sh(ホワイトリスト) + swarm-*.sh等。
│   │                       hooks/agy/(4件): security-gate.sh, vald-law-gate.sh, rtk-rewrite.sh, session-start.sh。
│   │                       hooks/omp/(6件): security-gate.ts, rtk-optimizer.ts, auto-memory.ts + lib/ 3件。
│   │                       claude/hooks・agy/hooks・omp/extensionsからper-file symlinkで統合される(下記参照)
│   ├── scripts/hooks/    # rule_engine.py・decide.py(hook判定ロジック本体)
│   ├── scripts/sandbox/  # pa-sandbox (全ハーネス共通 bwrap --clearenv 隔離ラッパー -> ~/.local/bin/pa-sandbox)
│   ├── scripts/sync-verify.sh    # $HOME側の配線(symlink先が正しいか)を機械検証
│   ├── models/           # 抽象モデルルーティング定義 (schema.json)
│   ├── harnesses/        # 各CLI/Harness固有設定・マッピング管理 (SSoT集約)
│   │   ├── claude/       # Claude Code config (-> ~/.claude/) & model-routing.json
│   │   ├── omp/          # Oh My Pi config (-> ~/.omp/agent/: config.yml, models.yml, lsp.yml, dap.json, sol-pi.json; settings.json禁止)
│   │   ├── agy/          # Antigravity CLI config (-> ~/.agy/ & ~/.gemini/) & model-routing.json
│   │   └── hermes/       # Hermes Agent + OMH config (-> ~/.hermes/ & ~/.omh/: config.yaml, SOUL.md, 6 profiles, category-maestro.json)
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
├── systemd/              # systemd user services (incl. user/hermes-gateway.service)
└── arch/                 # Arch-specific configs (waybar, etc.)
```

## Key Makefile Targets

- `make dotfiles/install` — symlink/copy all dotfiles to $HOME
- `make claude/install` — deploy Claude Code config (runs after dotfiles/install)
- `make omp/install` — deploy Oh My Pi (OMP) config (runs after dotfiles/install)
- `make agy/install` — deploy Antigravity CLI config (runs after dotfiles/install)
- `make hermes/install` — deploy Hermes Agent + OMH config (runs after dotfiles/install)
- `make hermes/systemd/install` — enable/start `hermes-gateway.service` on host (refused inside Docker)
- `make arch/install` — full Arch Linux setup (runs dotfiles/install + AUR packages)
- `make dotfiles/clean` — remove all symlinks

## Multi-Harness Config Deployment (SSoT: agent/)

**リポジトリ内の各ハーネス設定は `agent/harnesses/{claude,omp,agy,hermes}/` に集約され、内部中間 symlink は一切存在しない**（旧 `pi` / `primeagent` / `codex` / `dsh` は廃止済み）。
`Makefile.d/install.mk`（および `nix/modules/home/dotfiles/agent-tools.nix`）が正典（`agent/` および `agent/harnesses/`）から `$HOME` 側へ**直接** symlink / 生成する。配線が正しいかは `agent/scripts/sync-verify.sh` で機械検証できる。

`settings.json` and `settings.local.json` in `agent/harnesses/claude/` are **symlinked** to `~/.claude/`.
`installed_plugins.json` is processed via `envsubst` and copied to `~/.claude/plugins/`.
`CLAUDE.md` in `agent/harnesses/claude/` is **symlinked** to `~/.claude/CLAUDE.md`.
`model-routing.json` in `agent/harnesses/claude/` is **symlinked** to `~/.claude/model-routing.json`.
`~/.claude/rules`・`~/.claude/agents`・`~/.claude/skills`・`~/.claude/RTK.md`・`~/.claude/SWARM.md`・
`~/.claude/SWARM_REFERENCES.md` は `agent/` から直接 symlink される。
`~/.claude/hooks` は `agent/harnesses/claude/hooks/` と `agent/hooks/claude/` の両方から個別ファイルsymlinkする「merged directory」として構成される（Vald Law 1–5 は `vald-law-gate.sh` 1ファイルへ統合済み）。

`config.yml`, `models.yml`, `lsp.yml`, `dap.json`, `sol-pi.json`, `AGENTS.md`, `SYSTEM.md`, `keybindings.json`, and `model-routing.json` in `agent/harnesses/omp/` are **symlinked** to `~/.omp/agent/`（**`settings.json` は絶対に symlink しない** — OMP の `migrateJsonToYml` による symlink 破壊を防ぐため YAML 正典で管理）。
`prompts/` and `themes/` in `agent/harnesses/omp/` are **symlinked** to `~/.omp/agent/`.
`~/.omp/agent/agents/` は `agent/agents/` へ直接 symlink される。
`~/.omp/agent/extensions` は `agent/harnesses/omp/extensions/` と `agent/hooks/omp/` の両方から個別ファイルsymlinkする「merged directory」として構成される（`bridge-hermes.ts` で Hermes `hermes_query` へ連携）。
`~/.omp/agent/rules`（`vald-law-ttsr.md` 含む）・`~/.omp/agent/skills`・`~/.omp/agent/RTK.md`・`~/.omp/agent/SWARM.md`・
`~/.omp/agent/SWARM_REFERENCES.md` は `agent/` から直接 symlink される。

`settings.json`, `AGENTS.md`, `SYSTEM.md`, `policies/`, `model-routing.json`, and `mcp_config.json` in `agent/harnesses/agy/` are
**symlinked** to `~/.agy/` and `~/.gemini/`（`~/.gemini/antigravity-cli/settings.json` は `install.sh` が 0600 通常ファイルとしてマージ）。
`~/.agy/hooks`・`~/.gemini/hooks` は `agent/harnesses/agy/hooks/` と `agent/hooks/agy/` の両方から個別ファイルsymlinkする「merged directory」として構成される。
`~/.agy/rules`・`~/.agy/agents`・`~/.agy/skills`・`~/.agy/RTK.md`・`~/.agy/SWARM.md`・
`~/.agy/SWARM_REFERENCES.md` は `agent/` から直接 symlink される。

`config.yaml`, `SOUL.md`, and `model-routing.json` in `agent/harnesses/hermes/` are **symlinked** to `~/.hermes/`.
`agent/skills` is **symlinked** to `~/.hermes/skills`, `agent/harnesses/hermes/profiles/{chief,researcher,swe,perf,sec-reviewer,ops}` are **symlinked per-entry** into `~/.hermes/profiles/`, and `agent/harnesses/hermes/omh/category-maestro.json` is **symlinked** to `~/.omh/routing/category-maestro.json`. `systemd/user/hermes-gateway.service` is linked to `~/.config/systemd/user/hermes-gateway.service` and enabled on the host via `make hermes/systemd/install`.

Shared sandbox wrapper `agent/scripts/sandbox/pa-sandbox` is **symlinked** to `~/.local/bin/pa-sandbox`.

## agent/ — SSoT共通設定 & ハーネス統合ディレクトリ

`SWARM.md`・`SWARM_REFERENCES.md`・`rules/`・`skills/`（静的部分）・`agents/`・`models/` を単一ソース `agent/` へ集約。
さらに全ハーネスの設定を `agent/harnesses/` 配下で一元管理。4エコシステム（Claude, OMP, AGY, Hermes）への配線は
`Makefile.d/install.mk`・Nix の両方が `agent/` から直接行う。各ハーネスのモデル差異は `model-routing.json` と抽象Tier（Low, Medium, High, XHigh, Max）により透過的に解決される。

**Instruction files — one body, one root.** `agent/AGENTS.md` is the root of the global instructions (generic core +
`agent/AGENTS-<tool>-supplement.md`, deployed per tool; see "Multi-Harness Config Deployment"). This file, the
repo-root `AGENTS.md`, is the only body of the dotfiles _project_ instructions; `CLAUDE.md` and `GEMINI.md` next to
it are symlinks to it (no copies, so they cannot drift), and it applies only when an agent is run from this
directory. Edit this file, never the symlinks; the same Tier B write-scope rule as for any `AGENTS.md` applies.
`agent/scripts/test-root-agent-files.sh` checks the layout.

## Working in This Repo

- Always use `make` targets for installation, never manual symlinks
- Test symlinks with `ls -la ~/<target>` before committing
- JSON files must be valid — check with `python3 -m json.tool`
- Zsh config changes: source files are in `zsh/` directory
- systemd services: use `systemctl --user` on the host only (never inside Docker)
- Packages: prefer `pacman` over AUR when available; use `paru` for AUR
- **Action Fusion**: after editing a file, run its verification command (test/build/lint) before
  the next edit — don't stack unverified edits. Sourced from SoL-Pi (arXiv:2609.20519) with
  `agent/harnesses/omp/sol-pi.json` tracking OMP feature flags (`actionFusion`, `observationPack`,
  `evidencePreservingReducer`).

## Common Tasks

**Add new dotfile mapping:**

1. Add entry to `DOTFILES_MAP` in `Makefile.d/install.mk`
2. Run `make dotfiles/install`

**Update Claude settings:**

1. Edit `agent/harnesses/claude/settings.json` or `agent/harnesses/claude/settings.local.json`
2. Changes take effect immediately (hot-reload)

**Add new plugin:**

1. Add to `enabledPlugins` in `agent/harnesses/claude/settings.json`
2. Add marketplace to `extraKnownMarketplaces` if new source
3. Update `agent/harnesses/claude/installed_plugins.json` template

**Update systemd service:**

1. Edit file in `systemd/user/`
2. Run `systemctl --user daemon-reload && systemctl --user restart <service>` on the host

## Style Notes

- No trailing whitespace in config files
- JSON: 2-space indentation
- Shell scripts: set -euo pipefail header
- Makefile: tabs for recipe lines, spaces for variable assignments

<!-- trail:start -->

## Trail — repo context graph

This repo is indexed in `.trail/cache/`: small linked markdown nodes that explain each
system and carry exact file:line spans, kept in sync with the code through git.

For ANY task here — understanding how something works, finding where code lives,
or scoping a change — get context from the graph before grepping or opening
source files. Re-ask freely (it's cheap) and reuse literal identifiers you
already have (symbol, error string, file name) as the query. New to this repo?
Run `trail map` first — a token-budgeted orientation (dir clusters, hubs,
hotspots), no LLM, no key.

- Run `trail ask "<your question>" --source` → ranked nodes with the relevant
  code spans inlined (each hit's ≤8-line crux by default; `--full` for whole
  definitions when the crux isn't enough). Match the tool to the task shape:
  for understanding or editing, the top node IS the answer — cite its
  `covers:` file:line spans and edit straight from `--source`. For
  exhaustive tasks ("every occurrence / every caller of this pattern"), ranked
  results are top-N, not complete — run `trail grep "<literal>"` instead
  (exhaustive over indexed files, grouped by enclosing symbol), falling back
  to raw `grep -rn` only for unindexed files.
- `trail skeleton <file>` → every definition's signature + span, ~10× cheaper
  than reading the file; use it to skim an API surface.
- `trail callers <symbol>` gives precomputed, exact edges — who calls this.
  Add `--direction out` for what it calls, or `--depth N` to walk
  transitively for the full blast radius. For structural questions, skip
  ranking and use this directly.
- Or browse: `.trail/cache/INDEX.md` lists every node; follow the links.
- Monorepos and folders of multiple repos rank fairly across sub-projects —
  hits carry `[scope/]` labels naming which one they're from. Narrow with
  `trail ask "<task>" --in <scope>/` once you know where you're working.

If a returned span is truncated ("+N more lines"), open the file at that exact
range before finalizing. Only open source files when a node genuinely lacks a
needed detail, and then at the exact file:line the node points to — never
re-read whole files.

After big code changes, refresh the graph with `trail build` (deterministic,
no API key, $0).
<!-- trail:end -->

**One-time setup**: `bun add -g @trailhq/trail-code` (per-machine, no nixpkgs
derivation; Node `^20.16.0 || >=22.3.0`). Run `trail telemetry disable` once, then `trail build`
to populate `.trail/cache/` (git-ignored via `.trail/.gitignore`). Provenance/rebrand notes and
telemetry citation: `CONTEXT.md`'s `trail-code-migration (2026-11-20)` section.

**Trail-Code** (upstream `github.com/trailhq/Trail-Code`, package `@trailhq/trail-code`, command
`trail`; the former name is kept only in `CONTEXT.md`'s history). `.trail/learnings/` exists, so the
code map lives in `.trail/cache/`. The shared skill is `agent/skills/trail/`.

**Note on the auto-generated section above**: `trail init`/`trail build` may overwrite the
`<!-- trail:start -->`/`<!-- trail:end -->` block; this note and everything below it live outside
it so a regeneration doesn't drop them. The root `CLAUDE.md` and `GEMINI.md` are symlinks to this file:
if a Trail command rewrites one of them as a regular file, restore the symlink (`test-root-agent-files.sh` fails
on that) and merge any new Trail block text back into this file.

**What's wired** (decided 2026-11-20, replacing the earlier "no auto-hooks" stance): Trail's Claude Code
auto-hooks are on. Project level: `.claude/settings.json` SessionStart → `.trail/hook.cjs`, statusline and
allowlist in `.claude/settings.local.json`. User level: `~/.claude/helpers/trail-hooks.cjs` (trail still ships
the shim under this name) wired from `agent/harnesses/claude/settings.json`. `trail init --team` is the way
to (re)wire it. **Watch out**: `--no-agents` (and `--agents`) strip Trail's wiring for the agents not listed,
and that reaches tracked files — it deleted `.gemini/settings.json` and `opencode.json`, dropped the Trail
block from this file, reformatted `agent/harnesses/agy/mcp_config.json`, and rewrote
`agent/skills/trail/SKILL.md` back to a >160-char description (fails `test-catalog-health.sh`). After any
`trail init`, check `git status` and `git checkout --` what it touched outside `.claude/` and `.trail/`.

**graphify is retired** (2026-09-18) — the Trail-Code CLI is the sole code-graph tool.

**Container builds**: `dockers/tools.Dockerfile` installs the `@trailhq/trail-code` CLI in the image.
Telemetry opt-out doesn't persist in a container, so set `DO_NOT_TRACK=1` or run
`trail telemetry disable` on every container start.
