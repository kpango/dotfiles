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
│   ├── skills/             # claude/pi/agy 共通スキル静的部分(33スキル、正典)。動的統計ファイルはclaude/pi/agy各skills/に実ファイルとして残る
│   ├── agents/             # claude/agy/pi 共通エージェント定義(25件、正典)。pi向けもagent/agentsへ直接symlink
│   │                         (tools:frontmatter変換はpi/extensions/subagents.tsの実行時変換、旧gen-pi-agents.shは廃止済み)
│   ├── hooks/claude/, hooks/agy/, hooks/pi/  # claude/agy/pi実体移動済みhookファイル(計30ファイル、正典)。
│   │                         hooks/claude/(20件)はdecide.py委譲shim本体(7件)+rtk-rewrite.sh
│   │                         (判定ロジック共有なしの薄いラッパー、1件)+claude固有の非shimロジック
│   │                         (swarm-*.sh等12件、2026-09-04にclaude/hooks/から実体移動)の混在。
│   │                         hooks/agy/(5件)はdecide.py委譲shim4件+rtk-rewrite.sh 1件、
│   │                         hooks/pi/(5件)はdecide.py委譲shim3件+rtk-optimizer.ts 1件+
│   │                         共有ライブラリlib/shared.ts 1件の混在(いずれもdecide.py shimのみでは
│   │                         ない)。
│   │                         claude/hooks・agy/hooks・pi/extensionsからper-file symlinkで統合される(下記参照)
│   ├── scripts/hooks/     # rule_engine.py・decide.py(hook判定ロジック本体、上記shimが呼び出す)
│   ├── scripts/sync-verify.sh    # $HOME側の配線(symlink先が正しいか)を機械検証
│   ├── models/            # 抽象モデルルーティング定義 (schema.json)
│   ├── harnesses/         # 各CLI/Harness固有設定・マッピング管理 (SSoT集約)
│   │   ├── claude/        # Claude Code config (-> ~/.claude/) & model-routing.json
│   │   ├── pi/            # Pi Coding Agent config (-> ~/.pi/agent/) & model-routing.json
│   │   ├── agy/           # Antigravity CLI config (-> ~/.agy/ & ~/.gemini/) & model-routing.json
│   │   ├── codex/         # OpenAI Codex config (-> ~/.codex/) & model-routing.json
│   │   └── primeagent/    # PrimeAgent config (-> ~/.prime/agent/) & model-routing.json
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
- `make primeagent/install` — deploy PrimeAgent config (runs after dotfiles/install)
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
`settings.json`, `models.json`, and `model-routing.json` in `agent/harnesses/primeagent/` are **symlinked** to `~/.prime/agent/`.

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

## graphify

This project has a knowledge graph at .claude/graph/graphify/ (via `GRAPHIFY_OUT`, set by the `graphify` zsh wrapper) with god nodes, community structure, and cross-file relationships.

**Shared with contributors**: `graph.json`, `GRAPH_REPORT.md`, `manifest.json`, `.graphify_labels.json`, and `.graphify_labels.json.sig` are committed (see `.gitignore`'s allowlist under `.claude/graph/graphify/*`) so a fresh clone gets a ready-to-query graph without paying for a full re-extraction. `cost.json`, `graph.html`, `.graphify_root`, and `cache/` stay local-only (personal API spend, a large regenerable viewer, a non-portable absolute-path marker, and a cache with no merge driver, respectively).

**One-time setup after cloning**: run `GRAPHIFY_OUT=".claude/graph/graphify" command graphify hook install` once. This registers the `graphify` git merge driver for `graph.json` (via `.gitattributes`, already committed) in your local `.git/config`, and installs post-commit/post-checkout hooks that keep the graph in sync as you switch branches — none of this is itself version-controllable (git hooks and merge-driver commands never live in the repo), so every clone needs to run it. Querying the committed graph (`graphify query`/`path`/`explain`) needs no API key; only re-labeling communities with an LLM backend does.

Rules:

- For codebase questions, first run `graphify query "<question>"` when .claude/graph/graphify/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If .claude/graph/graphify/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read .claude/graph/graphify/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost). Commit the resulting changes to the 5 shared files above so other contributors get the update.
