# CONTEXT.md — domain terms and invariants

Persisted per the Grilling design-interview protocol (`agent/rules/grill-interview.md`). Each
section below was written at the end of one mission and captures terms/invariants that mission's
design decisions depend on, for future sessions that touch the same area. Sections are additive —
a new mission's design work appends a new section rather than overwriting prior ones.

## codegraph-tooling-consolidation (2026-09-18) — graft/graphify/executor/supermemory

Captures terms/invariants this mission's decisions depend on, for future sessions that touch
this repo's code-understanding tooling.

### Terms

- **graft**: `@nanonets/graft`, a tree-sitter-based code-graph tool. Sole code-graph tool in this
  repo (graphify retired). Provides an MCP server (`.mcp.json`) with tools
  `graft_find_code`/`graft_trace_calls`/`graft_find_all`/`graft_file_api`/`graft_repo_map`/
  `graft_check_freshness`, plus a CLI (`graft ask`/`callers`/`skeleton`/etc.). Its graph
  (`graft/`) is git-ignored, per-clone/per-worktree.
- **graphify** (retired): a community/god-node graph tool via AST+optional LLM
  labeling, git-committed graph, git hooks + merge driver. No longer wired in this repo.
- **executor**: the `executor`/`executor.sh` MCP gateway (`bun add -g executor`). On-demand daemon
  (not a persistent service unless `executor install` is run), ~localhost:4788. Used both directly
  (registered in `.mcp.json`/`pi/mcp.json`) and as a routing layer for graft-on-Pi (integration
  slug `graft-dotfiles`).
- **supermemory**: semantic memory store (`agent/scripts/hooks/supermemory.sh`), wired via
  `session-start.sh` (not `.claude/settings.json` hooks). Partially deployed — systemd units exist
  but were never enabled in this environment; currently inert (no server running).
- **graft's "upkeep" mechanism**: `@nanonets/graft`'s own `runUpkeep()`/`reconcileWiring()`
  (`dist/upkeep.js`, `dist/claude/hooks.js`), called from graft's `session-start` hook handler and
  (per graft's own source comments) from the graft MCP server's own boot path. Silently re-runs
  graft's own `init`, overwriting hand-patched files, whenever a git-ignored version stamp
  (`graft/.cache/wiring-stamp.json`) is missing — a structural certainty in every freshly created
  `git worktree add` checkout. See `.claude/helpers/graft-integrity-check.cjs`'s header comment for
  the full history (first observed 2026-09-13, reproduced again live during this mission's own
  measurement on 2026-09-18, and a third time — caught as pre-existing uncommitted main-tree state
  auto-repaired by `graft-integrity-check.cjs` — during this mission's own merge on 2026-09-19).

### Invariants this mission's decisions depend on

- `.claude/helpers/graft-integrity-check.cjs` MUST remain wired on both `SessionStart` and `Stop`
  in `.claude/settings.json` even after removing graft's other hooks —
  it is the only defense against the upkeep-triggered revert via the MCP-server-boot path, which
  removing the `session-start` hook entry does not close.
- graft's MCP server registration (`.mcp.json`) and CLI remain fully functional after this
  mission — only the *automatic, every-turn* hook wiring is removed. `graft ask`/`callers`/
  `skeleton`/the MCP tools are still the correct way to get code context on demand.
- graphify's removal is full-scope, not just git-mechanism-level: git merge driver +
  post-commit/post-checkout hooks, committed graph artifacts (`.claude/graph/graphify/`), all
  3 harnesses' hint-hook wiring and `validate-harness.sh` checks, documentation (CLAUDE.md,
  `agent/AGENTS*.md`, `agent/README.md`, etc.), the 3 Tier-B orchestration `SKILL.md` files, and
  the Nix package declaration (`nix/modules/home/packages/shared.nix` + its
  `nix/overlays/default.nix` override dependents). There is no code migration needed since nothing
  else in this repo depended on graphify's graph format programmatically. A repo-wide
  `grep -rIl graphify` (2026-09-18, post-cleanup) turns up only deliberately-preserved
  historical/CONTEXT.md mentions — verify this still holds before reusing this claim in a future
  session, since new references could reappear afterward.

## ai-config-optimization (2026-09-20) — 2026-09-19 DeepResearch起点の設定最適化

Captures terms/invariants this mission's decisions depend on, for future sessions that
re-run DeepResearch-driven config audits.

### Terms

- **`ConfigChange` hook**: Claude Code 2.1.x系で追加された新規hookイベント（`code.claude.com/docs/en/hooks`
  を2026-09-19にWebFetchで直接照合、matcher一覧`user_settings`/`project_settings`/`local_settings`/
  `policy_settings`/`skills`の記載を確認済み）。該当ファイルの変更を検知した時点で（次のStop/SessionStartの
  タイミングを待たずに）発火する — 「SessionStartより早い」という順序関係ではなく、セッション境界イベント
  (SessionStart/Stop)とは独立に、変更検知そのものをトリガーとする点が異なる。
- **verifier独立性の「実効票数」問題**: 9 judge・7 モデル系列のパネルでも実効独立票数は約2票（n_eff≈2.0–2.5）
  に留まるという知見自体は確定扱い（arXiv:2605.29800、Nine Judges Two Effective Votes、`SWARM_REFERENCES.md`
  の「確定」節参照）。一方「原因はベンダー系列ではなく判定対象の表層形式(surface form)の共有」という因果
  説明は、agent-swarmのjudgeパネルとは別設定（GRPO型RL訓練のrollout group、Qwen2.5）での単一プレプリント・
  未複製の報告（arXiv:2609.06386、2026-09、`SWARM_REFERENCES.md`参照）であり確度は低い。**数値の確定度と
  因果説明の確度を同一視しないこと** — `agent/SWARM.md` §2が既に述べる「intra-family < cross-family」という
  結論自体は変わらないが、「cross-familyというだけで十分」という誤解への追加のcaveatとして扱う。
- **既知バグクラスの持続確認**: `agent/skills/swarm-meta/SKILL.md`が根拠として引用するGitHub issue
  #26251/#43875（`disable-model-invocation`スキルがセッションのスキル一覧から消える不具合）はいずれも
  duplicateとしてclose済み（2026-09-19、GitHub直接fetchで確認）だが、同型バグは`#95469`（2026-09-18作成、
  2026-09-19のDeepResearch実施時点でOpen — 未検証・GitHub側の状態は以後変わりうる）等の後続issueで再発が
  継続している。issueがclose済みであることと、バグクラス自体が解消したことは別である。

### Invariants this mission's decisions depend on

- 新規`ConfigChange`hookは`.claude/settings.json`（プロジェクトスコープ）にのみ配線し、
  `agent/harnesses/claude/settings.json`（グローバル）へは拡張しない — graft自体が`--no-global`で
  初期化されている設計（CLAUDE.mdの「Graft — repo context graph」節）との整合性を保つため。
- `.claude/helpers/graft-integrity-check.cjs`の修復ロジック自体は変更しない。新規hookは既存スクリプトを
  そのまま呼ぶのみで、冪等性（既に修復済みなら2回目の呼び出しはno-op）に処理ループの収束を委ねる。
- `TaskOutput` tool関連の設定・利用方法は一切変更しない — 外部DeepResearchの「2.1.277で削除された」という
  主張は、本ミッション自身のセッションでの実際の`TaskOutput`呼び出し成功と矛盾するため採用しない
  （`agent/rules/verify-before-assert.md`のAI要約単独では断定しない原則）。将来のセッションでこの矛盾を
  再検証する場合は、まずこのセッションの実行環境（Claude Code バージョン）を確認すること。

