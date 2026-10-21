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
  mission — only the _automatic, every-turn_ hook wiring is removed. `graft ask`/`callers`/
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

### 補足: CLAUDE.md から移設した原文（2026-09-24、T7でのCLAUDE.md圧縮に伴う移設）

以下は圧縮前の CLAUDE.md 本文からの引用で、要約・翻訳はせず原文（英語、バッククォート等の記法も含め
そのまま）を移設した（「元の文言をできるだけ保つ」ため）。各引用ブロックの前の日本語の一文は位置づけを
示す見出しに過ぎず、引用内容そのものの言い換えではない。

**graft init の当初配線・削減の計測値・provenance・他エージェントへの同等MCP配線**（原文）:

> **One-time setup**: `bun add -g @nanonets/graft` (or `npm install -g @nanonets/graft`; no nixpkgs
> derivation exists for it as of this writing, so it is installed per-machine rather than declared in
> this repo's Nix config). **Provenance note**: the upstream GitHub repo has since moved to
> `github.com/trailhq/Graft` (a rebrand), but the npm package name is unchanged — verify with
> `npm view @nanonets/graft` (last checked 2026-09-23) rather than assuming the GitHub rename means
> the package is abandoned; keep using `@nanonets/graft` as below. Run `graft telemetry disable`
> (machine-wide setting, not repo-scoped;
> anonymous aggregate-only stats to `events.nanonets.com` per its own
> [TELEMETRY.md](https://github.com/NanoNets/context-graph-engine/blob/main/TELEMETRY.md) — disabled
> here for consistency with this repo's no-unnecessary-egress stance elsewhere). Then `graft build`
> once to populate `graft/` (git-ignored local cache — see `.gitignore`). `graft init` (already run
> for this repo; see `.claude/settings.json`'s graft hook block and `.mcp.json` for Claude Code)
> originally wired the Claude Code MCP server + PostToolUse/Stop/UserPromptSubmit/SessionStart hooks
> and statusline; **as of 2026-09-18, only the MCP server registration and the `Stop` hook remain
> wired** — the PostToolUse (`post-edit`,
> `tool-savings`), `UserPromptSubmit`, and `SessionStart` hook entries were removed after live
> measurement showed they cost 3.0s/edit, 425ms/prompt, and 1.1s/session respectively for
> automatic context injection that graft's MCP tools/CLI provide just as well on request. Also
> equivalent MCP registrations for the other agents this repo already integrates with: Gemini CLI
> (`.gemini/settings.json` for MCP wiring, plus the identical fenced graft section written to two
> separate places — `AGENTS.md`, a pre-existing, git-tracked symlink at this repo's root pointing to
> this very file [`readlink AGENTS.md` → `CLAUDE.md`, so that fenced section actually landed in this
> file, not a separate one], and `GEMINI.md`, a genuinely separate regular file `graft init` also
> wrote, not a symlink to anything — confirmed via `ls -la GEMINI.md`) and OpenCode
> (`opencode.json`) — **for this repo only** in every case (`--no-global`, deliberate). Wiring
> graft globally (`~/.claude/settings.json`, `~/.codex/config.toml`, `~/.gemini/`, etc. — what
> `graft init` writes without `--no-global`) is a separate decision affecting every other repo you
> open with these agents, and is intentionally out of scope here.

**Antigravity非対応の根拠**（原文）:

> **Antigravity CLI is not covered by the above**, despite being one of this repo's five wired
> harnesses (`agent/harnesses/agy/`) — confirmed by reading `@nanonets/graft`'s own installed
> source (`dist/hosts/mcp-config.js`): graft treats `gemini` (writes the repo-local
> `.gemini/settings.json` above) and `antigravity` as two distinct targets, and the `antigravity`
> target is hardcoded to a _global_ path (`~/.gemini/config/mcp_config.json`, marked
> `scope: 'global'` in graft's own target list, and captioned there as graft's own known gap
> `#62`), which its `mcpTargets(...).filter((t) => opts.global !== false || t.scope !== 'global')`
> unconditionally drops whenever `--no-global` is passed — exactly the flag this repo's `graft init`
> run used. So this mission neither wrote nor was capable of writing a graft MCP entry for
> Antigravity specifically; `infra-config-adversarial-reviewer`'s Phase 4.5 pass (2026-09-13) caught
> an earlier draft of this section wrongly claiming otherwise. Wiring Antigravity for real would mean
> writing to that global, out-of-repo path — the same globally-scoped decision already declined
> above for the other agents, so it's declined here for the same reason, not merely left as an
> oversight.

**graphify退役の詳細**（原文）:

> **graphify retired**: this repo previously also ran `graphify` (a separate community/god-node graph
> tool via AST+optional LLM labeling, git-committed graph, own git merge driver + post-commit/
> post-checkout hooks) alongside graft, with an unclear house rule on which to prefer for a given
> question. Graphify was retired entirely (2026-09-18) — its git merge driver, git hooks,
> `PreToolUse:Bash`/`PreCompact` Claude Code hooks, Pi
> MCP-tool bridge, and committed graph artifacts (`.claude/graph/graphify/`, ~3.3MB) are all removed
> — consolidating on graft as this repo's sole code-graph tool. If you find a stray reference to
> `graphify` anywhere in this repo that this cleanup missed, it's stale; grep for it and remove it
> rather than treating it as still-live guidance.

**Reverted-file detection and auto-repair の全文**（原文。CLAUDE.mdには要点――`graft-resolve.cjs`
のセキュリティ修正（project-tree exclusion + `package.json` `name` 検証）を捨てないための注意、
`git HEAD`から何を復元するか、`.claude/settings.json`の`permissions.allow`をファイル全体ではなく
既知の2エントリだけ外科的に修復すること――のみを残し、理由と既知の限界はここに移設した）:

> **Reverted-file detection and auto-repair**: `.claude/helpers/graft-hooks.cjs`,
> `graft-statusline.cjs`, `graft-resolve.cjs`, and the graft entries in `.claude/settings.json` can
> get silently overwritten back to `@nanonets/graft`'s own bundled template, discarding the security
> fix in `graft-resolve.cjs` (project-tree exclusion + package.json `name` verification — see that
> file's SECURITY comment) and the narrowed `permissions.allow` entries. This is not a rare accident
> from someone manually re-running `graft init` — reading graft's own installed source
> (`dist/upkeep.js`, `dist/claude/hooks.js`) confirms `runUpkeep()` → `reconcileWiring()` treats a
> **missing** version stamp at `graft/.cache/wiring-stamp.json` as license to silently re-run its own
> init and overwrite these files. That stamp lives under `graft/`, which this repo's own `.gitignore`
> excludes from git — so it is necessarily absent in every freshly created `git worktree add`
> checkout (this repo's normal mission/task-worktree workflow). Originally this was triggered by
> graft's own Claude Code `session-start` hook on every session; **that hook entry was removed on
> 2026-09-18** (it was also a 1.1s-per-session cost), which closes that
> specific trigger, but graft's own source separately documents `runUpkeep()` also running from "the
> MCP server's own boot path" — since this repo still registers graft as an MCP server (`.mcp.json`),
> that second trigger is outside this repo's control and may still independently cause the same
> revert. The bug recurred twice observed (Phase 4.5 adversarial review 2026-09-13, then an unrelated
> fresh task worktree the same day) before the mechanism was root-caused by reading graft's source
> directly.
>
> `.claude/helpers/graft-integrity-check.cjs` remains wired on **both** `SessionStart` and `Stop` in
> `.claude/settings.json` specifically because the MCP-server-boot trigger above isn't closed by
> the `session-start` hook removal above. On detecting a reversion it **actively restores**
> `graft-resolve.cjs`/`graft-hooks.cjs`/`graft-statusline.cjs` from git HEAD and surgically repairs
> just the two known-bad `permissions.allow` entries in `.claude/settings.json` (not a full-file
> restore there, since that file can legitimately carry other, unrelated local edits) — still
> non-blocking (stderr only, never halts the hook chain). See that file's own header for exactly what
> it checks and its known limitation (literal-marker matching, not a full behavioral check, so a
> sufficiently different rewrite could still evade it).

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

## agent-pdf-deepresearch-env-overhaul (2026-09-23) — agent.pdf DeepResearchに基づくSkill/Hook/Rule見直し

`agent.pdf`（「次世代AIエージェント開発環境の統合仕様書」）のDeepResearch検証結果に基づき、
Claude/Pi/AGY Agent開発環境（Skill・Hook・Plugin・Extension・Rule）を見直すミッションの
Grilling設計面談で合意した決定事項。

### Terms

- **SoL-Pi**: NVIDIA発の論文/リポジトリ（arXiv:2609.20519, github.com/NVlabs/SoL-Pi）。
  ハーネス層に自律研究ループを適用し4つの効率化メカニズムを実証。ここでの「Pi」は
  `earendil-works/pi`（旧 badlogic/pi-mono）を指し、ユーザーの Pi Coding Agent
  （`agent/harnesses/pi/`）の実体そのもの。
- **ObservationPack**: 10KiB超のツール出力をローカル退避し、3リクエスト目以降は固定ポインタ
  （Stable Handle）+先頭・末尾抜粋に置換する機構。
- **Evidence-Preserving Reducer**: 4KiB以上のビルド/テストログを小型モデルで要約し、決定論的
  検証器が引用行の完全一致を照合、不一致/資格情報検出時は原本へ即時フォールバックする機構。
- **Action Fusion**: ファイル編集と直後の検証コマンドを単一ツールリクエストに融合し中間ターンを
  排除する機構（ハーネスコア変更が必要、hookでは完全代替不可）。
- **Online Context Compact**: サブタスク完了境界でのみ圧縮要否を評価する機構（同上、hookでは
  完全代替不可。ただしPi拡張APIには`session_before_compact`という実在する介入点があり、
  「完全代替不可」は「hookで完全再現できる範囲は超える」の意で「介入点が全く無い」の意ではない）。
- **Jev / System-1判定モデル**: TypeSafe AI提供のChoice/Score/Noul判定プリミティブ。本ミッション
  では不採用（既存の決定論的ツール第一権威原則と重複、非公式MCP依存）、将来の別ミッション候補。

### Invariants this mission's decisions depend on

- 新規hookは既存の「決定論的ツール第一権威」原則（SWARM.md §2）を破らない —
  要約/圧縮ロジックはverifier判定を代替せず、あくまで観測値ハンドリングの効率化に留まる。
- Evidence-Preserving Reducer相当のhookは、引用行の完全一致検証に失敗した場合、
  または資格情報（秘密鍵等）を検出した場合、**要約を破棄し原文をそのまま返す**（安全側フォール
  バック、SoL-Pi原設計を踏襲）。
- Action Fusion / Online Context Compact はハーネスコア（ツール呼び出しループ・
  コンパクションタイミング）の変更を要するため、hookによる完全実装はしない。代わりに
  (a) CLAUDE.md/agent/rules 配下への行動規律としての明記、(b) 違反パターン検知の
  PostToolUse hook（警告のみ、非ブロッキング）の2点に限定する。
- ObservationPack・Evidence-Preserving Reducer相当の**実機能hook**は
  `agent/hooks/pi/` にのみ実装する（SoL-Pi自体がPi=earendil-works/piの公開拡張APIのみで
  構築されており、既存の `agent/hooks/pi/extensions/` と設計思想が一致するため）。Claude/AGY側は
  同等のhookコードを新規実装せず、SKILL.md/rules文書内の参照パターンとして記述するに留める。
- `agent/hooks/pi/`・`agent/harnesses/pi/extensions/`・`agent/skills/*/*.md`・
  `agent/SWARM_REFERENCES.md`・`agent/agents/*` は実行時hook(`swarm-write-scope-gate.sh`)による
  Tier Bガバナンス保護対象であり、`/swarm-evolve`のDrafter→Checker→人間承認→grant発行フローを
  経ずに直接Write/Editできない（2026-09-23実装時に実測確認）。`agent/rules/*`・リポジトリルート
  直下の`CLAUDE.md`はこの保護対象に**含まれない**。
- **許可される依存方向**: 新規hookは `agent/hooks/pi/` 配下に追加し、既存の
  `agent/scripts/hooks/rule_engine.py` / `decide.py` 委譲構造とは独立したPi extension固有の
  実装とする（既存shimの改変はしない、impact-A相当の新規ファイル追加を優先）。
- **エラー処理規約**: 新規hookは失敗時に処理をブロックしない（非ブロッキング、警告/フォール
  バックのみ）。既存の `swarm-post-edit-lint.sh` 等の exit 2 ブロッキング契約とは別枠。
- **Graft パッケージ名**: GitHub本体は`trailhq/Graft`へ組織移管済みだが、npmパッケージ名
  `@nanonets/graft`自体は現行（2026-09-23に`npm view`で確認）。CLAUDE.mdには再現可能な検証コマンド
  を明記し、スナップショット事実（発行時刻等）は書かない方針とする。

### 検討された選択肢と決定根拠

- **Jev/TypeSafe AI System-1層統合**: [不採用/別ミッション化] 実在・有用性は確認できたが
  (1) 非公式MCP依存、(2) 新規外部ベンダー依存、(3) 既存Checker(Opus)+決定論的ツール第一権威
  との設計原則重複、という3リスクを抱える。ユーザーは「本格統合」を志向するが、その本格統合こそが
  swarm-loop/swarm-graph/hooks全体に及ぶimpact-C全面改修であるため、**本ミッションでは実装せず、
  人間が別途 `/swarm-architect`（フル設計モード）を招集する新規ミッションとして切り出す**。
  本ミッションでは参考文献として `SWARM_REFERENCES.md` に記録するのみ（swarm-evolve draft経由）。
- **context-mode（ツール出力サンドボックス化）**: [不採用、ObservationPack方式を採用]
  目的は同じ（巨大出力のコンテキスト肥大化防止）だが、新規外部依存(SQLite+FTS5)を要する
  context-modeより、SoL-Piの実証済みObservationPack方式を採用。理由: 既存
  `agent/hooks/pi/extensions/` の「コア無改変・公開拡張APIのみ」という既存パターンと完全一致し、
  新規ライブラリ依存が不要。
- **codebase-memory-mcp**: [不採用] 既存の `@nanonets/graft`（trailhq/Graft）と機能的に重複。
  2026-09-18の `codegraph-tooling-consolidation` ミッション（上記セクション参照）でgraphify退役・
  graft一本化を既に決定済みであり、屋上屋を架す判断は既存決定と矛盾する。
- **Ruflo / Orca / agency-agents / OmniRoute / Paseo（マルチエージェント基盤）**: [不採用]
  実在は確認したが、LiteLLM（正当な有機成長51.5 stars/日）との比較でagency-agents(447/日)・
  orca(400/日)・OmniRoute(313/日)が異常成長を示し、star水増し/信憑性演出が疑われる
  （確信度: 中〜高）。既存swarm-loop/swarm-graphのMaker/Checker分離・verifier独立性に相当する
  設計原則を欠く。`ai-boost/awesome-harness-engineering`のみ参考リンクとして記録。
- **anthropics/skills frontend-design / mcp-builder**: [両方採用、swarm-evolve draft経由]
  実在確認済み・現行スキル体系との重複なし。frontend-design は将来のフロントエンド作業に備えた
  先行投資、mcp-builder は既存 `mcp-ecosystem-audit`（棚卸し専用）が埋めていない「新規MCPサーバー
  構築」のギャップを埋める。

### 既知の制約と非目標

- **非目標**: Jev/System-1判定層の実装（別ミッション）、context-modeの導入、codebase-memory-mcp
  の導入、Ruflo/Orca等マルチエージェント基盤の採用。
- **非目標**: vald リポジトリ側の変更（本ミッションはdotfilesの `agent/` 配下のみ）。
- **非目標**: Antigravityのグローバル配線変更（既存の意図的な対象外事項、CLAUDE.md参照）。
- **制約**: 新規hookはすべて非ブロッキング（既存のexit 2強制契約とは独立）。
- **制約**: 予算 task_max=5 / mission_max=20（swarm-meta M1 SELECTのharness-plan.jsonに準拠）。
- **本ミッションで実際に直接実装した範囲**: リポジトリルート`CLAUDE.md`への2件の追記（Action
  Fusion規律・Graftパッケージprovenance注記）のみ。SoL-Pi hooks 3件・スキル追加2件・
  SWARM_REFERENCES.md更新1件は `/swarm-evolve` draft
  （`~/.claude/session-data/swarm/evolve-proposals/2026-09-23-agent-pdf-deepresearch-draft.md`）
  として人間承認待ち。

## ai-env-deepresearch-overhaul (2026-09-24) — fix_references.md 再DeepResearch + 案A/B/C/D 全実施

前日ミッション（上記 agent-pdf-deepresearch-env-overhaul）と同一ソースを本日時点で一次再検証し、Grilling
設計面談 Q1〜Q9 で合意した決定事項。**前日ミッションの「Jev 不採用」「Claude 側は hook で実装しない」は本節で
明示的に覆す**（理由は下記「前提の変化」）。

### 前提の変化（一次確認済み）

- Claude Code `PostToolUse` の `updatedToolOutput` は全ツールで出力を置換可能（code.claude.com/docs/en/hooks
  「Prefer updatedToolOutput, which works for all tools」、値は tool の output shape と一致必須・不一致は無視され
  原文が使われる、Bash の shape = `{stdout, stderr, interrupted, isImage}`）。Claude Code 2.1.281 で確認。
- 30000 文字超の Bash 出力は Claude Code がネイティブにファイル退避＋プレビュー（`BASH_MAX_OUTPUT_LENGTH` 既定
  30000）＝ ObservationPack 相当は Claude 側ネイティブ。Reducer の対象帯は 4KiB〜30000 文字。
- 実測（直近 61 transcript、Bash 3026 回）: test/build 系で 4KiB 超は 58 回中 1 回（既存 RTK が圧縮済みと推定）。
  **Reducer の効果は現時点の実測では小さい** — 採用はユーザー判断（Q1「良いものは採用」）であり、効果の過大表明をしない。
- Jev 公式 API: `POST https://api.typesafe.ai/v1/systemone`、`Authorization: Bearer <key>`、body
  `{state, model: "jev-latest", questions: {<name>: {type: noul|choice|score, instructions, criteria?}}}`、
  response `{model, answers: {<name>: {type, noul|choice|score, confidence?}}, usage}`、エラー 422/429/529
  （docs.typesafe.ai/api.md を 2026-09-24 に取得、ミッション state-dir `jev-api-reference.md` に保存）。

### Terms

- **Jev guardrail**: 共有 hook 判定（`agent/scripts/hooks/decide.py`/`rule_engine.py`、claude/agy/pi の shim が
  委譲）の決定論判定の**後段**で動く Noul 判定層。
- **Jev tier advisor**: swarm-implement 複雑度ガード（trivial/simple/standard/complex）への Choice 判定補助。
- **Claude evidence reducer**: PostToolUse(Bash) で test/build 系 4KiB〜30000 文字の出力を、原文ファイル保存＋
  重要行（Jev Score で順位付け、原文と完全一致する行のみ）＋終了状態に置換する hook。
- **jev client**: 公式 API を直接叩く自前の薄いクライアント（第三者 MCP `itsmostafa/typesafe-mcp` は使わない）。

### Invariants（Q2〜Q9 の合意）

- **I-1 (Q2)** Jev はガードレール（PreToolUse）と Tier ルーティングの両方に組み込む。第三者 MCP は不採用。
- **I-2 (Q3/Q4) ガードレール権限は双方向**: Jev は決定論の `allow` を `ask`/`deny` に強化でき、決定論の `ask` を
  `allow` に緩和できる。**ただし決定論の `deny`（security-gate・Vald Law・write-scope 等）は hard floor で
  緩和不可**（Q4 の選択肢文面「ask を allow に緩める」の範囲に限定）。緩和は prompt injection 耐性を下げる
  既知のトレードオフとしてユーザーが受容済み。
- **I-3 障害時は決定論結果そのまま**: キー無し（`TYPESAFE_API_KEY` 未設定）・タイムアウト・HTTP エラー
  （422/429/529/ネットワーク）・レスポンス schema 不一致のいずれでも Jev 層は no-op（fail-to-deterministic）。
  hook 全体のレイテンシ予算を超えない短いタイムアウトを持つ。
- **I-4 (Q5) Tier 判定は「高い方を採用」**: 決定論ガードと Jev Choice が食い違えば高い複雑度を採る。Jev は
  Tier を下げない。Fable/Max スポット予算（budget-guard.sh --fable）を迂回しない。
- **I-5 (Q6) Reducer は Jev Score で行を順位付け**、返す行は原文と完全一致する行のみ（生成テキストを混ぜない）。
  キー無し・障害時は決定論抽出（エラー/失敗テスト/サマリー行＋先頭末尾）へフォールバック。原文は常にファイル
  保存しパスを提示。
- **I-6 外部送信前の秘密検出**: Jev へ state を送る全経路（ガードレール・Reducer）は送信前に秘密情報
  （鍵・トークン・PEM・パスワード代入等）を検出し、検出時は**送信しない**（ガードレールは決定論結果のまま、
  Reducer は原文をそのまま返す）。
- **I-7 (Q7)** `omitClaudeMd: true` はレビュー系 10 体（8 `*-adversarial-reviewer` + `code-reviewer` +
  `security-audit`）のみ。各本文に横断ルール（verify-before-assert・impact-scope・SWARM.md §2 diff-supply）の
  参照行を追加し必要時 Read させる。
- **I-8 (Q8)** Jev の検証はローカルのモック HTTP サーバーで全分岐を決定論テスト。実 API の live 検証は
  「未実施」と GATE で明示し、キー設定後の実行手順を残す。
- **I-9 (Q9)** Tier B 保護ファイルの変更は Maker が swarm-evolve draft として起案 → 独立 Checker →
  **全件を一括で人間に提示** → 承認分のみ grant 発行・適用 → 実機テスト → Phase 4.5。
- **I-10** 既存の決定論的ツール第一権威（SWARM.md §2）は Checker/Reviewer 判定に関して不変。Jev は PreToolUse の
  許可判定と Tier 選択に限定し、検証（Checker/hook の lint/test 結果）を上書きしない。

### 責務境界

- 依存方向: `decide.py`/Reducer hook/Tier advisor → jev client（`agent/scripts/jev/`。判定に効く本番モジュールは Tier B、テストは Tier A — I-15）→ 公式 API。
  jev client は hook 側を import しない。
- ガードレールは共有 `decide.py` に実装するため claude/agy/pi 3 ハーネスへ同時に効く。Reducer は Claude の
  `updatedToolOutput` 前提のため Claude のみ（Pi 側は前日 draft の扱いに従う）。

### 検討された選択肢

- 案A（既存基盤修復: dev.Dockerfile mount・graft 導入・sync-verify worktree 対応・チェッカー統一・graphify 残骸・
  CLAUDE.md 圧縮・研究結論記録・リファクタリング）[Selected]
- 案B（Claude reducer）[Selected, Q6 で Jev 行ランク方式]
- 案C（Jev）[Selected, Q2〜Q5] — 前日の不採用判断を覆す。自前クライアント・fail-to-deterministic・秘密送信禁止で
  リスクを抑える。
- 案D（omitClaudeMd）[Selected, Q7 レビュー系 10 体]
- 第三者 typesafe-mcp / context-mode / codebase-memory-mcp / Ruflo・Orca 等: 不採用（前日判断を維持）。

### 既知の制約と非目標

- 実 API キー未保有のため Jev の live 挙動・レイテンシは未測定（I-8）。
- docker イメージの実ビルドは本コンテナで未実施の可能性あり（`FROM kpango/tools:nightly` の pull が必要）。
- 非目標: vald リポジトリの変更、Antigravity のグローバル配線変更、第三者 MCP の導入。

### 追補（Q10、Laya 採用 — 2026-09-24 同日）

ユーザー追加依頼の Laya DeepResearch と実機計測（`@fix_plan.md`「Laya DeepResearch」節）を受け、Jev のバックエンドを
**Laya（convaiinnovations/laya、Apache-2.0、自己ホスト）へ置換**する。I-1〜I-10 の「Jev」は以降「System-1 判定バックエンド
（既定 Laya）」と読み替える。

- **I-11 バックエンド**: `laya-serve` は Jev と同一ワイヤプロトコル（`POST /v1/systemone`）を実装しているため、jev client は
  そのまま使い、endpoint をループバックの Laya に向ける（ループバック endpoint ではキーは任意）。第三者の公式 Jev API は
  既定で使わない。
- **I-12 配備**: 既存の ollama サイドカー前例（`dockers/ollama.Dockerfile` + `zsh/20-docker.zsh` の devrun/devkill）に倣い、
  モデルを焼き込んだ `laya` サイドカーコンテナとして dev コンテナと並べて起動する。`LAYA_HOST=127.0.0.1` を必須とし
  （laya-serve の既定 bind は 0.0.0.0）、`--network=host`、GPU は CDI（`nvidia.com/gpu`）で渡す。GPU が無い環境では CPU で
  動作する（実測 p50 160ms）。
- **I-13 権限は較正ゲートで自動拡大（Q10）**: Q3〜Q6 の全権限（双方向・単独 deny・Tier は高い方を採用・行ランク）は機能として
  実装する。ただし各権限は、コーディング領域の held-out 較正データで測った指標が閾値を満たしたものだけが有効になり、満たさない
  ものは縮小した権限で動く。
  | 権限                                                                                                                       | 有効化の条件（held-out）                                           | 条件を満たさないときの動作        |
  | -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ | --------------------------------- |
  | guard: allow→ask（強化）                                                                                                   | AUROC ≥ 0.90                                                       | 無効（決定論の結果のまま）        |
  | guard: 単独 deny                                                                                                           | deny 閾値以上に安全コマンドが 0 件、かつ危険コマンドの再現率 ≥ 0.5 | 無効（強化は ask まで）           |
  | guard: ask→allow（緩和）                                                                                                   | 緩和閾値未満に危険コマンドが 0 件（見逃し 0）                      | 無効（緩和しない）                |
  | tier: 高い方を採用                                                                                                         | 正解率 ≥ 0.70、かつ過大判定率 ≤ 25%                                | 記録のみ（判定には使わない）      |
  | reducer: 行ランク                                                                                                          | critical 行の再現率が決定論抽出以上                                | 決定論抽出のみ（Laya は使わない） |
  | 決定論 `deny` の hard floor（I-2）と fail-to-deterministic（I-3）はどの状態でも不変。較正結果はモデルの revision を        |
  | 固定したうえで JSON に保存し、hook はそれを読み取る（ファイルが無い／revision が一致しない場合は全権限を縮小側で動かす）。 |
- 実測の根拠: ゼロショットでは guard の AUROC は 0.958 だが、閾値 0.5 では危険コマンド 20 件中 9 件を見逃した。tier は情報を
  持たず、reducer は決定論抽出に劣った（74 件の小標本）。

### 追補 2（Q11・T4 方針、2026-09-24 同日）

- **I-6 の再定義（Q11）**: 既定では System-1 クライアントは**ループバック（ローカルの Laya）にしか送信しない**。データがマシンの
  外に出ないため、漏洩リスクを構造的に排除する。公式 Jev API などループバック以外への送信は `JEV_ALLOW_REMOTE=1`（1/true/yes）を
  明示したときだけ許可し、その経路でのみ送信前の秘密情報検出を行う。検出は**ベストエフォートで網羅は保証しない**（正規表現の
  ブラックリストでは原理的に保証できないことが 3 試行で実証された）。ループバック宛てでは秘密情報の検出によって送信を止めない。
  I-3（fail-to-deterministic）とそれ以外の防御（許可リスト・プロキシ無効化・リダイレクト拒否・全体の期限）は不変。
- **sync-verify.sh の worktree 対応（T4、人間判断）**: git のメタデータだけでは「本物のメインのチェックアウト」を判別できない構成が
  あり（separate-git-dir の保存先が `.git` という名前の場合など）、自動推定は 6 試行にわたって推測の穴が尽きなかった（最後は
  `GIT_INDEX_FILE` で誤配線が PASS になった）。そのため**自動推定はしない**。live 配線の照合基準は `SYNC_VERIFY_LIVE_ROOT` で
  明示し、未指定なら従来どおりスクリプト自身の root を使う。linked worktree 内で未指定のまま実行された場合は、指定方法を案内する
  だけにする（案内のための判定は結果に影響させない）。不変条件: **誤配線を PASS にしない**ことを、推測より優先する。

#### 追補 3（2026-09-24、人間判断: T9 は 3 ハーネスすべてに効かせる）

- **I-14 ハーネス差の吸収**: T9 の System-1 ガードレールは claude/agy/pi の 3 ハーネスすべてで有効にする。前提として、
  各 shim は決定論の判定を異なる意味で受け取る（pi の `security-gate.ts` は `all_matches` だけを走査し、トップレベルの
  `decision` を読まない。agy の `security-gate.sh` は `ask` と `block` をどちらも deny にする）。そのため:
  - 各 shim は decide.py への入力で `harness`（`claude`/`agy`/`pi`）を明示的に渡す。未指定なら System-1 の後段は適用しない（安全側）。
  - pi の shim は、System-1 による調整をトップレベルの `decision` で受け取り、反映する。
  - agy には ask が無いため、guard_relax（ask→allow）は agy では**常に無効**（実質的に deny→allow になるため）。
    guard_strengthen は agy では deny として効く（厳格化方向なので許容）。
- 決定論の deny（block）が絶対の下限であることは、どのハーネスでも変わらない（I-2）。

#### 追補 4（2026-09-24、ミッション作業ファイル `@fix_plan.md` から転記した学び。`@fix_plan.md` は git 管理外のため、恒久的に参照される事実だけをここに残す）

- **L-1 revision の機械検査（T17）**: `laya-calibration.json` の revision と `dockers/laya.Dockerfile` の `LAYA_HF_REVISION` の一致は、
  `agent/scripts/jev/calibration/test_calibration.py` のテストで機械検査する。
- **L-2 安全側の下限に precision 要件を課さない（T17）**: 決定論 regex に「成功サマリ・パスを拾わない」まで要求した結果、除外を足すたびに
  本物の失敗行を隠す回帰が起きた。一致行を常に保持する用途では、誤検知のコストは圧縮率だけで、見逃しは致命的になる。
- **L-3 Checker の判定範囲の凍結（T17）**: 独立 Checker に網羅性の要件を渡すと、有限集合に対して無限後退した。判定範囲を「確定テスト表への
  後退＋文書が裏付け範囲を超えないこと」に凍結すると収束した。
- **L-4 star 数を採否の根拠にしない（Secretary Report）**: 候補の一部で star 数と実コミット活動の乖離が指摘された。ただし、fake star と
  結論する根拠はいずれも二次情報源（medium.com と peerlist.io の記事）のみで、一次資料での裏取りはしていない。
- **L-5 omitClaudeMd の実測（T12、2026-09-24、Claude Code 2.1.281、1 回のみ）**: `omitClaudeMd: true` のサブエージェントでは、CLAUDE.md
  （プロジェクト・ユーザー）と `paths:` を持たないルール（プロジェクト・ユーザー）が注入されなかった。`paths:` を持つルールは、対象ファイルを
  Read したときに `nested_memory` として注入された。判定はサブエージェントのトランスクリプトをマーカー文字列で grep して行った。

#### 追補 5（2026-09-24、T18: 上記の実測値への出典追記）

既存の行番号参照（SWARM_REFERENCES.md が引用する CONTEXT.md:298-300, 381, 400-409, 424-434）を動かさないため、
出典は追記のみとし本節末尾に置く。元データはいずれも `~/.claude/session-data/swarm/missions/ai-env-deepresearch-overhaul/`
配下（`bench.py` の出力、git 管理外 — このリポジトリの外）。

- **I-12「実測 p50 160ms」（382行目。381行目は SWARM_REFERENCES.md が引用する LAYA_HOST/bind の行で別内容）の出典**: `res-cpu-english.json` の `guard.p50_ms` = 160.0（`guard.p95_ms` = 180.7）。
- **「ゼロショットでは guard の AUROC は 0.958 だが、閾値 0.5 では危険コマンド 20 件中 9 件を見逃した…（74 件の小標本）」
  （395-396行目）の出典**: 同ファイルの `guard.samples`（危険コマンド20件・安全コマンド20件、各要素 `[コマンド文字列, 危険か, スコア]`）
  から本タスクで AUROC（Mann-Whitney U 由来のランク統計、同点は0.5扱い）を再計算した値 0.9575（四捨五入で0.958）、スコア<0.5の
  危険コマンドは 9/20 件。74 件は同ファイルの `guard.n`(40) + `tier.n`(16) + `reducer.n`(18) の合計。同条件の `res-cuda-english.json`
  は同一の値（AUROC 0.9575・見逃し9件）、`res-cuda-td.json` は異なる値（AUROC 0.9825・見逃し17件）を記録しており、本文が引く数値は
  cpu-english 実行分と一致する。

#### 追補 6（2026-09-25、人間判断: G4.5 セキュリティ HIGH への対応 — 判定に効く本番モジュールを Tier B で保護）

- **I-15 System-1 判定経路の保護範囲**: Tier B の `decide.py` は security_shell の判定を `agent/scripts/jev/guard_advisor.py` に委ねるため、
  委ね先とその判定を左右するファイルも Tier B（write-scope）で保護する。対象は次の 9 件:
  `agent/scripts/jev/{guard_advisor,tier_advisor,evidence_reducer,revision_check,jev_client,questions}.py`、
  `agent/scripts/jev/calibration/{calibrate.py,laya-calibration.json}`、`dockers/laya.Dockerfile`。
  テスト（`test_*.py`・`test_support_*.py`・`*.ts`）、較正データ（`calibration/*.jsonl`）、`calibration/README.md` は Tier A のまま。
  保護パターンは `agent/write-scope-rules.json`・`agent/skills/swarm-implement/scripts/write-scope-lib.sh`・
  `agent/skills/swarm-meta/scripts/harness-lint.sh` の 3 か所で一致させ、`agent/scripts/test-write-scope-parity.sh` で期待値ベースに固定する。
  以後この 9 件の変更は I-9 の承認フロー（draft → 独立 Checker → 人間の承認 → grant）を通す。

## ai-env-followup-refactor (2026-09-25) — ai-env-deepresearch-overhaul の非ブロッキング指摘 6 件の消化

対象は `~/.claude/session-data/swarm/missions/ai-env-deepresearch-overhaul/followup-refactor.md` の 6 候補（C1〜C6）に限る。新規監査はしない。

### 決定事項（grill-interview 2026-09-25）

- **F-1（C3、人間判断「OS ごとに補助関数」）**: `zsh/20-docker.zsh` のサイドカー起動は OS 別の補助関数へ寄せる。
  macOS は ollama/laya の 2 ブロックを `_devrun_mac_sidecar <name> <image> <start-note>` 1 本に丸ごと統合する（起動済み確認 → 停止コンテナ削除 → pull → `container run -d`、失敗は WARNING で継続）。
  Linux は `_devrun_docker_sidecar_prepare <name> <image>` に「起動済み確認・停止コンテナ削除・pull」だけを寄せ、戻り値 0 = 起動が必要 / 1 = 既に起動済み とする。
  `docker run` の引数（ollama の `$gpu_option`、laya の CDI GPU と CPU 再試行、`-e LAYA_*`）は各呼び出し箇所に残す。
  表示メッセージ・挙動（コマンド列・失敗時の継続）は変えない。
- **F-2（C4、人間判断「許可文字で検査する」）**: `agent/hooks/claude/{post-write,session-end,session-start,post-tool-failure}.sh` は session_id を
  hook 入力 JSON の `.session_id` から読む（未文書の `CLAUDE_SESSION_ID` は使わない）。値が `^[A-Za-z0-9._-]+$` に一致しない、または `.`/`..` の場合は `unknown` にする
  （evidence_reducer.py の `_sanitize_session_id` と同じ許可文字）。ログのファイル名に使う値なので入力元を信頼しない。
  stdin を読んでいない hook（session-start.sh）には読み取りを加え、INPUT を後段で読んでいる hook（session-end.sh）は読み取りを SESSION_ID の前へ移す（stdin は 1 回しか読めない）。
  jq が無い・JSON が壊れている場合も `unknown` で継続する（fail-open、hook を止めない）。
  既知の例外（2026-09-25 Checker 実測）: stdin に生の NUL バイトが含まれると、bash の `$(cat)` が jq に渡す前にそれを捨てるため、
  jq には NUL を除いた JSON が見える（例: `"ab<NUL>cd"` → `abcd`）。採用されるのは許可文字だけなので保存先の外には出ない。
  Claude Code は JSON 内の NUL を `\u0000` とエスケープして渡すため（それは jq 側で `unknown` になる）、実運用で生の NUL は届かない想定として受け入れる。
- **F-3（C1）**: `_RevisionFixtureMixin` は `agent/scripts/jev/test_support_revision_fixture.py` に 1 本だけ置き、3 テスト（guard / tier / evidence_reducer）はそこから import する。
  属性名は子クラスの `self.tmpdir` と衝突しない `dockerfile_dir` に統一し、mixin の `self.tmpdir` に依存していた箇所も合わせて書き換える。
- **F-4（C2、人間判断「C2 も改名する」）**: 4 つのモジュールプライベートな `_write_calibration` を扱う対象ごとの名前へ改名する:
  `test_tier_advisor.py` → `_write_tier_calibration`、`test_guard_advisor.py` → `_write_guard_calibration`、
  `test_evidence_reducer.py` → `_write_reducer_calibration`、`test_revision_check.py` → `_write_revision_calibration`。シグネチャ・中身は変えない（改名のみ）。
- **F-5（C5）**: `decide.py` の「PERF (measured regression, fixed here)」から裏付けの無い「measured」の主張を外し、遅延 import の理由だけを書く（コメントのみ、ロジック不変）。
- **F-6（C6）**: `evidence-reducer.sh` の session_id コメントは「値の検査は evidence_reducer.py の `_sanitize_session_id`（fullmatch）が行う」と実際の責任の所在を書く（コメントのみ）。
- C4・C5・C6 は Tier B（I-9 の承認フロー: draft → 独立 Checker → 人間の承認 → write-scope-grant）。C1・C2・C3 は Tier A。
- **F-7（Phase 4.5 perf-simd 指摘、人間判断「jq の呼び出しを 1 回にまとめる」）— 不採用になった案。下の F-7 結論を参照**: 案は、F-2 の 4 hook が同じ stdin JSON を jq で複数回解析しないようにするもの。
  session_id の検査は 1 行の変数 `_SID_JQ='def _sid: …;'` として 4 hook に同じ文字列で置き、各 hook は 1 回の `jq -rs` でそれを使う
  （post-write.sh は session_id と file_path、post-tool-failure.sh は session_id・tool_name・error、session-start/session-end は session_id のみ）。
  検査の内容（F-2 の許可文字・非文字列の拒否・`.`/`..` の拒否）と、取り出す各値の従来の意味は変えない。
  案では `agent/scripts/test-hook-session-id.sh` を `_SID_JQ=` 行に追従させる予定だった（採用されなかったため、実際のテストは T3 の `SESSION_ID=$(printf …)` 行を検査している）。
  参考値（オーケストレーターの手元計測、jq 1.8.1、計測スクリプトは残していない）: session_id 抽出の jq 1 回分は小さい入力で約 2.4ms、2MB の入力で約 15.8ms。post-write.sh と post-tool-failure.sh は settings.json で async=True。
- **F-7 改訂（2026-09-25、T5 試行 4 の Checker 結果を受けた人間判断「一時ファイルなしで再設計」）— これも不採用（F-7 結論）**: 一時ファイル（mktemp）と EXIT trap は使わない。
  理由（Checker 実測）: kill のタイミングにより一時ファイルが残る、EXIT trap が長い bash 展開の間 SIGTERM の処理を遅らせる、fallback 時に解析が 1 回増える。
  jq は 1 回だけ呼び、出力は `$()` で受ける（シェル変数への代入は `@sh` で安全にクォートした代入文を `eval` するか、最後の 1 値だけを生のまま出力して `$()` の末尾改行除去に任せる）。
  受け入れ条件: 記録する値・lint に渡す値・exit code・dunstify の文字列は旧 hook（4077e288）とあらゆる入力で同一。
  性能は旧 hook より悪化しないこと。例外として、末尾改行の除去を jq 内で行う値に極端に長い改行の連続がある場合だけは旧より遅くなりうる（選択肢の提示時に人間へ説明済み）。
- **F-7 結論（2026-09-26、人間判断「T5 を止めて締め、Go 化は新ミッション」）**: F-7（jq の呼び出しを 1 回にまとめる）は**不採用**。hook は T3（500bbab5）の値ごとの jq 呼び出しのまま。
  10 回の試行で、挙動の完全一致は達成できたが、「どの入力でも旧 hook より遅くならない」は bash の制約で満たせなかった。
  手元の計測で確認した制約（参考値、計測スクリプトは残していない）: bash は大きな変数を展開するたびに値全体をコピーする（2MB で 1 回約 6.6ms / UTF-8、約 3.7ms / C。20 バイトの切り出しでも同じ）。
  1 回の jq で複数の値を受け取ると、bash 側での分割が必ず発生し、旧 hook が `$()` で暗黙に行っていた処理（末尾改行の除去、NUL の除去、parse エラー時の部分出力）を自前で再現する必要がある。
  試行ごとに見つかった問題: `$()` の末尾改行の扱い、`sub("\n+$")` の二乗時間（対策は `(?<!\n)\n+$`）、一時ファイルと EXIT trap（kill 時の残留・SIGTERM の遅延）、スクリプト全体の `LC_ALL=C` による `${ERROR:0:200}` の文字数→バイト数化、bash 側分割のコピーコスト、多数の連結 JSON での jq 内部処理のコスト。
  最終試行（10 回目）で残った差: post-write の `{bad` +6.5ms、post-tool-failure の 20 万件連結 +300ms など（いずれも壊れた JSON や大量の連結 JSON で、通常の hook 入力の形ではない）。
- **同期 hook の実測（2026-09-26、Go 化ミッションの目安）**: 1 回あたりの中央値（10 回、HOME は一時ディレクトリ）。計測スクリプトは残していない参考値で、Go 化ミッションの P2 では計測スクリプトをリポジトリに置いて測り直し、それを比較基準にする。
  rtk-rewrite.sh 68.5ms、security-gate.sh 62.7ms、evidence-reducer.sh 87.6ms、write-security-gate.sh 57.4ms、swarm-write-scope-gate.sh 24.5ms、user-prompt-submit.sh 48.4ms。
  起動コスト（10 回平均）: python3 -S 約 8.5ms、jq 約 3.4ms、rtk 約 2.8ms。security-gate / write-security-gate は jq 3〜4 回と decide.py、evidence-reducer は jq 2 回と python3 を起動する。
  Go 化の制約として把握済みの点: pi の拡張は pi が読み込む TypeScript のため、TypeScript は Go バイナリを呼ぶ薄い層として残る。配布は `tmux/go/install`（`~/.zcache` に go install、Go が無い環境では既存スクリプトを使う）が前例。

## ai-cli-always-latest (2026-10-14) — claude-code 最新化と Docker/nix/AUR の鮮度維持

「最新の claude code を入れ、nix と Docker でも常に最新が入るようにする」という依頼に対する
Grilling 設計面談（`agent/rules/grill-interview.md`）の決定事項。prime-agent の導入可否は
面談の途中で追加された質問ノード。

### Terms

- **鮮度経路 (freshness path)**: claude-code のような無ピン依存が「最新」になるために通る経路。
  このリポジトリには 3 本ある — (1) Docker: `dockers/tools.Dockerfile` の `bun install -g`、
  (2) nix: `nix/modules/home/packages/shared.nix` の `claude-code` 属性 →nixpkgs→`nix/flake.lock`、
  (3) Arch ホスト: `arch/aur*.list` →`paru -Syu`。経路ごとに「古くなる原因」が違う。
- **TOOLS_REFRESH**: `Makefile.d/docker.mk` が `docker/build/tools` にだけ渡すキャッシュバスト
  トークン。値は UTC の `YYYYMMDD`。`dockers/tools.Dockerfile` の `bun install -g` レイヤと
  2 つの fetcher ステージ（agy / prime-agent）がこれを参照する。
- **agy インストーラの gzip 問題**: `https://antigravity.google/cli/install.sh` が Accept-Encoding
  を提示していないのに `Content-Encoding: gzip` 付きの gzip 本体を返すことがある。curl は自分が
  要求していないエンコーディングを展開しないため、保存ファイルが gzip 生バイトになり
  `bash install.sh` が exit 126（cannot execute binary file）で落ちる。

### Invariants this mission's decisions depend on

- **I-1 (nixpkgs は遅れの原因ではない)**: 2026-10-14 時点で nixpkgs-unstable の claude-code は
  2.1.296 で、npm の `latest` と完全に同値。遅れていたのは `nix/flake.lock`（2026-09-16 固定、
  同 rev の `manifest.zst.json` が 2.1.272）だけ。したがって nix 側の対策は
  「flake.lock を定期的に更新すること」であって「自前 derivation を書くこと」ではない。
- **I-2 (`update-actions.yaml` は flake.lock を運ばない)**: 同 workflow の PR 作成ステップが
  ステージするパスは `.github/` 配下に限定されている。`make nix/update` を足すだけでは
  flake.lock はコミットされない。
- **I-3 (schedule 以外のビルドはキャッシュを使う)**: `.github/actions/docker/action.yaml` が
  `--no-cache` を付けるのは `github.event_name == 'schedule'` のときだけ。push 起因の tools ビルドは
  キャッシュヒットし、`bun install -g` レイヤのコマンド文字列が不変なら `latest` は再解決されない。
- **I-4 (tools/merge は両アーキの成功を要求する)**: `docker-reusable.yaml` の `merge` は
  `needs: build`。片方のアーキが落ちると merge が skip され、`tools:nightly` のマニフェストは
  更新されない。2026-10-10/11/12 の 3 回の schedule 実行がこれに該当し（失敗したアーキは
  10-11 が amd64、10-12 が arm64 と交代している）、`tools:nightly` は 2026-10-09 以降
  再公開されていない。原因はいずれも Terms の gzip 問題。
- **I-5 (AUR の claude-code-bin は消滅済み)**: AUR RPC v5 で `claude-code-bin` は resultcount=0。
  現行は `claude-code` 2.1.296-1（votes=95）。`Provides`/`Replaces` が無いため自動移行されない。
- **I-6 (`arch/aur*.list` は機械生成)**: `zsh/20-os-arch.zsh` の `_backup_packages` が
  `pacman -Qqem | sort` で上書きする。ロケール依存の `sort` 順なので、手編集時は再ソートせず
  該当行だけを差し替える（Python の codepoint ソートを掛けると `swaybg-git` と
  `sway-git-wlroots-git` の順が入れ替わり、無関係な差分が出る）。コメント行は書けない
  （`paru -Syu - < aur.list` が標準入力をパッケージ名として読むため）。
- **I-7 (prime-agent は公式インストーラ以外の配布経路を持たない)**: npm（`prime-agent` および
  `@primeintellect/*` 系）・nixpkgs（`pkgs/by-name/pr/prime-agent/package.nix` が 404）・AUR
  （resultcount=0）のいずれにも存在しない。2026-10-14 確認。
- **I-8 (prime-agent は `~/.prime/agent` を触らない)**: 公式インストーラの usage に明記。
  本リポジトリの `primeagent/install` が同ディレクトリへ張る symlink と衝突しない。
  またインストーラがアンインストールする npm パッケージは `prime-agent` のみで、
  Pi（`@earendil-works/pi-coding-agent`）には影響しない。
- **I-9 (prime-agent と Pi はワイヤ互換)**: prime-agent の `AGENTS.md` が `PI_PACKAGE_DIR`・
  settings キー・provider ID を TS 製品と byte 互換に保つと明記し、セッション保存先も
  `~/.prime/agent/sessions` と同じレイアウト。`agent/harnesses/primeagent/settings.json` が
  `https://pi.dev/schemas/settings.json` を参照しているのは誤りではない。

### 責務境界と入出力規約

- **Docker の鮮度**: `docker/build/tools` のみが `TOOLS_REFRESH` を渡す。`docker/build/image` に
  置くと他 14 イメージに未使用 build-arg 警告を撒くため、`docker/build/dev` と同じ
  「専用ターゲットで追加 opts を足す」形に揃える。
- **nix の鮮度**: `update-nix-lock.yaml` が単独で負う。`nix/overlays/` には手を入れない
  （同ディレクトリの `default.nix` が自前パッケージを 2 回壊して撤去した経緯を記録している）。
- **検証ゲート**: flake.lock の直 push は `make nix/test` 全通過が前提。push 後は
  `nix.yaml`（`paths: nix/**`）のフルマトリクスが二段目として走る。

### Considered Options & Rationale

- **Q2 nix 方式**: (a) **[Selected]** nixpkgs 追従 + flake.lock 定期更新 /
  (b) 自前 overlay + versions.nix で pin を bump / (c) overlay で毎回 downloads.claude.ai 取得
  （`--impure` 必須、再現性喪失）/ (d) nix 管理から外す。I-1 より (a) で十分。
- **Q3/Q10 Docker 方式**: cache-bust ARG を導入。当初は AI CLI 11 本だけを別レイヤに分離する
  案だったが、Q10 で 19 本すべてを bust 対象とする判断になったため分離の利点が消えた。
  代わりに **pip レイヤを bun レイヤより前へ移動**し、bust されるレイヤを tools-stage の
  最後に置くことで「無関係レイヤを巻き込まない」という当初の意図だけを残した。
  ARG 名も実態に合わせて `AI_CLI_REFRESH` ではなく `TOOLS_REFRESH` とした。
- **Q5/Q6 lock 更新の形**: 専用 workflow + **main へ直 push**（PR ではない）。回帰リスクは
  `make nix/test` フルゲートを push 前に置くことで抑える。
- **Q7 頻度**: 6 時間ごと（`20 */6 * * *`）。`update-actions.yaml`(18:00 UTC) と
  `docker-matrix.yaml`(23:00 UTC) を避けて毎時 20 分にずらしてある。
- **Q11 prime-agent**: Docker に `prime-fetcher` ステージを追加（`agy-fetcher` の前例に倣う）＋
  開発コンテナへ即時導入。nix は I-7 により対象外。`agy-fetcher` が `--platform=$BUILDPLATFORM`
  なのに対し `prime-fetcher` は TARGETPLATFORM のままにしてある（インストーラ自身の
  `uname -m` 判定に正しいアーキを見せるため）。

### Constraints & Non-Goals

- **Non-Goal**: nixpkgs に無いツール（prime-agent, `@byterover/cipher`, `@google/jules`）を
  nix 経路に載せること。
- **Non-Goal**: `docker-matrix.yaml` の他の赤ジョブ（2026-10-12 実行時点で `images (rust)` 両アーキ、
  `images (go)` amd64）。`tools` は `needs` の条件が `base` の成功のみなのでこれらに阻まれない。
- **既知の制約**: 開発コンテナ内での `bun install -g` は `/usr/local/install` が root 所有のため
  sudo が要る。また `@nanonets/graft` の依存 `tree-sitter-kotlin` は Node ABI 137 向けの prebuild を
  持たず、`node-gyp` が PATH に無いとインストールが中断して graft が壊れた状態で残る。

## ci-all-green (2026-10-14) — 恒常的に赤い CI 6 件の原因切り分けと修正

`gh` でリモートの実行履歴を走査し、赤い workflow をすべて緑にするミッション。
上の `ai-cli-always-latest` と同一セッションの続きで、そこで見つけた Docker の失敗を含む。

### Terms

- **CI が見ているコード**: `origin/main`。調査時点で `origin/main` は 2026-09-23 の `752cf083`、
  ローカル `main` はその 69 コミット先 (0 behind)。**CI の赤の一部はローカルで既に直っている**
  ため、「リモートのログの原因」と「今直すべき箇所」は必ずしも一致しない。切り分けには
  `git show origin/main:<path>` と作業ツリーの比較が要る。
- **formatter 規約 (zsh)**: `make format/zsh` は `shfmt -ln bash -w` の後に
  `sed 's/ - /-/g'` と `sed 's/ + /+/g'` を全ファイルへ掛ける。この 2 つは shfmt の演算子間隔を
  打ち消すためのもので、実測では shfmt 単体が 21 ファイル中 9 ファイルを書き換え、sed がその
  うち 8 ファイルを元に戻す。コミット済みファイルはすべてこの「sed 正規化後」の形。

### Invariants this mission's decisions depend on

- **I-10 (GITHUB_TOKEN は workflow ファイルを push できない)**: GitHub は `workflow` スコープの
  無いトークンによる `.github/workflows/**` への push を拒否する。`update-actions.yaml` が
  書き換える対象は pinact・ghatm・`update/versions/{actions,tools}` のすべてが
  `.github/workflows/` 配下（`Makefile.d/update.mk:114,136,181`）なので、一部だけ切り出して
  GITHUB_TOKEN で push する逃げ道は無い。`GH_PAT` secret は未登録（登録済みは repo に
  `CLAUDE_CODE_OAUTH_TOKEN`、environment `copilot` に `DOCKERHUB_USER`/`DOCKERHUB_PASS` のみ）。
- **I-11 (`secrets` コンテキストは step の `if` で使えない)**: `jobs.<id>.steps.*.if` から
  `secrets` は参照できない。`jobs.<id>.env` からは参照できるので、`HAS_GH_PAT` のような
  job-level env に畳んでから step の `if` で見る。
- **I-12 (ahash 0.7.6 は nightly で壊れる)**: ahash 0.7.6 の build.rs はコンパイラが nightly だと
  自身の `stdsimd` feature を有効化するが、rustc はその feature を削除済み
  (`error[E0635]`)。frawk の Cargo.lock が ahash 0.7.6 を固定し `cargo install --git` が
  それを尊重するため、nightly 既定の `rust-base` 上では必ず落ちる。frawk 自体は nightly を
  要求しない — nightly 依存コードは frawk の `unstable` feature の下にあり、それは `default`
  feature 集合の一部なので `--no-default-features` で既に無効化されている。
- **I-13 (xargs の終了コード)**: `xargs` は配下コマンドが 255 で終わると自身は 124 を返す。
  `dockers/go.Dockerfile` のビルドログに出る `exit code: 124` は「timeout」ではなく
  「`go install` が失敗した」の意味。
- **I-14 (NixOS build は substitute だけでは終わらない)**: 2026-10-12 の tr で nix は
  「these 620 derivations will be built」と報告し、60 分時点で 334 個完了・3429 パス
  substitute 済み。unfree の CUDA アーカイブや NVIDIA カーネルモジュールがバイナリキャッシュに
  無いため実コンパイルが発生する。
- **I-15 (`.zwc` は CI に存在しない)**: `zsh/*.zwc`・`zfunc/*.zwc` は `.gitignore:176` の `*.zwc`
  で除外されたコンパイル生成物。ローカルで `zsh -n` を全ファイルに掛けると parse error を出すが、
  CI はクリーンチェックアウトなので無関係。検証時は `git ls-files` 経由で追跡ファイルだけを見る。

### 原因と対処の対応表

| workflow / job                      | 症状                                               | 原因                                                                                                              | 対処                                                                                    |
| ----------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| update-actions                      | 2026-10-04〜10-13 毎日 failure                     | I-10                                                                                                              | `HAS_GH_PAT` env で判定し、未登録なら warning を出して skip（登録されれば無改修で復帰） |
| docker images (rust)                | 両アーキ毎回 failure                               | I-12                                                                                                              | frawk stage を `rust-base` → `rust-stable`                                              |
| docker images (go)                  | amd64 が 10-07/10-12 に failure                    | proxy.golang.org の間欠 HTTP/2 `INTERNAL_ERROR`                                                                   | `go install` を 3 回まで線形バックオフで再試行                                          |
| docker tools                        | 10-10/11/12 failure → merge skip                   | agy インストーラの gzip（上節 Terms）                                                                             | curl に `--compressed`                                                                  |
| docker dev                          | 直近 8 回 merge skip                               | `source=pi,claude,agy` の stale bind mount                                                                        | 既に `80b3ad6b`(2026-09-24) で修正済み・未 push                                         |
| nix NixOS build                     | 4 ホストとも 60 分 timeout で cancelled            | I-14                                                                                                              | `timeout-minutes` 60 → 180                                                              |
| agent-sync-verify                   | 2026-09-23 push で failure                         | pi/AGENTS.md の末尾改行差分                                                                                       | 未 push コミットで解消済み（ローカルで 20/20 pass を確認）                              |
| (push 後に顕在化) agent-sync-verify | `test-settings-common.sh` drift                    | `305ab588`(2026-09-25) が claude `/model` を `opusplan`→`opus` に変えたが `agent/settings-common.json` が追従せず | settings-common を作業ツリーの `opus[1m]` へ追認                                        |
| (push 後に顕在化) zsh               | `make format/zsh && git diff --exit-code` が落ちる | `zsh/20-docker.zsh` のコメント散文に `+` が含まれ formatter 規約に抵触                                            | 散文を言い換え、`format/zsh` に注意書きを追加                                           |

### Constraints & Non-Goals

- **ユーザー作業が必要な残件**: `GH_PAT`（`repo` + `workflow` スコープ）の登録。手元のトークンは
  `repo` までで `workflow` を持たないため、代理登録しても同じ理由で失敗する。
- **Non-Goal**: `format/zsh` の sed をコメント非適用にする改修。既存の全 zsh ファイルが
  sed 正規化後の形でコミットされており、規約そのものの変更は影響範囲が別物。
- **前提**: 上記すべては `origin/main` へ push されて初めて CI に反映される。

## unifi-ips-docfix (2026-10-16) — UniFi Network 11 の DB 移行と IPS 実機調査の反映

- **起点**: amalance.jp/blog-unifi-03（UDM Pro IPS ルール統計記事）の実機ファクトチェック。統計値は
  実機（Network 11.0.89）とほぼ一致、「カテゴリ単位でしか切替不可」は誤り（Signature Suppression あり）。
- **決定 1**: UniFi Network ≥ 11.0.83 はアプリ DB が PostgreSQL（release notes "Migrated the application
  database to PostgreSQL"）。`unifi-api` skill の DB 直接照会手順は版分岐で記述し、旧版の mongo 手順も残す
  （未更新機器向け）。DB は読み取り専用で使い、修正は従来どおり Classic REST API 経由（DB 直書きしない）。
- **決定 2**: IPS の機構（suricata `--pcap` 受動監視 → ipset `ips`/`ips6` → FORWARD で一定時間 DROP）を
  skill に汎用知識として記載。世帯固有の有効カテゴリ・Tor 方針は auto-memory 側に置く（harness-design.md）。
- **決定 3**: UDM 本体は変更しない。Tor 遮断は人間判断で現状維持、カテゴリ削減・シグネチャ抑制は便益なしで不採用。

## login-startup-optimize (2026-10-21) — tty1 ログイン → sway / zsh / tmux 起動チェーンの整理

起点: 同日朝、`libliftoff` の orphan 削除で sway が即死し、tty1 ログインが即ログアウトするループが発生した。
kpango は `~/.zprofile` の `exec sway`、root(bash) は `/etc/profile.d/sway.sh` の `exec sway` が原因
（`ed1f382` の暫定修正は後者のみに効いていた）。**zshenv:9 の `unsetopt GLOBAL_RCS` により kpango の zsh
ログインは /etc/zsh/zprofile・/etc/profile・profile.d を読まない**（実測 `zsh -l -c` で globalrcs=off）。
本ミッションはその起動チェーン全体を計測に基づき一本化・高速化する。決定は grill-interview Q1〜Q10。

### Terms

- **launcher**: tty ログインシェルから sway を起動する唯一の箇所（tty1 のログイン経路が対象で OS 非依存。
  NixOS ホスト `tr` の greetd 起動はこの経路を通らない）。本ミッション後は repo の `zprofile`
  （`~/.zprofile`、共通 `DOTFILES_MAP`）が `arch/sway.sh` を呼ぶ。`/etc/profile.d/sway.sh` は I1 の条件で撤去
- **session env**: sway プロセスとその子（systemd user / D-Bus activation 経由のサービス含む）が見る環境変数
- **host tmux server**: `/run/user/$UID/tmux-main.sock` 上の単一サーバー。Arch（install.mk 配備）では起動役は
  `tmux.service`。Nix ホストには同 unit が無く、01-tmux.zsh の直接 `new-session -d` か端末の `new-session -A`
  が作る（docker 分岐の `/tmp/tmux-main.sock` はコンテナ内用で別物）

### Invariants this mission's decisions depend on

- **I1 (Q1) launcher は 1 箇所（tty ログイン経路）**: tty ログインから sway を起動するのは `~/.zprofile` だけ。gate は対話シェル・tty1・
  `WAYLAND_DISPLAY` 未設定・非 root（EUID≠0）・`sway` が存在。root（tty1 からの `su -`/`sudo -i` 含む）・
  他 tty・SSH のログインでは sway を起動しない（system-wide profile.d を使わない）。既配備の
  `/etc/profile.d/sway.sh` は arch install prep が symlink の場合、または旧版のヘッダにだけある印
  （`system-wide sway launcher`）を含む通常ファイル（`MODE=copy` 配備の残骸）の場合に削除し、加えて `arch/sway.sh`
  先頭の POSIX ガード（zprofile が立てる `_SWAY_LAUNCH`）で zprofile 以外からの source を no-op にする。
  zprofile は自身の実パスから `arch/sway.sh` を解決し、見つからなければ（`MODE=copy` で `~/.zprofile` が実ファイル）
  zshrc の dotfiles 候補パスから fork する `ghq root` を除いたもの（`$DOTFILES_DIR`、`~/go/src/…`、`~/ghq/…`、
  `~/dotfiles`）を探す。`dotfiles/install` は手書きの `~/.zprofile` を退避せず置き換える（`.zshrc`/`.zshenv` と
  同じ既存挙動）。MAC_PREP は home-manager に場所を空けるため 3 ファイルとも無条件に削除する
- **I2 (Q2) env import は 1 回**: 値の持ち主は `arch/sway.sh`（sway に export）。systemd/D-Bus への
  反映は sway.conf autostart の 1 exec（`sh -c 'env -u … dbus-update-activation-environment --systemd --all;
  systemctl --user start --no-block sway-session.target'`）のみ。sway の exec は非同期なので import と
  target 起動は同一 exec 内で順序付けし、`;` で import 失敗時も target は起動する。sway 起動前の import と
  キー列挙による個別 import は持たない。NVIDIA 用の `LIBVA_DRIVER_NAME`/`__GL_*` は
  `systemd/environment.d/xdg.conf` から `arch/sway.sh` の NVIDIA 分岐へ移設（sway 外のセッションには付かない）。
  greetd 起動の NixOS では `nix/modules/nixos/desktop/wayland.nix` の NVIDIA ブロックが同じ値を持つ
- **I3 (Q3) GPU 判定は fork しない**: `/sys/module/nvidia_drm` あり・`/sys/module/nouveau` なし・
  `/dev/nvidiactl` あり、のファイル判定のみ。nvidia-smi / lsmod / lspci は呼ばない
- **I4 (Q4) host tmux は 1 サーバー 1 ソケット（Linux/sway ホスト）**: sway の `$term`/`$xterm`、
  `arch/hyprland.lua`、`zfunc/_gen_env` の `TERMCMD`、SSH/対話シェル（`zsh/01-tmux.zsh`）は
  `$XDG_RUNTIME_DIR/tmux-main.sock`（= tmux.service の `/run/user/%U/tmux-main.sock`）の同一セッション
  `$USER@#H`（= `%u@%H`）へ `new-session -A` で接続する。`-d` は付けないので他クライアント（SSH 等）を
  切断しない。`$term` は `$SHELL -c` を経由せず tmux を直接実行する。darwin は対象外: `_gen_env` の
  `TERMCMD` は darwin にも焼かれるが、zshenv の `XDG_RUNTIME_DIR` 既定（`~/.local/run`）と 01-tmux.zsh の
  ソケット選択（`/run/user/$UID` か `~/.tmux/`）が一致しない既知の差異として残す
- **I5 (Q5) sway 失敗時は通常の対話シェル**: 非 0 終了ならログインシェルに留まり、以降は通常どおり
  zshrc → tmux 自動 attach まで進む（特別な抑止フラグは設けない — 人間判断）。正常終了ならログアウト
- **I6 (Q6) kanshi の起動役は kanshi.service のみ**: sway.conf の `exec kanshi` は持たない。unit は
  `ConditionEnvironment=WAYLAND_DISPLAY` で sway 外（SSH からの make 等）では起動しない。
  install.mk は `enable` のみ（`--now` しない）。`systemd/user/sway-session.target` も install.mk で配備
  （従来ホストには手置きの同一内容ファイルのみ）。Nix は `nix/modules/home/services.nix` に kanshi unit
  （`${pkgs.kanshi}`）と sway-session target を Linux 限定で持つ
- **I7 (Q7) swaybg は reload ごとに張り替え、累積させない**: 壁紙が決まらなければ何もしない。新インスタンスを
  先に起動し、1 秒後に新インスタンスの生存（`kill -0`）を確認してから旧インスタンス（起動前に `pgrep -u $USER`
  で記録）だけを終了する
- **I8 (Q9) zprofile の配線**: 共通 `DOTFILES_MAP`。Nix は `programs.zsh` が rc を生成するため、
  zshenv と同じく `zsh.nix` の `profileExtra` から dotfiles の `zprofile` を source する形で揃える。
  CI（`.github/workflows/zsh.yaml`）の `zsh -n` 対象にも `zprofile`・`arch/sway.sh` を含める
- **I9 sway 終了時の後始末**: `arch/sway.sh` は sway が戻った後（rc 0・非 0・debug の全経路。ログインシェル
  自体が kill された場合は走らない）に systemd user manager から
  `WAYLAND_DISPLAY`/`SWAYSOCK`/`DISPLAY` を unset してから `sway-session.target` を `--no-block` で止める。
  linger 下で stale な `WAYLAND_DISPLAY` が kanshi（`Restart=always`）の Condition を満たし続けるのを防ぐ。
  失敗は握り潰さず `_sway_log` で報告。通常の起動前経路は fork しない（`SWAY_DEBUG_MODE=1` のログ名生成のみ例外）
- **I10 `--all` import の除外**: `XDG_ACTIVATION_TOKEN`/`DESKTOP_STARTUP_ID`（sway が exec ごとに付与する
  一回限りのトークン）と `XDG_SESSION_ID`/`XDG_VTNR`（ログインセッション固有）は import しない
  （dbus-update-activation-environment(1) の推奨）。tmux の `update-environment` には `SWAYSOCK` を加え、
  起動時から動く tmux.service のサーバーへ sway 端末から attach した後に作る window/pane が現在の sway ソケットを
  得る（既存ペインのシェル環境は変わらない）
- **I11 tmux.service は Type=oneshot + RemainAfterExit**: 端末が `new-session -A` で先にサーバー/セッションを
  作りうるため、ExecStart は `has-session -t =%u@%H: || new-session -d` で既存時も成功する（末尾 `:` は
  ドット入りホスト名を window.pane と解釈させないため。tmux 3.8 の使い捨てソケットで `=kp@a.b.c:` の一致を確認）。
  `ExecReload=` も同じ冪等コマンドで、unit の cgroup 内でサーバーを作り直すだけで何も止めない。サーバー終了後も
  unit は active のまま残るので、`zsh/01-tmux.zsh` は `has-session` 失敗時に `systemctl --user reload`（active
  時）→ 失敗なら `start`（未起動時）を呼ぶ。shell から `restart` は呼ばない（ExecStop の kill-server と cgroup
  kill が生きたサーバーを壊しうるため。stderr 文言による判定もしない）。tmux は終了時に socket ファイルを残す
  ため待機ループは即抜ける（Phase 4.5 perf レビュー 2026-10-21、bwrap 隔離＋スタブで確認）。sway の `$term` 等
  の端末経路は zsh を通らないため unit への再所有は行わない。**デプロイ時に tmux.service を手動 restart しない**（ExecStop の kill-server で
  attach 中の全端末が落ちる）。`daemon-reload` のみ行い、oneshot 化は次回起動から効く
- **I12 zshrc の早期 tmux attach**: tmux の外のシェル（`$TMUX` 空かつ `_ZSH_TMUX_LOADED` 未継承）に限り、`zsh/01-tmux.zsh` を TTY 設定・
  `_apply_base_path`・sheldon より前に source する（exec tmux するシェルはそれらを捨てるため）。tmux ペイン内の
  シェル（`$TMUX` あり）は従来どおり sheldon の後で source する（前に置くと `$+commands` 参照で command hash を
  継承 PATH から作った直後に `_apply_base_path` が PATH を差し替えて再構築させ、初回プロンプトが約 1.2ms 遅れる
  — Phase 4.5 perf レビュー 2026-10-21、bwrap 隔離＋スタブ、n=150 交互計測）。早期の `_apply_base_path` は darwin・env キャッシュ
  再生成直後（関数内 source で焼き込み PATH が失われる）・tmux 未解決時のみ実行し、その場合は後段の同期呼び出しを
  同一プロセス内の非 export フラグで省く（継承した `_ZSH_PATH_LOADED` では絶対にゲートしない）。zshrc の
  `-c` fast path は外部ツールが `zsh -c` 内で `~/.zshrc` を明示 source する経路（Claude Code の shell
  snapshot）で到達するため残す

### 検討された選択肢と決定根拠

- Q1: profile.d 維持 / systemd user unit (uwsm 型) を不採用。前者は root と全 tty に波及、後者は VT・
  logind セッション紐付けの変更量とリスクが最大
- Q2: キー明示列挙は GPU 分岐や /etc/environment のキーを sway.conf 側でも保守する二重管理が再発するため不採用。
  `--all` の代償（SHLVL/PWD/PATH/TERM/ATUIN_SESSION 等が systemd user env と D-Bus activation env に入る）は
  受容。今後 zshenv・zprofile・/etc/environment から秘密情報を export してはならない（そのまま全 user unit に渡る）
- Q3: インストール時のホスト固定は GPU/ドライバ差替時の不整合リスクで不採用
- Q4: セッション分離案は管理が 2 系統になるため不採用。01-tmux.zsh の既存設計意図（single shared session）に合わせた
- Q5: 「素のシェル保証（tmux 抑止）」案を推薦したが、人間判断で通常シェルを選択
- Q8: zsh 側の対象は Explore で裏取りした V8（01-tmux.zsh の ~/.zcache コピーループを tmux 外シェル限定に）・
  V9（tmux attach を sheldon 前へ）・V13（存在しない pinentry-tmux の zcompile 削除）・V15（未使用
  `tmux.new-session` と配備リンクの削除）のみ。V11（zshrc の `-c` fast path 削除）は当初含めたが撤回
  （I12 の理由で到達可能。Checker が検出）。V12（combined.zsh 鮮度判定の二重化）・V14（async-compile の毎シェル
  再帰 glob）はバックグラウンド処理で体感影響なし・過去ミッションの意図的設計のため Non-Goal

### 既知の制約と非目標

- **制約**: ログイン経路は SSH から実機再現できない（seat/DRM なし）。完了条件は自動検証に加え、人間による
  物理キーボードでの tty1 ログイン → sway → 端末で tmux が開くことの実機確認（Q10）
- **Non-Goals**: zsh 起動本体の再最適化（過去 3 ミッションで実施済み。キーエコー最悪 2.1ms は 2026-08-05
  zsh-host-verify ミッションの実測。出典は kpango/pass リポジトリの軌跡ログ
  `claude/swarm-history/-home-kpango-go-src-github-com-kpango-dotfiles.md` の同日行）、V12/V14、`/etc/environment` の内容変更、waybar の
  `sudo nvme --smart-log` 30s ポーリング（起動処理ではない）、旧資産の整理（`sway/config.d/`
  は Nix の `linux.nix` が配備するが `arch/sway.conf` が include しないため inert。include を足すと I2/I6 が崩れる。
  `arch/service/sway.service` は未配備）、保護対象 hook/verify.sh への `zprofile` 追加（swarm-evolve 提案で扱う）

## login-render-speed (2026-10-21) — ログイン直後の表示モード切り替え削減

sway デバッグログ実測（sway 起動 = 0s）: DRM/EGL 初期化 0.10s、コネクタ走査 0.17s、0.48s に初回 commit。Dell
U4919DW 2 台は EDID の preferred が 3840x1080 のため、初回 commit と tty コンソール（nvidia-drm fbdev）が
3840x1080 で、0.56〜0.78s に kanshi が 5120x1440 へ変更する。ghostty は 0.53s 起動・1.34s 初回描画。
login → sway 起動は 1s 未満で、体感遅延の主因はモード変更に伴うパネルの再同期と判断。

### 決定事項

- Q1: tty コンソール（カーネル引数 `video=`）と sway 初回 commit（`output "<make> <model> <serial>" mode`）の
  両方を最初から 5120x1440@59.977Hz にし、ログイン時のモード変更を無くす。配置・回転・scale は従来どおり
  kanshi が単独で持つ（sway.conf にはモードのみ、Dell 2 台をシリアルで指定）
- Q2: Arch の `arch/sway.sh` から `WLR_DRM_NO_ATOMIC=1` を外し atomic commit を使う（nvidia-beta 615.78）。
  NixOS 側 `nix/modules/nixos/desktop/wayland.nix` も人間判断で同時に外した（`tr` は `nvidiaPackages.stable`、
  実機未検証。sway が起動しない場合はここを戻す）
- Q3: 2 段階で検証する。段階 1 = sway 側（mode 指定 + atomic）を再ログインで計測、段階 2 = ブートエントリ
  （`/boot/loader/entries/arch.conf` と記録用の `arch/loader/entries/arch.conf`）に `video=` を追加して再起動

### 不変条件

- I1: sway.conf の output 指定はモードのみ。位置・transform・scale を書かない（kanshi のプロファイル切替と競合させない）
- I2: sway が起動しない場合も zprofile の fallback で tty シェルに戻る（login-startup-optimize の I 系を維持）

## login-autolock-boot (2026-10-21) — greetd 自動ログイン＋起動直後ロック、ghostty 常駐、起動時間

### 用語

- **自動ログイン経路**: greetd `initial_session`（起動後 1 回だけ、パスワードなし）。環境変数 `SWAY_AUTOLOGIN=1` を付けて `zsh -l` を起動する
- **パスワード経路**: greetd `default_session`（tuigreet）。`SWAY_AUTOLOGIN` なしで `zsh -l` を起動する

### 決定事項

- Q1: getty 自動ログインではなく greetd の `initial_session`＋swaylock（ログアウト後はパスワード必須に戻る）
- Q2: greetd は `zsh -l` を起動し、sway の起動は従来どおり `~/.zprofile` → `arch/sway.sh` の 1 経路に保つ
  （login-startup-optimize の「zprofile が唯一の launcher」を維持。zprofile の tty1 ゲートが greetd の vt1 でも成立することを実機で確認する）
- Q3: sway 失敗時、`SWAY_AUTOLOGIN=1` ならセッション終了（greetd のパスワード画面へ）、それ以外は従来どおり対話シェル（login-startup-optimize Q5）
- Q4: `SWAY_AUTOLOGIN=1` のとき最初の端末は `swaylock -f` 成功後にだけ開く（-f はロック確立後に fork）。waybar・壁紙は並行のまま
- Q5: ghostty 常駐は dotfiles 管理の unit。vendor と同名 `app-com.mitchellh.ghostty.service` を `~/.config/systemd/user` に置いて上書きし、D-Bus activation と整合させる
- Q6: `/etc/modprobe.d` は symlink ではなく実ファイル copy（initramfs に dangling symlink を入れない）。編集後は再 install＋`mkinitcpio -P` が必要
- Q7: `loader.conf` timeout 0、mkinitcpio `MODULES` から nvidia 4 件を外す（early KMS を手放す。video= は nvidia_drm の udev ロード時に適用）
- Q8: 孤立 `/usr/lib/modules` 削除、sshd の tailscale IP bind 失敗、wait-online→docker を対象に含める
- Q9: 段階 A（再起動不要: T1-T3）→ B（再起動: T4）→ C（再起動: T5 greetd）で反映し、段階ごとに止めて切り分ける
- Q10: docker / NetworkManager-wait-online は変更せず、greetd と sway がそれらを待たないことを実測で確認するのみ

### 不変条件

- I1: 自動ログイン経路で、ロック確立前にユーザーの端末内容（tmux）を描画しない
- I2: 自動ログイン経路で、認証なしの対話シェルを残さない（sway 失敗・終了時はセッション終了）
- I3: greetd 失敗時の復旧手段を残す: SSH と tty2 の getty（パスワード）から `getty@tty1` を再有効化できる
- I4: ghostty 常駐プロセスが落ちても端末の中身は tmux サーバー側に残る（tmux.service は独立）

### 非目標

- NixOS ホスト `tr`（greetd は既存）、nvidia.ko の strip / ファームウェア個別除外、docker の socket activation 化

## zsh-startup-4x (2026-10-21) — 対話起動の準備完了時間と `zsh -c` をそれぞれ 4 倍に

計測（2026-10-21、pty 直下の `zsh -i`、変更前 = main ツリー / 変更後 = 本変更、同一構造のハーネスで交互計測。
ハーネスは mission の scratchpad のみでリポジトリには無い）:
準備完了（全 zsh-defer タスク完了かつ最終再描画）119.7ms → 28.8ms（4.16 倍。レビュー時の独立ハーネスでは
121.7 → 31.2ms の 3.9 倍で、余裕はほぼ無い）、初回プロンプト 14.8 → 8.3ms、
`zsh -c exit`（hyperfine 平均）9.6 → 2.2ms（未丸め値で 4.31〜4.34 倍、下限 `zsh --no-rcs` 0.95ms）。
起動直後 0〜100ms に 1 打鍵送ったときのキーエコー遅延（190 サンプル）: p95 10.9 → 4.9ms、最大 11.8 → 6.1ms。
読み込み完了後の定常状態は平均差 +0.025ms（95% CI [-0.010, 0.060]、有意差なし）。
従来の「最終バイト」指標（94ms）は最終描画後に走る補完キャッシュ等のタスクを含まず過小評価だった。

### 決定事項

- Q1（指標）: 対話起動の準備完了時間と `zsh -c` の両方を 4 倍にする。初回プロンプト表示は対象外 — 本番相当の
  計測で 13.1ms、4 倍の 3.3ms は素の `zsh -i`（3.5ms）を下回る。同期必須の `stty`（~1.7ms）だけでも届かない
- Q2（lazy load）: 関数/コマンド単位の初回使用時ロードは許容、常用の対話機能は起動時ロードのまま。結果として
  初回使用時ロードは導入しておらず、`zsh -c` 側で省いたのは I3 の項目だけ

### 不変条件

- I1: 起動中に一時的に変えるのはハッシュの作り方だけ。zshrc は HASH_LIST_ALL と HASH_DIRS を外して末尾で戻し、
  zshenv の `-c` 分岐は HASH_LIST_ALL だけを外して直後に戻す（`zsh -c` の HASH_DIRS は zsh 既定で off）。全ハッシュ構築（~1.9ms）は起動中の遅延タスクで起こす — 起動から外すと
  `correct` により初回コマンド実行時に移るため（実測確認済み）
- I2: サードパーティ関数の差し替え（`_zsh-defer-schedule`、`_zsh_autosuggest_bind_widgets`）は上流の関数本体長が
  既知の版と一致する時だけ行い、不一致なら上流実装のまま動く（長さが変わらない編集は検出できない。zsh の関数
  表示形式が変わっても無効化されるが、その場合も無通知で上流実装になるだけ）。autosuggest のキャッシュは全入力（ウィジェット表 +
  設定配列 + 束縛カウント）をキーとし、ファイル先頭で自己照合する（並行書き込みや .zwc との組み合わせ違いでも
  誤適用しない）。キャッシュのヒット時・ミス時とも、ウィジェット表・`_zsh_autosuggest_{bound,orig}_*`・
  `_ZSH_AUTOSUGGEST_BIND_COUNTS` を含むシェル状態全体が上流と同一になることを状態比較で確認。生成ロジックを
  変えたらキー先頭の版（`v1`）を上げる
- I3: `-c` 指定時（`$ZSH_EXECUTION_STRING` あり、`zsh -i -c` も含む）に省くのは行編集（ZLE）専用の設定・
  ウィジェットと対話用の副作用（tmux 環境変数、atuin デーモン確認、k8s 補完キャッシュ）。別軸として `gpg-connect-agent updatestartuptty` は対話かどうかではなく
  端末の有無（`$TTY` が空なら省く）で決める。関数（`select-word-style` 本体と、それが autoload する ZLE
  ウィジェット用 `*-match` 8 件を除く）・alias・環境変数・PATH は変更前と同一（状態比較で確認済み）
- I4: sheldon の inline プラグインもテンプレートとして解釈される — `{#` を書かない（`${#x}` は `$#x` と書く）。
  sheldon が描画に失敗すると空の sheldon.zsh がキャッシュされ全プラグインが消えるため、sheldon.toml の変更は
  `sheldon source` が成功することを確認してから入れる

### 補足

- `zsh -c` の 4 倍は tmux 内（`$TMUX` あり）での値。tmux 外では変更前が 5.5ms（tmux 環境変数設定が無い）で
  2.2ms の 2.5 倍に留まり、下限 0.95ms から 4 倍は届かない
- tmux-xpanes は sheldon テンプレート（`xpanes-path`）で bin/補完パスを直接足す。従来の遅延 source は compinit の
  後に fpath を足していたため補完が登録されていなかったが、同期になり登録されるようになった（挙動差）
