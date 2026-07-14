---
name: swarm-loop
description: >-
  自走ループの単一エントリポイント（旧 dig を完全統合）。1 行の typo 修正から 100 体規模の Haiku 探索を伴う
  大規模自律ミッションまで、規模を自動判定して同じ状態機械で処理する。人間が「これは dig サイズか
  swarm-loop サイズか」を毎回判断するコストを排除するのが目的であり、常にこの skill 一つを起点にする。
  トリガー: 「実装して」「修正して」「調べて直して」「自律で進めて」「/dig」「/swarm-loop」
  「massive agents loop」など、コードベースへの変更を伴うタスク全般。
  境界条件: 変更を伴わない質問・調査のみは swarm-explore を直接使う（本 skill は実装まで完走するため）。
  マージ・デプロイの実行判断は本 skill では行わず、人間へ /swarm-release-gate 招集を要請して停止する。
  大量トークンを消費しうる Mission 規模の判定を誤らないよう自動発火は無効化されている。
  ミッション途中のセッション再開もこの skill から行う (@fix_plan.md と loop-status.sh で状態復元)。
allowed-tools:
  [
    Read,
    Write,
    Edit,
    Bash,
    Grep,
    Glob,
    Agent,
    Workflow,
    Skill,
    TaskCreate,
    TaskUpdate,
    TaskList,
    TaskGet,
  ]
user-invocable: true
disable-model-invocation: true
---

# swarm-loop — 統合自走ループ（旧 dig 統合済み）

全層を貫く自走ループの状態機械。人間の介入点は「起動」「Interactive モードの設計インタビュー応答」
「/swarm-architect 招集」「/swarm-release-gate 承認」のみ。

```
SCALE判定 ─▶ INIT ─▶ EXPLORE ─▶ PLAN(+設計インタビュー) ─▶ EXECUTE ─▶ CHECKPOINT ─┬─▶ 残タスク: EXECUTE へ
                                                                              ├─▶ 難局: ESCALATE ──▶ 人間
                                                                              └─▶ 完了: GATE ──▶ 人間承認 ──▶ REPORT
```

`旧 dig` の Quick/Research/Full モード判定・対話的設計インタビュー・TDAD Iron Law・複雑度ガードは、
すべて以下の Phase -1（SCALE 判定）と各 Phase 内の分岐として統合済み。`/dig` は本 skill への薄いリダイレクトに
なっており、単独の別ワークフローとしては存在しない。

## Phase -1: SCALE 判定（起動直後、必ず最初に実行）

ゴールの文言・既知の変更規模から自動判定する。不明な場合のみ人間に 1 問確認する
（「Quick(即実行)/Interactive(設計相談しながら)/Mission(大規模・自律)のどれで進めますか？」）。
**判定は昇格のみ許可し、降格はしない**（Phase 1 の結果や試行の失敗で規模が想定より大きいと分かったら
即座に昇格する。小さいと分かっても格下げしない — 安全側に倒す）。

| モード          | 判定条件                                                                                       | 適用される規模                                                                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Quick**       | バグ修正・既知ファイルへの小変更・1 ファイル 15 行以下・新規ロジックなし                       | EXPLORE 省略・設計インタビュー省略・worktree 省略・`@fix_plan.md` 省略。単一 Maker+Checker を現セッション内で完結                                |
| **Interactive** | 新機能・設計判断が要る変更だが、単一セッションで完結し人間がその場で応答できる                 | EXPLORE は Haiku 1 体・PLAN で設計インタビュー実施・並列上限 3・`@fix_plan.md` は使うが軽量                                                      |
| **Mission**     | スコープ不明・複数システム・大規模・「自律で」「swarm で」等の明示・複数セッションに跨る見込み | EXPLORE は Haiku 100 体（`swarm-explore`）・PLAN は秘書レポート駆動＋設計は `/swarm-architect` 招集・並列上限 3・`@fix_plan.md` が必須の永続状態 |

**モード昇格チェック**（Phase 1 EXPLORE 終了時）: 影響ファイル数が 6 以上判明したら Mission へ昇格。
2 以下しか無いと分かっても Quick 以外からの降格はしない。

## Phase 0: INIT

- **Quick**: 状態ファイルを作らず直接 Phase 3 (EXECUTE) の軽量パスへ進む。
- **Interactive/Mission — 再開判定**: `<repo>/@fix_plan.md` が存在すれば進行中ミッション。状態を復元:

  ```bash
  ~/.claude/skills/swarm-loop/scripts/loop-status.sh <mission-slug>
  ```

- **Interactive/Mission — 新規開始**: `AGENTS.md` を読み（過去の学びの継承）、初期化:

  ```bash
  ~/.claude/skills/swarm-loop/scripts/mission-init.sh <mission-slug> "<目標 1 文>" <interactive|mission> [self-improve-targets]
  ```

  `@fix_plan.md` の骨子が生成される。目標・完了条件（Definition of Done）・スコープ外を必ず埋める。

  **自己改善ミッションの重複チェック**: ゴールが「Claude Code 自体（CLAUDE.md / settings.json / Skill /
  Agent / hooks 等の設定・コンテンツ）の改善・監査・リファクタリング」であると判定した場合、対象を
  `self-improve-registry.tsv` と同じ固定語彙（`CLAUDE.md` / `settings.json` / `hooks` /
  `agents-content` / `skills-content` / `multi-agent-mechanism`）でトークン化し、カンマ区切りで
  `mission-init.sh` の第 4 引数として渡す。`mission-init.sh` は内部で `self-improve-check.sh` を呼び、
  新ミッションの対象集合が既知の過去ミッション（`self-improve-registry.tsv`）の対象集合の**部分集合**に
  なっていないかを機械的に判定し、結果を `@fix_plan.md` の `## Out of Scope` 節に自動追記する（主観的な
  「重複していない気がする」判断ではなく集合演算、SWARM.md §5「学びの3段階モデル」段階3＝機械化に対応）。
  - **Interactive**: `OVERLAP` と判定されたら、Phase 2 PLAN へ進む前に人間へ提示し、続行するか差別化角度
    を明確にするか確認する（Interactive はもともと人間がその場にいる前提であり、Mission の自律性原則とは
    矛盾しない）。
  - **Mission**: **停止しない**。`@fix_plan.md` の `## Out of Scope` に自動追記された
    `differentiation angle: <TBD>` を Phase 2 PLAN 開始前に埋め、GATE（Phase 5）で人間 /
    `/swarm-architect` に提示する。自律実行を止めるものではなく、非ブロッキングな記録を強制するのみ。

- Interactive/Mission では TaskCreate でフェーズ単位のタスクを登録する（進捗の可視化）。
- ワークスペース隔離（旧 dig Phase 0）: サブモジュール/worktree で既に隔離されているか確認する:

  ```bash
  GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
  GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
  ```

  `GIT_DIR == GIT_COMMON` かつタスクが 2 件以上並列になる見込みなら、タスクごとに worktree を割り当てる
  （`swarm-implement/scripts/worktree-alloc.sh`）。単独タスクなら main tree 直接編集でよい。

- **ベースラインテスト**（Interactive/Mission のみ）: 既存の失敗があるかを先に確認し、あれば人間に
  「既存失敗 N 件、続行するか」を確認してから進める。

## Phase 1: EXPLORE

- **Quick**: スキップ（Phase 2 も簡略化して直接 EXECUTE へ）。
- **Interactive**: 単一の Haiku Explore Agent を dispatch し、JSON サマリーのみ受け取る
  （codegraph_search / graphify query / 変更対象とテストファイルのマッピング）。フルログは受け取らない。
- **Mission**: `swarm-explore` を Skill 起動。Haiku 群（`model: haiku`）→ 秘書（`model: sonnet`）の順は
  skill 側が強制する。成果物 = 秘書レポート（Priority Queue + Root Causes）。`@fix_plan.md` の
  `## Secretary Report` 節に貼り付けて永続化する。1 ミッション原則 1 回、再探索は差分入力で範囲を絞る。

## Phase 2: PLAN（+ 設計インタビュー）

1. **自動解決**: codegraph/graphify で先に解決できることは解決する（類似実装の有無・テスト戦略・
   後方互換性制約・パフォーマンス要件）。解決済みは人間への質問から除外する。
2. **ギャップが残る場合の分岐**:
   - **Interactive**（人間がその場にいる想定）: 対話的設計インタビューを行う（旧 dig Phase 2 相当）。
     - 質問前に必ず関連コードを読む。1 回に 1〜3 個の関連質問をまとめて聞く。外部ライブラリ情報が
       必要なら WebSearch で先に調べてから質問する。
     - **質問の具体化ルール**: 「設計はどうしますか？」のようなオープン質問は禁止。選択肢・具体例を
       提示する（例:「エラー時は `Result<T, E>` を返す/パニックする/ログのみ、のどれを想定していますか？」）。
     - **優先度順**: (1) 技術的設計判断（ライブラリ・データ構造・API 設計）→ (2) ビジネス要件（エッジケース・
       エラー時挙動・成功/失敗基準）→ (3) 既存コード整合性（型/API 互換性・命名規則）→ (4) 実装具体性
       （変更対象ファイル・テスト戦略）。
     - 終了条件: 全観点で情報が揃う、またはユーザーが終了意思を示す。
     - **設計提案**: 2-3 アプローチを提示し（概要・メリット・デメリット）、推奨案と理由を添える。
       スコープ過大ならサブシステムに分解し最初のものだけ設計する。
     - **ユーザー承認なしに Phase 3 へ進まない。**
   - **Mission**（人間不在の自律実行が前提）: 対話的インタビューはしない。ギャップは `/swarm-architect`
     招集で解く（提案書形式、人間の応答待ちでループを止めない設計）。
3. 秘書レポート/Explore 結果を実装タスクへ変換し、`@fix_plan.md` の `## Tasks` テーブルに列挙する
   （1 タスク = 1 worktree = 1 task-id。依存順を `depends` 列に明記。Quick はこのテーブル化自体を省略）。
   秘書レポートの Priority Queue が付与した `mast` 列（design/misalignment/verification）は
   `note` 列にそのまま転記する — Tasks テーブルに専用列はないため、ここで失わせない
   （CHECKPOINT が同じ MAST 3 分類でルーティングするため、Checker の再判定前に手がかりとして使える）。
4. 各タスクに **domain タグ**を付ける（例: `go-core` / `rust-core` / `k8s-infra` / `docker-eng`）。domain は
   Maker への専門コンテキスト（該当言語の skill: golang-patterns / rust-patterns / k8s-patterns 等）を
   決めるためのルーティング情報であり、モデル階層（SWARM.md §1）とは独立の軸。
5. アーキテクチャ判断が未確定の項目は着手せず `blocked(design)` とし、人間へ `/swarm-architect` 招集を
   要請する。設計待ちと独立なタスクは先へ進める。
6. **コア設計変更の事前ゲート（プロアクティブ）**: タスクの summary/domain がコアアーキテクチャに触れると
   分かっている時点で EXECUTE 前に `/swarm-architect` 招集を要請する。対象例: vald の VStream /
   パーティショニング方式 / ストレージ階層 / インデックス構造そのものの変更、dotfiles の Makefile.d
   構造・hooks の検証ロジックそのものの変更。末端のバグ修正・パラメータ調整はゲート対象外。

## Phase 3: EXECUTE

`swarm-implement` に委譲する。複雑度ガード（旧 dig の trivial/simple/standard/complex 分類）・
TDAD の必須化条件・Fixer/Circuit Breaker は `swarm-implement` skill 側に実装されている。

- **独立タスクは最大 3 並列**まで（Checker の品質とレビュー可能性を落とさないため。旧 dig の上限 5 は
  レビュー品質の実証知見により本基盤では採用しない）。4 並列以上は禁止。
- Maker/Checker は同一ベンダー系列 (intra-family) で verifier 独立性に理論的限界があるため
  （SWARM.md §2）、`swarm-implement` の決定論的検証（hook/lint/test）の結果を Checker 判定より優先させる。
- 各タスク終了（成功・予算超過とも）ごとに `@fix_plan.md` の該当行を更新: `done` / `blocked(budget)` /
  `blocked(design)` / `blocked(spec)`（Interactive/Mission のみ。Quick は状態ファイルを持たないため
  会話内で完結を報告する）。

## Phase 4: CHECKPOINT — ループ制御とエスカレーション行列

各タスク完了ごとに、失敗があれば MAST 3 分類（SWARM.md §2）でまず切り分けてから評価する:

| MAST 分類                 | 意味                                      | CHECKPOINT の扱い                                               |
| ------------------------- | ----------------------------------------- | --------------------------------------------------------------- |
| system design issue       | 仕様・役割定義の不備                      | `blocked(design)` にして `/swarm-architect` 招集を検討          |
| inter-agent misalignment  | 秘書レポートと Maker/Checker の前提のズレ | `blocked(spec)` にして PLAN のタスク分割・depends を見直す      |
| task verification failure | 検証不足・時期尚早な終了                  | Checker/hook の検証強化。Checker だけを強めても直らない点に注意 |

| 状況                                                                                             | 行動                                                                                          |
| ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------- |
| 同一エラーに同一対処を 2 回試みようとした                                                        | 禁止。別仮説へ切替え、`AGENTS.md` に記録し、2 回目の学びは機械化チェックへ昇格（SWARM.md §5） |
| `swarm-implement` の Fixer トリガー条件成立（3 試行・Permanent エラー・失敗シグネチャ 2 回一致） | Fixer（`debugger` サブエージェント）へ委譲。同じ対処を漫然と繰り返さない                      |
| タスクが 5 試行超過（BUDGET_EXCEEDED）                                                           | `blocked(budget)` にして**次のタスクへ進む**（ミッション全体を止めない）                      |
| `blocked` が全タスクの過半、または残タスクが全て blocked に依存                                  | ループ停止 → ESCALATE                                                                         |
| Stop hook から 5 回差し戻し（エスカレーション通知）                                              | ループ停止 → ESCALATE                                                                         |
| 全タスク done                                                                                    | GATE へ                                                                                       |

**ESCALATE**: `@fix_plan.md` に「全 blocked タスクの失敗軌跡・試した仮説・次候補（MAST 分類つき）」を書き、
`AGENTS.md` に軌跡を追記し、人間へ報告して停止する。難局の性質が設計問題（system design）なら
`/swarm-architect` 招集を、仕様・分担の齟齬（inter-agent misalignment）なら PLAN のやり直しを、
環境問題（権限・パッケージ導入等）なら具体的な人間の作業を明記して要請する。
**エスカレーションなしに同じループを回し続けることを禁止する。**

## Phase 5: GATE → REPORT

1. 人間へ `/swarm-release-gate` の招集を要請する（自分でマージしない）。決定論的検証（`verify.sh`）が全パス
   していても、それは**既知の回帰を防ぐだけで新規の失敗モードを事前に予見しない**（SWARM.md §8）。
   したがって GATE では「全チェック green」を安全の証明として扱わず、diff の要約・影響範囲・新規性の
   高い変更点を人間が一目でパターンマッチできる形で提示する。`@fix_plan.md` の `## Out of Scope` 節に
   `self-improve-check.sh` による `OVERLAP` 記録（過去ミッション slug・differentiation angle）があれば、
   それもこの提示に含める。
2. **完了時の選択肢提示**（旧 dig のブランチ完了メニュー）: `swarm-release-gate` 承認後、人間に選ばせる:

   ```
   1. <base-branch> にローカルマージ  2. Push + PR 作成  3. このまま保持  4. 破棄
   ```

3. 承認・統合後: `AGENTS.md` へ軌跡追記（2 回目の学びは機械化チェックへ昇格済みか確認）→
   worktree 回収（`worktree-release.sh`、Option 1/4 のみ、必ずメインリポジトリルートから実行。
   Option 1〈ローカルマージ済み〉は素の呼び出しでブランチを保持、Option 4〈破棄〉は
   `worktree-release.sh <worktree-path> --delete-branch` でブランチも削除し `swarm/*` の残骸を残さない）→
   ミッション予算カウンタ掃除（`budget-guard.sh --reset`）→ `@fix_plan.md` を削除またはアーカイブ →
   最終レポート（done/blocked 一覧・学び・残課題）を提示して終了。
4. **Quick モードの完了処理**: `@fix_plan.md` が無いため、テスト全通過を確認し、変更要約を提示して終了。
   ワークツリークリーンアップ・軌跡追記は変更が非自明だった場合のみ行う。

## ループ不変条件（全 Phase 共通）

- モデルルーティングは SWARM.md §1 の表を Agent/Workflow の `model` パラメータで**明示**する。
- Haiku 生ログを上位層へ流さない。層間の受け渡しは構造化レポートのみ（Observation Masking）。
- 「完了しました」の自己申告を状態遷移の根拠にしない。根拠は Checker 判定・lint/test の実行結果・
  Stop hook 通過・**今このメッセージ内で実行したテスト結果**のみ（過去の実行結果を信頼しない）。
- `@fix_plan.md` が唯一の進行状態（Quick を除く）。コンテキスト圧縮・セッション断で失われて困る情報は
  即座にそこへ書く。
- 一時ファイルはリポジトリルートではなく `/tmp/` 以下のみに置く。
- 隣接コードの改善・整形・リファクタは行わない。変更行はすべてタスクにトレース可能なこと（Surgical changes）。
