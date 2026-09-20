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

**One-time setup**: `bun add -g @nanonets/graft` (or `npm install -g @nanonets/graft`; no nixpkgs
derivation exists for it as of this writing, so it is installed per-machine rather than declared in
this repo's Nix config). Run `graft telemetry disable` (machine-wide setting, not repo-scoped;
anonymous aggregate-only stats to `events.nanonets.com` per its own
[TELEMETRY.md](https://github.com/NanoNets/context-graph-engine/blob/main/TELEMETRY.md) — disabled
here for consistency with this repo's no-unnecessary-egress stance elsewhere). Then `graft build`
once to populate `graft/` (git-ignored local cache — see `.gitignore`). `graft init` (already run
for this repo; see `.claude/settings.json`'s graft hook block and `.mcp.json` for Claude Code)
originally wired the Claude Code MCP server + PostToolUse/Stop/UserPromptSubmit/SessionStart hooks
and statusline; **as of 2026-09-18, only the MCP server registration and the `Stop` hook remain
wired** — the PostToolUse (`post-edit`,
`tool-savings`), `UserPromptSubmit`, and `SessionStart` hook entries were removed after live
measurement showed they cost 3.0s/edit, 425ms/prompt, and 1.1s/session respectively for
automatic context injection that graft's MCP tools/CLI provide just as well on request. Also
equivalent MCP registrations for the other agents this repo already integrates with: Gemini CLI
(`.gemini/settings.json` for MCP wiring, plus the identical fenced graft section written to two
separate places — `AGENTS.md`, a pre-existing, git-tracked symlink at this repo's root pointing to
this very file [`readlink AGENTS.md` → `CLAUDE.md`, so that fenced section actually landed in this
file, not a separate one], and `GEMINI.md`, a genuinely separate regular file `graft init` also
wrote, not a symlink to anything — confirmed via `ls -la GEMINI.md`) and OpenCode
(`opencode.json`) — **for this repo only** in every case (`--no-global`, deliberate). Wiring
graft globally (`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.gemini/`, etc. — what
`graft init` writes without `--no-global`) is a separate decision affecting every other repo you
open with these agents, and is intentionally out of scope here.

**Antigravity CLI is not covered by the above**, despite being one of this repo's five wired
harnesses (`agent/harnesses/agy/`) — confirmed by reading `@nanonets/graft`'s own installed
source (`dist/hosts/mcp-config.js`): graft treats `gemini` (writes the repo-local
`.gemini/settings.json` above) and `antigravity` as two distinct targets, and the `antigravity`
target is hardcoded to a *global* path (`~/.gemini/config/mcp_config.json`, marked
`scope: 'global'` in graft's own target list, and captioned there as graft's own known gap
`#62`), which its `mcpTargets(...).filter((t) => opts.global !== false || t.scope !== 'global')`
unconditionally drops whenever `--no-global` is passed — exactly the flag this repo's `graft init`
run used. So this mission neither wrote nor was capable of writing a graft MCP entry for
Antigravity specifically; `infra-config-adversarial-reviewer`'s Phase 4.5 pass (2026-09-13) caught
an earlier draft of this section wrongly claiming otherwise. Wiring Antigravity for real would mean
writing to that global, out-of-repo path — the same globally-scoped decision already declined
above for the other agents, so it's declined here for the same reason, not merely left as an
oversight.

**graphify retired**: this repo previously also ran `graphify` (a separate community/god-node graph
tool via AST+optional LLM labeling, git-committed graph, own git merge driver + post-commit/
post-checkout hooks) alongside graft, with an unclear house rule on which to prefer for a given
question. Graphify was retired entirely (2026-09-18) — its git merge driver, git hooks,
`PreToolUse:Bash`/`PreCompact` Claude Code hooks, Pi
MCP-tool bridge, and committed graph artifacts (`.claude/graph/graphify/`, ~3.3MB) are all removed
— consolidating on graft as this repo's sole code-graph tool. If you find a stray reference to
`graphify` anywhere in this repo that this cleanup missed, it's stale; grep for it and remove it
rather than treating it as still-live guidance.

**Note on the auto-generated section above**: the `<!-- graft:start -->`/`<!-- graft:end -->`
block is written and may be overwritten by `graft init`/`graft build` — the two paragraphs above
(setup, coexistence) are deliberately placed outside it so a future regeneration doesn't drop them.

**Reverted-file detection and auto-repair**: `.claude/helpers/graft-hooks.cjs`,
`graft-statusline.cjs`, `graft-resolve.cjs`, and the graft entries in `.claude/settings.json` can
get silently overwritten back to `@nanonets/graft`'s own bundled template, discarding the security
fix in `graft-resolve.cjs` (project-tree exclusion + package.json `name` verification — see that
file's SECURITY comment) and the narrowed `permissions.allow` entries. This is not a rare accident
from someone manually re-running `graft init` — reading graft's own installed source
(`dist/upkeep.js`, `dist/claude/hooks.js`) confirms `runUpkeep()` → `reconcileWiring()` treats a
**missing** version stamp at `graft/.cache/wiring-stamp.json` as license to silently re-run its own
init and overwrite these files. That stamp lives under `graft/`, which this repo's own `.gitignore`
excludes from git — so it is necessarily absent in every freshly created `git worktree add`
checkout (this repo's normal mission/task-worktree workflow). Originally this was triggered by
graft's own Claude Code `session-start` hook on every session; **that hook entry was removed on
2026-09-18** (it was also a 1.1s-per-session cost), which closes that
specific trigger, but graft's own source separately documents `runUpkeep()` also running from "the
MCP server's own boot path" — since this repo still registers graft as an MCP server (`.mcp.json`),
that second trigger is outside this repo's control and may still independently cause the same
revert. The bug recurred twice observed (Phase 4.5 adversarial review 2026-09-13, then an unrelated
fresh task worktree the same day) before the mechanism was root-caused by reading graft's source
directly.

`.claude/helpers/graft-integrity-check.cjs` remains wired on **both** `SessionStart` and `Stop` in
`.claude/settings.json` specifically because the MCP-server-boot trigger above isn't closed by
the `session-start` hook removal above. On detecting a reversion it **actively restores**
`graft-resolve.cjs`/`graft-hooks.cjs`/`graft-statusline.cjs` from git HEAD and surgically repairs
just the two known-bad `permissions.allow` entries in `.claude/settings.json` (not a full-file
restore there, since that file can legitimately carry other, unrelated local edits) — still
non-blocking (stderr only, never halts the hook chain). See that file's own header for exactly what
it checks and its known limitation (literal-marker matching, not a full behavioral check, so a
sufficiently different rewrite could still evade it).
