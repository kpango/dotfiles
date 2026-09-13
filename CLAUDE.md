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

**Sandboxed/CI environments without a Nix-managed graphify (expected, not a repo bug)**: `graphify` itself is installed via Nix (`nix/overlays/default.nix`, `nix/modules/home/packages/shared.nix`) on the maintainer's actual host — it is not vendored into this repo and is not present in every environment that can check this repo out. A Claude Code sandbox (or any other environment without that Nix profile) commits successfully, but the post-commit/post-checkout hook logs `[graphify hook] could not locate a Python with graphify installed` and skips the rebuild (exit 0, non-fatal) — confirmed 2026-09-13 by direct probing: the installed launcher (at the doubled-segment path `/usr/local/local/bin/graphify` — re-verified with `ls`, not a typo; `/usr/local/bin/graphify` does not exist in this sandbox) itself raises `ModuleNotFoundError: No module named 'graphify'` when invoked directly in such an environment, i.e. the package genuinely isn't there, not merely off PATH. Treat this warning as an environment gap, not something to "fix" by editing the hook script (it is regenerated by `graphify hook install`, not tracked in this repo) — the graph simply won't be rebuilt from commits made in such an environment until the next commit from a host with a working `graphify`.

**Git worktrees**: the post-commit/post-checkout hooks exit early (before any Python-detection probing) whenever `git rev-parse --git-dir` differs from `git rev-parse --git-common-dir` — confirmed 2026-09-13 by reading the installed hooks directly (`.git/hooks/post-commit`/`post-checkout`, lines comparing `$_GFY_GITDIR`/`$_GFY_COMMONDIR` and exiting 0 on mismatch) — i.e. inside any `git worktree add` checkout (mission/task worktrees under `.claude/worktrees/`, per `agent/SWARM.md` §4 "Git Worktree Isolation"). Hooks only run from the main checkout; committing from inside a worktree neither rebuilds nor warns about the graph.

Rules:

- For codebase questions, first run `graphify query "<question>"` when .claude/graph/graphify/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If .claude/graph/graphify/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read .claude/graph/graphify/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost). Commit the resulting changes to the 5 shared files above so other contributors get the update.

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

**One-time setup**: `bun add -g @nanonets/graft` (or `npm install -g @nanonets/graft`; not
Nix-managed like graphify above — no nixpkgs derivation exists for it as of this writing). Run
`graft telemetry disable` (machine-wide setting, not repo-scoped; anonymous aggregate-only stats
to `events.nanonets.com` per its own [TELEMETRY.md](https://github.com/NanoNets/context-graph-engine/blob/main/TELEMETRY.md) — disabled here for consistency with this
repo's no-unnecessary-egress stance elsewhere). Then `graft build` once to populate `graft/`
(git-ignored local cache, unlike graphify's committed graph — see `.gitignore`). `graft init` (already run for this repo; see `.claude/settings.json`'s
graft hook block and `.mcp.json` for Claude Code) wired the Claude Code MCP server +
PostToolUse/Stop/UserPromptSubmit/SessionStart hooks and statusline, plus equivalent MCP
registrations for the other agents this repo already integrates with: Gemini CLI
(`.gemini/settings.json` for MCP wiring, plus the identical fenced graft section written to two
separate places — `AGENTS.md`, a pre-existing, git-tracked symlink at this repo's root pointing to
this very file [`readlink AGENTS.md` → `CLAUDE.md`, so that fenced section actually landed in this
file, not a separate one], and `GEMINI.md`, a genuinely separate regular file `graft init` also
wrote, not a symlink to anything — confirmed via `ls -la GEMINI.md`) and OpenCode
(`opencode.json`) — **for this repo only** in every case (`--no-global`,
deliberate — see graphify's Nix-wide install above for a wired-everywhere alternative). Wiring
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

**Coexistence with graphify**: the two tools' Claude Code hooks don't fire on the same event (see
below). This is **not** a claim that every place graphify gets invoked in
this repo is listed below — graphify also has a git merge driver (`.gitattributes` +
`.git/config`'s `merge.graphify.driver`, see the "One-time setup" note above) and a
`graphify hook status` check in `agent/harnesses/claude/validate-harness.sh`, neither of which is
a Claude Code hook event at all, so they're outside the scope of this comparison rather than
enumerated here. What actually matters — and what this comparison is scoped to — is whether
graft's Claude Code hooks and graphify's Claude Code hooks can fire on the same event: graphify's
two known Claude-Code-lifecycle hooks are `PreToolUse:Bash` (`.claude/settings.json`'s
pre-existing `graphify-hint.sh` entry) and `PreCompact` (`agent/hooks/claude/pre-compact.sh`,
wired via the user's **global** `~/.claude/settings.json`, running `graphify update .`). graft,
wired only in this repo's project-level `.claude/settings.json` (this change), fires on
`PostToolUse`, `Stop`, `UserPromptSubmit`, and `SessionStart` — none of which is `PreToolUse` or
`PreCompact`, so the two tools' Claude Code hooks don't double-fire on the same event. graphify's
git-level mechanisms (post-commit, post-checkout, the merge driver) have no graft counterpart at
all — graft installs no git hooks and no merge driver — so there's no git-level conflict either,
independent of the Claude Code hook comparison above. Both index this same repo independently (graphify:
community/god-node graph via AST+optional LLM labeling, committed; graft: linked-card graph via
tree-sitter, git-ignored) — treat them as complementary, not a migration: `graphify query`/`path`/
`explain` for broad architecture and community structure, `graft ask`/`callers`/`skeleton` for
fast per-symbol lookups with inlined code spans. Prefer whichever answers the question more
directly; there is no house rule yet on which to try first.

**Note on the auto-generated section above**: the `<!-- graft:start -->`/`<!-- graft:end -->`
block is written and may be overwritten by `graft init`/`graft build` — the two paragraphs above
(setup, coexistence) are deliberately placed outside it so a future regeneration doesn't drop them.

**Reverted-file detection and auto-repair**: `.claude/helpers/graft-hooks.cjs`,
`graft-statusline.cjs`, `graft-resolve.cjs`, and the graft entries in `.claude/settings.json` can
get silently overwritten back to `@nanonets/graft`'s own bundled template, discarding the security
fix in `graft-resolve.cjs` (project-tree exclusion + package.json `name` verification — see that
file's SECURITY comment) and the narrowed `permissions.allow` entries. This is not a rare accident
from someone manually re-running `graft init` — reading graft's own installed source
(`dist/upkeep.js`, `dist/claude/hooks.js`) confirms its `session-start` hook unconditionally calls
`runUpkeep()` → `reconcileWiring()`, which reads a version stamp at `graft/.cache/wiring-stamp.json`
and treats a **missing** stamp as license to silently re-run its own init and overwrite these
files. That stamp lives under `graft/`, which this repo's own `.gitignore` excludes from git (see
above) — so it is necessarily absent in every freshly created `git worktree add` checkout (this
repo's normal mission/task-worktree workflow), making the revert-on-first-session-start a
structural certainty for any new worktree, not a one-off: it happened once during this repo's
Phase 4.5 adversarial review (2026-09-13), then again — with nobody running `graft init` by
hand — in a freshly created, unrelated task worktree the same day, which is what led to reading
graft's source directly instead of continuing to guess at a cause.

`.claude/helpers/graft-integrity-check.cjs` is wired into **both** `SessionStart` (right after
graft's own `session-start` hook entry, to close the window as early as possible in a given
session) and `Stop` (a second backstop) in `.claude/settings.json`. On detecting a reversion it
now **actively restores** `graft-resolve.cjs`/`graft-hooks.cjs`/`graft-statusline.cjs` from git
HEAD and surgically repairs just the two known-bad `permissions.allow` entries in
`.claude/settings.json` (not a full-file restore there, since that file can legitimately carry
other, unrelated local edits) — still non-blocking (stderr only, never halts the hook chain). See
that file's own header for exactly what it checks and its known limitation (literal-marker
matching, not a full behavioral check, so a sufficiently different rewrite could still evade it).
