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
