# Pi agent 改善30技術 — 実装状況マトリクス

- 作成: 2026-11-22 (mission `pi-techniques-30`)
- 対象: `plans/pi-agent-improvement.pdf` の30技術
- 判定対象: OMP 19.0.1 host source / OMP repo (`agent/harnesses/omp`) / Claude / Agy
- 判定記号: `IMPL`=機構が存在し既定で有効 / `PART`=機構はあるが論文の形と異なる・既定無効・片側のみ /
  `ABSENT`=無し / `REJECT`=この環境では採用しない / `FIXED`=本ミッションで導入

> 注: 原 PDF はこの worktree に存在しないため、技術名は依頼時に提示された30項目リストに従い、
> 実装判定は「原論文 (SoL-Pi, arXiv:2609.20519)・上流リポジトリ・host 19.0.1 の実ソース」で行った。
> Web 検索は実行環境のネットワーク制約で一次ページを取得できず、上流2リポジトリ
> (`NVlabs/SoL-Pi`, `google-research/harness2`) と host source を一次情報とした。

## 30技術マトリクス

`H`=host 19.0.1, `O`=OMP repo, `C`=Claude, `A`=Agy。証拠は特記なき限り repo 相対、
`host:` は `pi-coding-agent/src/` 配下。

| #   | 技術                                                                         | H    | O         | C      | A      | 判定        | 根拠 / 差分                                                                                                                                                                                                                                                                                            |
| --- | ---------------------------------------------------------------------------- | ---- | --------- | ------ | ------ | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | Prefix KV-cache 保全 + cache warming (PACT)                                  | PART | PART      | PART   | PART   | 既存        | host `session/cache-warmer.ts`, `providers.cacheWarming=idle` 既定。OMP `sol-pi-core.ts` の projection pack、`context-economy.ts`。Claude `subagentPromptCacheTtl:1h`、Agy `experimental.promptCaching`                                                                                                |
| 2   | SoL-Pi 一式 (Action Fusion / ObservationPack / EP-Reducer / OCC)             | PART | IMPL      | ABSENT | ABSENT | 既存 (OMP)  | `agent/harnesses/omp/extensions/sol-pi.ts`, `lib/sol-pi-core.ts`, `sol-pi.json`。OCC は既定 off (`onlineContextCompact:false`)                                                                                                                                                                         |
| 3   | 厳選スキル + 遅延/代理 tool loading                                          | IMPL | PART      | PART   | PART   | 既存        | host `capability/skill.ts`, `DeferredMCPTool` (`mcp/tool-bridge.ts`), `task/executor.ts` proxyTools。repo `test-catalog-health.sh` が skill 予算を機械検証                                                                                                                                             |
| 4   | Codemode / programmatic tool calling                                         | IMPL | ABSENT    | ABSENT | ABSENT | 既存 (host) | host `eval/js/tool-bridge.ts`, `eval/py/tool-bridge.ts`, `eval.tools.enabled=true`。`eval` が `tool.<name>(...)` を提供する。OMP 側に codemode 経路は無い                                                                                                                                              |
| 5   | Hash-anchored edit (Hashline)                                                | IMPL | IMPL      | ABSENT | ABSENT | 既存 (OMP)  | `config.yml` `edit.mode: hashline` / `fuzzyThreshold`。Claude/Agy は文字列置換ネイティブ                                                                                                                                                                                                               |
| 6   | RL middleware guardrails (checklist / loop / time budget / onboarding)       | PART | **FIXED** | PART   | PART   | 採用        | `stop-verify.ts` が `session_stop` で `decision:"block"` を返す強制ゲートへ移行 (本ミッション)。host `advisor/loop-guard.ts`、`todo.reminders`、`task.maxRuntimeMs` (既定 0)。Claude は dotfiles の project `.claude/settings.json` のみ Stop 配線、Agy は Stop 非対応 (PreToolUse + PostToolUse のみ) |
| 7   | リアルタイム LSP/静的/test フィードバック + delta diagnostics + commit guard | IMPL | PART      | PART   | PART   | 既存 + 修正 | host `lsp.diagnosticsOnWrite=true` 既定、`commit.enabled` (selective commit)。OMP は `lsp` tool + `stop-verify`。Agy の `agent/harnesses/agy/hooks/post-edit-lint.sh` は診断を破棄する既知欠陥 (後述)、matcher に `multi_replace_file_content` 漏れを修正 (`edit_file` は contrib 版の予約)            |
| 8   | 外部化タスク状態 + 独立監査ループ                                            | IMPL | IMPL      | IMPL   | IMPL   | 既存        | `@fix_plan.md` 状態機械、`todo`/`plan`、swarm の reviewer/auditor                                                                                                                                                                                                                                      |
| 9   | Reasoning budget + model/harness 切替                                        | IMPL | PART      | IMPL   | IMPL   | 既存        | host は `prewalk.auto` 既定 off / `task.enableEffort` 既定 false。repo `config.yml` は `prewalk.auto: on` (`prewalk.enabled: false` のため本環境では未稼働) と `task.enableEffort: true` を設定。Claude `effortLevel:xhigh` + `model-routing.json`、Agy `dynamicModelConfiguration`                    |
| 10  | 長距離 context 管理 (LCM: 階層要約 DAG + 不変 store)                         | PART | ABSENT    | ABSENT | ABSENT | 保留        | host は線形 compaction + artifact spill。`compaction.experimentalContextManagement` は既定 off。LCM の DAG は未実装で、別ミッション規模                                                                                                                                                                |
| 11  | 動的/再帰的 tool discovery (RLM, CRISP)                                      | PART | PART      | PART   | ABSENT | 保留        | `find` (judge role = `typesafe/jev`) と repomap で近似。再帰的 code execution は無い                                                                                                                                                                                                                   |
| 12  | Agentless / セマンティック検索ハイブリッド                                   | IMPL | PART      | PART   | PART   | 既存        | host `find.enabled=auto` + `modelRoles.judge: typesafe/jev`、`search_sessions`、trail graph                                                                                                                                                                                                            |
| 13  | SIA / 自己改善 harness                                                       | PART | PART      | PART   | PART   | 任意        | `synthesize_skill`, `harness_refine`, `/swarm-evolve` (人間承認必須)。自動改変は意図的に不可                                                                                                                                                                                                           |
| 14  | タスク分離 + git worktree                                                    | IMPL | PART      | IMPL   | PART   | 既存        | repo `config.yml` `task.isolation.enabled: true` / `merge: patch` (host 既定 false)、`using-git-worktrees` skill                                                                                                                                                                                       |
| 15  | Contract/TDD 駆動実装                                                        | PART | PART      | PART   | PART   | 既存        | SWARM の TDAD/verify ゲート。契約抽出は `spec_miner` ロール                                                                                                                                                                                                                                            |
| 16  | 外部監査 + trace + change manifest                                           | PART | PART      | PART   | PART   | 保留        | `mission-bridge.ts` の trace、host telemetry/OTLP 設定 (export 先未設定)。manifest は producer/consumer 双方に実装済み（`pi30-applicability.md` §2 参照）                                                                                                                                              |
| 17  | Context 圧縮 + 省略ポインタ (actionable omission)                            | IMPL | PART      | PART   | PART   | 既存        | host artifact spill / `read.summarize` / shake、OMP ObservationPack                                                                                                                                                                                                                                    |
| 18  | Multi-model KV handoff / compaction bridge                                   | PART | PART      | PART   | PART   | 既存        | `retry.fallbackChains`、compaction、`prewalk`。モデル間 KV 厳密引き継ぎは無い                                                                                                                                                                                                                          |
| 19  | 無限 context の harness ratchet (RRSI)                                       | PART | ABSENT    | ABSENT | ABSENT | 保留        | host `ratchet` は存在するが `ratchet.enabled=false` 既定、repo 未設定。有効化には専用研究ミッションが必要                                                                                                                                                                                              |
| 20  | Offline search over harness experiences (RHO)                                | PART | PART      | ABSENT | ABSENT | 任意        | `agent/scripts/evolve/harness2-offline.py` + trail learnings。自動探索ループは無い                                                                                                                                                                                                                     |
| 21  | Minimal masks / recovery-oriented prompting                                  | PART | PART      | PART   | PART   | 既存        | SoL-Pi の projection mask、hashline edit、`recovery` 文言。CLAUDE/AGENTS の失敗回復規約                                                                                                                                                                                                                |
| 22  | Environment onboarding + friction telemetry                                  | PART | **FIXED** | PART   | PART   | 既存 + 修正 | host は `<project-context>`/AGENTS 注入 + `/doctor`。`config.yml` の `memory.enabled`/`disassembler.enabled`/`tools.disabled` が**未登録キー**だったのを `memory.backend`/`disassembler.backend`/`speechgen.enabled` ほかへ修正 (本ミッション)                                                         |
| 23  | RAH loop (research → audit → harden)                                         | PART | IMPL      | IMPL   | PART   | 既存        | `/swarm-graph`, `/swarm-loop`, 8 adversarial reviewer, GATE                                                                                                                                                                                                                                            |
| 24  | Agentless pipeline (localize → repair → validate)                            | PART | PART      | PART   | PART   | 既存        | plan-mode、task DAG、決定的ゲート。完全な単一パイプラインではない                                                                                                                                                                                                                                      |
| 25  | Autoresearch 自己改善ループ                                                  | PART | PART      | ABSENT | ABSENT | 任意        | host autoresearch / `goal_loop`、harness2 pipeline。既定では使わない                                                                                                                                                                                                                                   |
| 26  | Billion-context / 可逆圧縮 proxy                                             | PART | ABSENT    | ABSENT | ABSENT | 不採用      | host の shake は可逆 elision だが長距離 proxy ではない。外部 proxy はデータ境界・コストの理由で不採用                                                                                                                                                                                                  |
| 27  | Cross-model ensemble + placement                                             | PART | PART      | PART   | ABSENT | 既存        | `consensus-verifier.ts`, `run_adversarial_review`, `model-routing.json` の tier/fallback                                                                                                                                                                                                               |
| 28  | Verifier/scorer 学習 + rollback                                              | PART | PART      | PART   | PART   | 任意        | `checkpoint.enabled=false` 既定、review ロール。モデル学習は Out of Scope                                                                                                                                                                                                                              |
| 29  | 軽量/重量の統一 governance                                                   | PART | PART      | PART   | PART   | 既存        | `agent/` SSoT + 共有ゲート。Agy は Stop 未配線で強制力が弱い (既知)                                                                                                                                                                                                                                    |
| 30  | Cross-harness transfer / portability                                         | PART | PART      | PART   | PART   | 既存        | `agent/` 共有 + `bridge-hermes.ts` + per-harness `model-routing.json`。codemode の移植は未対応                                                                                                                                                                                                         |

## 本ミッションで採用した変更

1. **技術6: OMP の完了ゲートを強制化** — `agent/harnesses/omp/extensions/stop-verify.ts`
   - 19.0.1 の `session_stop` が `decision:"block"` を返せることを host source で確認。
   - 「セッション中に write/edit したファイル ∩ git 未コミット変更」を lint し、失敗時に修正ループへ差し戻す。
   - 連続ブロックは `OMP_STOP_VERIFY_MAX` (既定 5、上限 10) で打ち切り、上限到達後は同一失敗を
     waiver として通りす。新しい失敗は再カウントする。`OMP_STOP_VERIFY_BLOCK=0` はブロックのみ無効化。
   - キャッシュは内容 hash (≤4MB) で判定し、`touch -r` 等の mtime 偽装では通過しない。
   - `git status -z` で非 ASCII/空白入りパスも正規化。spawn は git 10s / lint 300s で打ち切る。
   - テスト: `agent/harnesses/omp/extensions/lib/stop-verify.test.ts` (32 checks)。
2. **技術22: `config.yml` の無効キー修正** — `agent/harnesses/omp/config.yml`
   - `memory.enabled` → `memory.backend: local` (登録キーは `memory.backend` のみ)。
   - `disassembler.enabled: false` → `disassembler.backend: none`。
   - `tools.disabled: [tts, generate_image, computer]` → `speechgen.enabled: false` +
     `generate_image.enabled: false` + `computer.enabled: false` (`tools.disabled` は未登録キー)。
3. **技術7: Agy の post-edit matcher 漏れ** — `agent/harnesses/agy/hooks/hooks.json`
   - ネイティブな `multi_replace_file_content` が matcher と 3 hook の whitelist から漏れていたため追加
     (`edit_file` は contrib 版の予約で、現ビルドでは発火しない)。診断破棄の本体修正は
     Agy の PostToolUse 出力契約が未文書化のため保留 (下記)。

## 未採用・保留の理由

- **10 LCM / 19 RRSI / 26 billion-context**: いずれも新しい永続ストアまたは外部 proxy を要し、
  既存の compaction/artifact 機構と重複する。設計から別ミッションで扱う。
- **Claude のグローバル Stop 配線**: `agent/harnesses/claude/settings.json` の Stop は graft のみで、
  `swarm-stop-verify.sh` は dotfiles の project `.claude/settings.json` のみに配線されている。
  dotfiles 以外の任意リポジトリで毎応答をブロックしないための**意図的なスコープ**であり、欠陥ではない
  (`agent/AGENTS-claude-supplement.md` の記述と一致)。よって変更しない。
- **Agy の post-edit 診断破棄**: `post-edit-lint.sh` は全 `subprocess.run` の出力を `DEVNULL` に捨て、
  常に `{}` を返す。Agy の PostToolUse が診断をモデルへ返す契約を一次情報で確認できないため、
  推測で `decision` を返す変更は行わない。契約判明後に修正する。
- **time budget**: host は main session の wall-clock 予算を持たない (`task.maxRuntimeMs` は委譲のみ)。
  助言のみの注入はプロンプトノイズになるため、強制力のある実装 (abort/continue 制御) が可能になるまで保留。

## 一次情報

- SoL-Pi: arXiv:2609.20519 / `NVlabs/SoL-Pi` (検証時 commit `0597fad0`)
- Harness2: `google-research/harness2` (検証時 `/tmp/harness2-upstream`)
- OMP host: `@oh-my-pi/pi-coding-agent` 19.0.1 source
  (`~/.bun/install/cache/@oh-my-pi/pi-coding-agent/19.0.1@@@1/src`)
- 既存の検証記録: `.trail/learnings/2026-11-21-omp-online-context-compact-follows-upstream-kpango.md`,
  `.trail/learnings/2026-11-21-harness2-tree-compose-port-kpango.md`

## 再現ゲート

```bash
agent/scripts/test-omp-extensions.sh
agent/harnesses/omp/validate-harness.sh
agent/scripts/test-harness2-offline.sh
python3 agent/scripts/update-model-catalog.py --check
bash agent/skills/swarm-release-gate/scripts/verify.sh "$PWD"
```
