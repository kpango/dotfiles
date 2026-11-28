# Pi agent 改善30技術 — 実装状況マトリクス

- 作成: 2026-11-22 (mission `pi-techniques-30`)
- 更新: 2026-11-28 (OMP -> `@earendil-works/pi-coding-agent@1.7.0` 移行 + `pi-sota-30` SOTA 昇華)
- 対象: `/home/kpango/Downloads/pi-agent-improvement.pdf` の30技術
- 判定対象: Pi 1.7.0 host / Pi repo (`agent/harnesses/pi`) / Claude / Agy
- 判定記号: `IMPL`=機構が存在し既定で有効 / `PART`=機構はあるが論文の形と異なる・既定無効・片側のみ /
  `ABSENT`=無し / `REJECT`=この環境では採用しない / `FIXED`=本ミッションで導入・強化

> 注: 原 PDF (`/home/kpango/Downloads/pi-agent-improvement.pdf`, 全39ページ) の30技術・推奨コンポジションスタック A/B/C に基づき、
> 「最小コア＋高 Prefix キャッシュ効率」を維持したまま観測・編集・検証・状態・再帰・可観測性の各境界を実装した。

## 30技術マトリクス

`H`=Pi 1.7.0 host, `P`=Pi repo (`agent/harnesses/pi`), `C`=Claude, `A`=Agy。証拠は特記なき限り repo 相対。

| #   | 技術                                                                         | H      | P         | C      | A      | 判定            | 根拠 / 差分                                                                                                                                                                                                       |
| --- | ---------------------------------------------------------------------------- | ------ | --------- | ------ | ------ | --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Prefix KV-cache 保全 + cache warming (PACT)                                  | IMPL   | **FIXED** | PART   | PART   | 採用 + 強化     | host `cacheWarming: "idle"` + `sol-pi-core.ts` ブロック単位 ObservationPack、`loop-guard.ts`・`thinking-budget.ts` の `systemPrompt` 非変異厳守                                                                   |
| 2   | SoL-Pi 一式 (Action Fusion / ObservationPack / EP-Reducer / OCC)             | PART   | IMPL      | ABSENT | ABSENT | 既存 (Pi)       | `agent/harnesses/pi/extensions/sol-pi.ts`, `lib/sol-pi-core.ts`, `sol-pi.json` (`pi` 名前空間へ移行)。OCC は既定 off (`onlineContextCompact:false`)                                                               |
| 3   | 厳選スキル + 遅延/代理 tool loading                                          | IMPL   | **FIXED** | PART   | PART   | 採用 + 強化     | host `tool_search` + `SKILL.md` (`test-catalog-health.sh` 検証)。専門拡張ツール 31 個へ `exposure: "deferred"` を適用し直接スキーマを 4 個へ圧縮 (`harness-tax.test.ts`)                                          |
| 4   | Codemode / programmatic tool calling                                         | IMPL   | IMPL      | ABSENT | ABSENT | 既存 (Pi)       | `settings.json` `defaultTools` に `codemode` + `tool_search` を有効化、`mcp.json` の `trail` + 6 Docker MCP を `exposure: "codemode"` 統合                                                                        |
| 5   | Hash-anchored edit (Hashline)                                                | PART   | **FIXED** | ABSENT | ABSENT | 自前拡張 + 強化 | `hashline-core.ts` / `hashline-edit.ts` に `read` 行番号+ハッシュ付与・ハッシュ検証置換・±15行一意 Auto-Rebase・CAS Undo ストア (32世代, `/edit-undo`) を実装                                                     |
| 6   | RL middleware guardrails (checklist / loop / time budget / onboarding)       | PART   | **FIXED** | PART   | PART   | 採用 + 強化     | `stop-verify.ts` (`agent_before_settle` + `evidence-ledger.ts`) + 新設 `loop-guard.ts` (Read-Guard / 5 edit Doom-Loop / 3 連続失敗 / `PI_TURN_BUDGET=40` / `/env-context`)                                        |
| 7   | リアルタイム LSP/静的/test フィードバック + delta diagnostics + commit guard | PART   | **FIXED** | PART   | PART   | 自前 + 強化     | 自前 `lsp-client.ts` + `dap-client.ts` に Delta Diagnostics（新規エラーのみ抽出）、Honesty Contract (`[LSP diagnostics: unconfirmed ...]`)、Commit Guard (`git commit`/`push` 阻止) を追加                        |
| 8   | 外部化タスク状態 + 独立監査ループ                                            | IMPL   | IMPL      | IMPL   | IMPL   | 既存            | `@fix_plan.md` + `missionBridge`、`evidence-ledger.ts`、swarm の `adversarial-reviewer` (repro-evidence 要求)                                                                                                     |
| 9   | Reasoning budget + model/harness 切替                                        | IMPL   | **FIXED** | IMPL   | IMPL   | 採用 + 強化     | `thinking-budget.ts` に **Reasoning Sandwich** (`plan=xhigh` -> `implement=high` -> `verify=xhigh`、高速系 `medium/low/high`) + Model-Family Guidance (`/thinking-budget profile`, Prefix KV-Cache 非破壊) を実装 |
| 10  | 長距離 context 管理 (LCM: 階層要約 DAG + 不変 store)                         | PART   | **FIXED** | ABSENT | ABSENT | 採用 + 強化     | `lcm-core.ts` / `lcm-context.ts` に不変 JSONL+SHA-256 Store・3段階収束 Compaction・**Subtask Stack Machine** (`subtask_frame`, `lcm_recall`, deferred 登録) を実装                                                |
| 11  | 動的/再帰的 tool discovery (RLM, CRISP)                                      | PART   | PART      | PART   | ABSENT | 保留            | `find` (judge role = `typesafe/jev`) と repomap で近似。再帰的 code execution は無い                                                                                                                              |
| 12  | Agentless / セマンティック検索ハイブリッド                                   | IMPL   | PART      | PART   | PART   | 既存            | host `find.enabled=auto` + `modelRoles.judge: typesafe/jev`、`search_sessions`、trail graph                                                                                                                       |
| 13  | ツリー型セッション分岐 & 隔離ブランチレビュー (`pi-review` 方式)             | IMPL   | **FIXED** | PART   | PART   | 採用 + 強化     | `session-tree.ts` に `/branch-review [uncommitted                                                                                                                                                                 | branch:<base> | return]` (`navigateTree` 要約ハンドオフ + Human Reviewer Callouts 分離) を追加 |
| 14  | タスク分離 + git worktree                                                    | IMPL   | **FIXED** | IMPL   | PART   | 既存 + 強化     | `worktree-core.ts`、`subagents.ts`、`subagent-mesh-core.ts` (`selectSelfOrganizingTopology` 5種トポロジ自動選択 + `StigmergyBoard` 協調フェロモンボード, `/mesh topology`, `/mesh signals`)                       |
| 15  | Contract/TDD 駆動実装                                                        | PART   | PART      | PART   | PART   | 既存            | SWARM の TDAD/verify ゲート。契約抽出は `spec_miner` ロール                                                                                                                                                       |
| 16  | 外部監査 + trace + change manifest + テレメトリ                              | IMPL   | **FIXED** | PART   | PART   | 採用 + 強化     | `context-economy.ts` が `session_shutdown` で `~/.pi/agent/telemetry/sessions.jsonl` (`0600` / cwd SHA-256 ハッシュ) を追記し `/economy` に Active Tools 数を表示                                                 |
| 17  | Context 圧縮 + 省略ポインタ (actionable omission)                            | IMPL   | IMPL      | PART   | PART   | 既存            | `sol-pi.ts` ObservationPack + `repl-context.ts` + `codemode`                                                                                                                                                      |
| 18  | 役割別モデルルーティング (`role/*` Virtual Models + failover)                | IMPL   | **FIXED** | PART   | PART   | 自前 + 強化     | 自前 `model-roles.ts` (`role/*` 10 ロール) + `model-failover.ts` / `subagents.ts` の `openai-codex`・`antigravity` 実プロバイダ正規化                                                                             |
| 19  | 無限 context の harness ratchet (RRSI)                                       | ABSENT | **FIXED** | ABSENT | ABSENT | 採用 + 強化     | `harness2-offline.py --rrsi` に Leakage Critic・Annealed Diff Budget・Bootstrap ノイズ下限 (`--noise-floor`)・構造 Pruner (`--prune-audit`) を実装                                                                |
| 20  | Offline search over harness experiences (RHO / Meta-Harness)                 | ABSENT | **FIXED** | ABSENT | ABSENT | 採用 + 強化     | `harness2-offline.py` に AHE 反証マニフェスト評価 (`evaluate_ahe_manifest`) + RRSI・`--prune-audit`・`.trail/learnings/` 連携を統合                                                                               |
| 21  | Harness² 2階層自己改善 & 2回連続退行ロールバック                             | ABSENT | **FIXED** | ABSENT | ABSENT | 採用 + 強化     | `continual-harness.ts` (`refinement-ledger.json` + 2回連続摩擦増自動ロールバック) + `harness2-offline.py` (`--rrsi`, AHE 反証評価, `--prune-audit`)                                                               |
| 22  | Environment onboarding + friction telemetry                                  | PART   | **FIXED** | PART   | PART   | 採用 + 強化     | `loop-guard.ts` の `/env-context` + `developer-ergonomics.ts` (`/doctor`) + `context-economy.ts` telemetry JSONL                                                                                                  |
| 23  | RAH loop (research → audit → harden)                                         | PART   | IMPL      | IMPL   | PART   | 既存            | `/swarm-graph`, `/swarm-loop`, 8 adversarial reviewer, GATE                                                                                                                                                       |
| 24  | Agentless pipeline (localize → repair → validate)                            | PART   | PART      | PART   | PART   | 既存            | plan-mode、task DAG、決定的ゲート。完全な単一パイプラインではない                                                                                                                                                 |
| 25  | Autoresearch 自己改善ループ                                                  | PART   | PART      | ABSENT | ABSENT | 任意            | host autoresearch / `goal_loop`、harness2 pipeline。既定では使わない                                                                                                                                              |
| 26  | Billion-context / 可逆圧縮 proxy                                             | PART   | ABSENT    | ABSENT | ABSENT | 不採用          | host の shake は可逆 elision だが長距離 proxy ではない。外部 proxy はデータ境界・コストの理由で不採用                                                                                                             |
| 27  | Cross-model ensemble + placement                                             | PART   | PART      | PART   | ABSENT | 既存            | `consensus-verifier.ts`, `run_adversarial_review`, `model-routing.json` の tier/fallback                                                                                                                          |
| 28  | Verifier/scorer 学習 + rollback                                              | PART   | PART      | PART   | PART   | 任意            | `checkpoint.enabled=false` 既定、review ロール。モデル学習は Out of Scope                                                                                                                                         |
| 29  | 軽量/重量の統一 governance                                                   | PART   | PART      | PART   | PART   | 既存            | `agent/` SSoT + 共有ゲート。Agy は Stop 未配線で強制力が弱い (既知)                                                                                                                                               |
| 30  | Cross-harness transfer / portability                                         | PART   | PART      | PART   | PART   | 既存            | `agent/` 共有 + `bridge-hermes.ts` + per-harness `model-routing.json`。codemode の移植は未対応                                                                                                                    |

## 2026-11-28 `pi-sota-30` で適用した昇華

1. **Harness Tax 排除 (PDF #1, #3, #4)**:
   - カスタム拡張 35 ツールのうち基盤 4 ツール (`edit`, `obs_recall`, `update_plan`, `subagent`) のみを direct 維持し、残り 31 専門ツールへ `exposure: "deferred"` を適用（`lib/harness-tax.test.ts` で上限 <=5 を機械強制）。
2. **LangChain Middleware & LSP 強化 (PDF #6, #7)**:
   - `loop-guard.ts`（Read-Guard / 5 edit Doom-Loop / 3 連続失敗検知 / `PI_TURN_BUDGET=40` / `/env-context`）を追加。
   - `lsp-client.ts` に Delta Diagnostics、Honesty Contract (`[LSP diagnostics: unconfirmed ...]`)、Commit Guard を追加。
3. **Reasoning Sandwich (PDF #9)**:
   - `thinking-budget.ts` に `plan -> implement -> verify` フェーズ別思考努力切替を追加（`systemPrompt` 非変異）。
4. **ツリー型隔離レビュー (PDF #13)**:
   - `session-tree.ts` に `/branch-review [uncommitted|branch:<base>|return]` (`navigateTree` 要約ハンドオフ) を追加。
5. **セッションテレメトリ (PDF #16)**:
   - `context-economy.ts` に `session_shutdown` JSONL 記録 (`~/.pi/agent/telemetry/sessions.jsonl`, mode `0600`) を追加。
6. **2回連続退行自動ロールバック (PDF #21)**:
   - `continual-harness.ts` に `refinement-ledger.json` と 2 回連続摩擦増で `.bak` へ自動復元する安全網を追加。
7. **LCM + Subtask Stack Machine (PDF #10, Phase 2)**:
   - `lcm-core.ts` / `lcm-context.ts` に `ImmutableLcmStore` (`0700`/`0600` JSONL + SHA-256 `lcm-<10hex>` ID・`utf8SafeTruncate`)、3段階収束 Compaction (`escalateCompact`)、`SubtaskStackMachine` (`subtask_frame`, `lcm_recall`, deferred 登録で `direct <= 5` 不変条件を維持) を追加。
8. **RRSI 正則化 + AHE 反証マニフェスト + Prune Audit (PDF #19, #20, #21, Phase 2)**:
   - `harness2-offline.py` に Leakage Critic (`check_leakage`)・Annealed Diff Budget (`annealed_max_lines`)・Bootstrap ノイズ下限 (`bootstrap_net_gain_lower_bound`)・AHE 反証マニフェスト評価 (`evaluate_ahe_manifest`)・`--prune-audit` を実装。
9. **自己組織化トポロジ + Stigmergy Board (PDF #14, Phase 2)**:
   - `subagent-mesh-core.ts` / `subagent-mesh.ts` に 5 種トポロジ自動選択 (`selectSelfOrganizingTopology`) と時間減衰フェロモンボード (`StigmergyBoard`, `/mesh topology`, `/mesh signals`) を統合。
10. **Hashline Auto-Rebase + CAS Undo & Model-Family Profile (PDF #5, #9, Phase 2)**:
    - `hashline-core.ts` / `hashline-edit.ts` に ±15 行一意 Auto-Rebase (`findUniqueRebasedLine`) と 32 世代 CAS Undo (`CasUndoStore`, `/edit-undo`) を実装。`thinking-budget.ts` に `resolveModelFamilyGuidance` と `/thinking-budget profile` を追加（`systemPrompt` 不変で KV-Cache を保持）。

## 意図的に除外した機構（PDF アンチパターン回避）

- **26 billion-context**: コード識別子の Needle-in-a-Haystack 劣化リスク（69%→27%）および二重課金/圧縮競合のため不採用。
- **pi-pstack-native / @piex-dev/***: 外部 npm 依存を増やさず、SWARM/Ponytail・自前拡張 (`hashline-edit`/`lsp-client`/`dap-client`/`ttsr-guard`/`model-roles`) へ統合。
- **常時 RLM / 無検証 `/refine` 自動改変**: 通常タスクは Pi 最小コア + Codemode + SoL-Pi で処理し、RLM は 200K+ トークン監査 (`rlm-deep-audit` / `repl_query`) のみに限定。

## 再現ゲート

```bash
bash agent/scripts/test-all-harnesses.sh
bash agent/skills/_swarm-common/test-common.sh
bash agent/scripts/test-root-agent-files.sh
bash agent/scripts/sync-verify.sh
```
