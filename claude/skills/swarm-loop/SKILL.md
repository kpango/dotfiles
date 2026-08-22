---
name: swarm-loop
description: >-
  自走ループの 0 段（線形状態機械）エントリポイント（旧 dig を完全統合）。1 行の typo 修正から 100 体規模の
  Haiku 探索を伴う大規模自律ミッションまで、規模を自動判定して同じ状態機械で処理する。姉妹 skill:
  `swarm-graph`（1 段・DAG フロンティア実行）／`swarm-meta`（2 段・メタ層、いずれも人間招集限定）。
  `swarm-graph` の GRAPH-FIT UNFIT フォールバック・`swarm-meta` の DISPATCH からは、Skill tool 経由では
  なく本 SKILL.md を Read して同じ状態機械へインライン合流する委譲経路がある。1 行の typo 修正から
  100 体規模の Haiku 探索を伴う大規模自律ミッションまで、常にこの skill 一つを起点にする。
  トリガー: 「実装して」「修正して」「調べて直して」「自律で進めて」「/swarm-loop」
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
    ListAgents,
    SendMessage,
  ]
user-invocable: true
disable-model-invocation: true
---

# swarm-loop — 統合自走ループ

全層を貫く自走ループの状態機械。人間の介入点は「起動」「Interactive モードの設計インタビュー応答」
「/swarm-architect 招集」「/swarm-release-gate 承認」のみ。

```
SCALE判定 ─▶ INIT ─▶ EXPLORE ─▶ PLAN(+設計インタビュー) ─▶ EXECUTE ─▶ CHECKPOINT ─┬─▶ 残タスク: EXECUTE へ
                                                                              ├─▶ 難局: ESCALATE ──▶ 人間
                                                                              └─▶ 完了: ADVERSARIAL REVIEW ─▶ GATE ──▶ 人間承認 ──▶ REPORT
```

`旧 dig` の Quick/Research/Full モード判定・対話的設計インタビュー・TDAD Iron Law・複雑度ガードは、
すべて以下の Phase -1（SCALE 判定）と各 Phase 内の分岐として統合済み（`dig` skill 自体は削除済み）。

姉妹 skill からのインライン合流委譲経路（`swarm-graph` GRAPH-FIT UNFIT フォールバック・`swarm-meta`
DISPATCH）は frontmatter の説明のとおり（詳細は SWARM.md §0）。

開始前に `~/.claude/SWARM.md` を Read する（CLAUDE.md の常時 import ではなく本 skill が個別に
読み込む設計。統治規約・verifier 独立性原則・MAST 分類等、本 skill 全体の前提はそこにある）。

## Phase -1: SCALE 判定（起動直後、必ず最初に実行）

ゴールの文言・既知の変更規模から自動判定する。不明な場合のみ人間に 1 問確認する
（「Quick(即実行)/Interactive(設計相談しながら)/Mission(大規模・自律)のどれで進めますか？」）。
**判定は昇格のみ許可し、降格はしない**（Phase 1 の結果や試行の失敗で規模が想定より大きいと分かったら
即座に昇格する。小さいと分かっても格下げしない — 安全側に倒す）。

| モード          | 判定条件                                                                                       | 適用される規模                                                                                                                                                                         |
| --------------- | ---------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Quick**       | バグ修正・既知ファイルへの小変更・1 ファイル 15 行以下・新規ロジックなし                       | 専用ミッションworktreeを割当・EXPLORE 省略・設計インタビュー省略・`@fix_plan.md` 省略。単一 Maker+Checker を現セッション内で完結                                                       |
| **Interactive** | 新機能・設計判断が要る変更だが、単一セッションで完結し人間がその場で応答できる                 | 専用ミッションworktree割当(継承あり)・EXPLORE は Haiku 1 体・PLAN で設計インタビュー実施・並列上限 3・`@fix_plan.md` は使うが軽量                                                      |
| **Mission**     | スコープ不明・複数システム・大規模・「自律で」「swarm で」等の明示・複数セッションに跨る見込み | 専用ミッションworktree割当(継承あり)・EXPLORE は Haiku 100 体（`swarm-explore`）・PLAN は秘書レポート駆動＋設計は `/swarm-architect` 招集・並列上限 3・`@fix_plan.md` が必須の永続状態 |

**モード昇格チェック**（Phase 1 EXPLORE 終了時）: 影響ファイル数が 6 以上判明したら Mission へ昇格
（測定基準: `git diff --name-only` 相当の実際の変更対象ファイル数。影響範囲の推定・間接影響ファイルは含めない）。
2 以下しか無いと分かっても Quick 以外からの降格はしない。

## Phase 0: INIT

**ミッションworktree割当（全スケール共通、最初に実行）**:

- **Quick**: 常に新規ミッションworktreeを割り当てる（再開ロジックは無し）:

  ```bash
  ~/.claude/skills/swarm-implement/scripts/mission-worktree-alloc.sh quick <slug>
  ```

  以降このworktreeをカレントとして Phase 3 (EXECUTE) の軽量パスへ直接進む（EXPLORE省略・設計
  インタビュー省略・`@fix_plan.md`省略）。main treeは触れない。

- **Interactive/Mission — 再開判定**: ゴール文言から slug を導出し（kebab-case・48文字以内、
  `mission-init.sh` と同じ正規化）、既存ミッションworktreeの有無を確認する:

  ```bash
  git worktree list | grep -E '\.claude/worktrees/(interactive|mission)-'"${slug}"'-'
  ```

  見つかれば再開: そのworktreeパスへ切り替え、状態を復元する:

  ```bash
  ~/.claude/skills/swarm-loop/scripts/loop-status.sh <mission-slug>
  ```

  新規worktreeは作らない。

- **Interactive/Mission — 新規開始**: 見つからなければ新規ミッションworktreeを割り当てる:

  ```bash
  ~/.claude/skills/swarm-implement/scripts/mission-worktree-alloc.sh <interactive|mission> <slug> [base-ref=HEAD]
  ```

  `<repo>/.claude/worktrees/<scale>-<slug>-<timestamp>` に worktree・`swarm-<scale>/<slug>-<timestamp>`
  ブランチを作成し、絶対パスを返す。**以降の全 Phase はこのミッションworktreeをカレントとして進行する**
  （main tree は他の並行ミッションのために触れないまま維持する — これが複数ミッションを同一クローンへ
  同時実行できる前提）。起動元ツリー（通常 main tree の現在のブランチ）に既存の `@fix_plan.md` があれば
  `@fix_plan.md.inherited` として新worktreeへ自動ステージングされる（**Plan継承**、下記参照）。

  軌跡ログ（`swarm-implement/scripts/agents-log-lib.sh` が返すパス）を読み（過去の学びの継承）、
  新規worktree内で初期化:

  ```bash
  ~/.claude/skills/swarm-loop/scripts/mission-init.sh <mission-slug> "<目標 1 文>" <interactive|mission> [self-improve-targets] [depth]
  ```

  `[depth]`: ネストされた `/swarm-loop` の深さ（省略時 0、通常はユーザーが直接指定する必要はない）。

  `@fix_plan.md` の骨子が生成される。目標・完了条件（Definition of Done）・スコープ外を必ず埋める。
  骨子には予算・並列数上限等の `## Invariants` スナップショットも含まれる（ConstraintRot対策
  arXiv:2606.22528、単一preprint。コンテキスト圧縮後の規範復元は `@fix_plan.md` の再読込に依る）。
  `mission-init.sh` が状態ディレクトリ作成後（`@fix_plan.md` 書き込み等）に失敗した場合の自動ロールバックは
  ないため、`$HOME/.claude/session-data/swarm/missions/<slug>` の残骸を手動確認してから再実行する。

  **Plan継承**: 起動元ツリーに既存の `@fix_plan.md` があった場合、`mission-init.sh` が新骨子の
  `## Tasks` テーブル直後へ継承元の Task 行を HTML コメント（継承日）付きで挿入する。ヘッダ
  （goal/scale/Invariants 等）は継承せず今回のミッションの値を正とする。

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
- **タスク単位のworktree隔離（既存規約、ミッションworktree内へ再配置）**: ミッションworktree内で
  タスクが2件以上並列になる見込みなら、タスクごとに `swarm-implement/scripts/worktree-alloc.sh` で
  さらに隔離済みworktreeを割り当てる（ミッションworktree配下の `.claude/worktrees/` にネストする —
  `worktree-alloc.sh` は cwd を基準に解決するため、ミッションworktree内から呼べば自動的にネストする）。
  単独タスクならミッションworktree直下で直接編集してよい。
- **ベースラインテスト**（Interactive/Mission のみ）: 既存の失敗があるかを先に確認し、あれば人間に
  「既存失敗 N 件、続行するか」を確認してから進める。
- **init broadcast（任意・非ブロッキング）**: `swarm-relay/SKILL.md` §2 プロトコルに従い、`ListAgents`
  で同一 repo 上で動作中の他セッションが見つかれば `init` メッセージを送ってよい（ミッションworktree化
  により同一main treeのgit index/HEADを取り合う衝突は構造的に大幅に減るが、GATE Option1のマージ時
  衝突検知とクロスリポジトリの学び伝播という残存価値は変わらない。cross-session messaging 非対応環境・
  宛先無しではミッション開始を止めない、詳細は `swarm-relay/SKILL.md` §5）。

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
     - インタビューで得た回答のうち、今回のミッション限りでなく今後も通用する人間の恒久的な好み・
       制約・運用ポリシーがあれば、Phase 5 GATE を待たずこの場で `Skill(swarm-memory-sync)` を呼ぶ
       （feedback/user type が主）。決定論的な重複チェック（`memory-guard.sh`）を経由するため、
       auto-memory への直接反映は行わない。
   - **Mission**（人間不在の自律実行が前提）: 対話的インタビューはしない。設計ギャップはまず Fable
     スポット設計スクリーニング（SWARM.md §1 トリガー 2 の PLAN 段階適用。`budget-guard.sh --fable`
     の許可時のみ）で一次診断し、(a) 自己解決可能（仕様の読み違い・タスク分割の問題等）なら PLAN に
     反映して進む、(b) 本物の設計問題なら該当タスクを `blocked(design)` とし人間へ `/swarm-architect`
     （フル設計モード）招集を**要請**する（応答待ちでループは止めず、下記 5. と同様に独立タスクを先へ
     進める）。`FABLE_BUDGET_EXCEEDED` 時は (b) へ直行。スポット診断が招集を代替することはない。
3. 秘書レポート/Explore 結果を実装タスクへ変換し、`@fix_plan.md` の `## Tasks` テーブルに列挙する
   （1 タスク = 1 worktree = 1 task-id。依存順を `depends` 列に明記。Quick はこのテーブル化自体を省略）。
   秘書レポートの Priority Queue が付与した `mast` 列（design/misalignment/verification）は
   `note` 列にそのまま転記する — Tasks テーブルに専用列はないため、ここで失わせない
   （CHECKPOINT が同じ MAST 3 分類でルーティングするため、Checker の再判定前に手がかりとして使える）。
   テーブル確定時にタスク数を再確認し、6 件以上なら Phase 1 の昇格チェックと同様に Mission へ昇格する
   （昇格のみ・降格しない）。
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
- **並列ディスパッチ前の独立性事前チェック（プロアクティブ）**: 2 タスク以上を同一バッチで並列実行する前に、
  `impact-scope.md` の完全判定手順（変更予定 file/symbol の列挙 → 参照元 grep → impact 分類）を各タスクに
  対して行い、対象 file/symbol が重複するタスクの組がないか確認する。重複が見つかった組は
  `[parallel-task:<id>]` マーカーを付けず逐次実行に降格する。Phase 5 の統合 consistency-verify（事後検出）
  はこの事前チェックを代替しない — PLAN 時点の想定に基づく推定であり、実装が進むにつれ事前に見えなかった
  依存が生まれうるため、事後検証は引き続き必須のまま残す（`SWARM_REFERENCES.md` 参照）。
- Maker/Checker は同一ベンダー系列 (intra-family) で verifier 独立性に理論的限界があるため
  （SWARM.md §2）、`swarm-implement` の決定論的検証（hook/lint/test）の結果を Checker 判定より優先させる。
- 高難易度・状況判断が鍵の局面での **Fable スポットルート**のうち、Fixer 失敗後の最終診断（トリガー 1）・
  `complex` 計画レビュー（トリガー 3）・Checker と決定論的検証の矛盾診断（トリガー 4）は `swarm-implement`
  側に配線されている（SWARM.md §1 スポット判断層）。トリガー 2（`blocked(design)` 前スクリーニング）のみ
  本 skill の CHECKPOINT が担う。いずれも `budget-guard.sh --fable` の許可（1 タスク 1 回・1 ミッション
  2 回）なしに Fable を起動しない。
- 各タスク終了（成功・予算超過とも）ごとに `@fix_plan.md` の該当行を更新: `done` / `blocked(budget)` /
  `blocked(design)` / `blocked(spec)`（Interactive/Mission のみ。Quick は状態ファイルを持たないため
  会話内で完結を報告する）。更新は **swarm-loop 本体（main tree 常駐のオーケストレーター）のみ**が行い、
  worktree 内で動作する Maker/Checker は `@fix_plan.md` に一切触れない（single-writer 規約。
  swarm-graph §6 と同一）。

## Phase 4: CHECKPOINT — ループ制御とエスカレーション行列

各タスク完了ごとに、失敗があれば MAST 3 分類（SWARM.md §2）でまず切り分けてから評価する:

| MAST 分類                 | 意味                                      | CHECKPOINT の扱い                                                                                    |
| ------------------------- | ----------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| system design issue       | 仕様・役割定義の不備                      | Fable スポット設計スクリーニング（下記）を経てから `blocked(design)` → `/swarm-architect` 招集を検討 |
| inter-agent misalignment  | 秘書レポートと Maker/Checker の前提のズレ | `blocked(spec)` にして PLAN のタスク分割・depends を見直す                                           |
| task verification failure | 検証不足・時期尚早な終了                  | Checker/hook の検証強化。Checker だけを強めても直らない点に注意                                      |

**fault-side の補助判定（単一preprint、参考情報）**: 「task verification failure」に分類した
ブロックが、Checker/hookをいくら強化しても解消しない環境要因・グレーダー側要因（テスト環境の
非決定性、外部依存の不整合等）に起因する可能性がある場合は、Checkerの追加起動より先に環境要因を
切り分ける（arXiv:2607.28802 は失敗の大半をモデル側に帰属可能と報告する一方、環境/グレーダー側
要因はモデル改善では解消しないと示す）。

**Fable スポット設計スクリーニング（SWARM.md §1 スポット判断層・トリガー 2）**: system design issue と
分類したタスクを `blocked(design)` にする前に、`budget-guard.sh --fable <task-id> --mission=<slug>` が
許可すれば `swarm-architect` スポット診断モードで一次診断を 1 回だけ行う。診断書が (a) 自己解決可能
（実は仕様の読み違い・タスク分割の問題等）と示せば該当タスクの次試行の入力に反映し、(b) 本物の設計問題と
示せば `blocked(design)` の根拠・人間への `/swarm-architect`（フル設計モード）招集要請の判断材料として
`@fix_plan.md` に添付する。`FABLE_BUDGET_EXCEEDED` の場合は従来どおり直接 `blocked(design)` にする
（スクリーニングは招集の代替ではなく前置フィルタ）。`/swarm-architect`（フル設計モード）での解決後は、
該当タスクの `@fix_plan.md` 上の status を `pending` に戻し EXECUTE を再開する。grant トークンが TTL
（600s）内に消費されず失効した場合は、`--mission` を付けずに `budget-guard.sh --reset <task-id>` でタスク側
カウンタのみをクリアしてから `--fable <task-id> --mission=<slug>` を再実行する（`--mission` 付き reset は
ミッション全体の fable 予算を巻き戻すため使わない）。予算カウンタファイルが非数値等で破損し
`budget-guard.sh` がエラー終了する場合も、同様に該当タスクを `--reset` してから再実行する。

| 状況                                                                                             | 行動                                                                                             |
| ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| 同一エラーに同一対処を 2 回試みようとした                                                        | 禁止。別仮説へ切替え、軌跡ログに記録し、2 回目の学びは機械化チェックへ昇格（SWARM.md §5）        |
| `swarm-implement` の Fixer トリガー条件成立（3 試行・Permanent エラー・失敗シグネチャ 2 回一致） | Fixer（`debugger` サブエージェント）へ委譲。同じ対処を漫然と繰り返さない                         |
| タスクが 5 試行超過（BUDGET_EXCEEDED）                                                           | `blocked(budget)` にして**次のタスクへ進む**（ミッション全体を止めない）                         |
| `blocked` タスク間に循環依存または推移依存（A→B→C）がある                                        | 依存チェーン全体を根本原因タスクの MAST 分類・行動へ集約し、個別タスクごとに重複 ESCALATE しない |
| `blocked` が全タスクの過半、または残タスクが全て blocked に依存                                  | ループ停止 → ESCALATE                                                                            |
| Stop hook から 5 回差し戻し（エスカレーション通知）                                              | ループ停止 → ESCALATE                                                                            |
| 全タスク done                                                                                    | Phase 4.5 ADVERSARIAL REVIEW へ                                                                  |

**ESCALATE**: `@fix_plan.md` に「全 blocked タスクの失敗軌跡・試した仮説・次候補（MAST 分類つき）」を書き、
軌跡ログに追記し、人間へ報告して停止する。難局の性質が設計問題（system design）なら
`/swarm-architect` 招集を、仕様・分担の齟齬（inter-agent misalignment）なら PLAN のやり直しを、
環境問題（権限・パッケージ導入等）なら具体的な人間の作業を明記して要請する。
**エスカレーションなしに同じループを回し続けることを禁止する。**

## Phase 4.5: ADVERSARIAL REVIEW — 8 Agent 敵対的レビュー（Quick はスキップ）

Phase 4 CHECKPOINT で全タスクが `done` に達した時点（上記表「全タスク done」行）で、GATE の前に本 Phase を
挿入する。**Quick はスキップし直接 GATE へ進む**（Phase -1 の Quick 定義そのものが対象 — 1 ファイル 15 行
以下の変更に 8 Agent の重厚な敵対的レビューは不要。`swarm-evolve` 自動証跡収集を Quick が省略するのと同じ
扱い）。

**対象 diff の準備**: `SWARM.md §2「Phase 4.5/G4.5 diff-supply プロトコル」`に従う（一時ファイル保存・
信頼境界・完全性の自己検証・最小権限の詳細は同項目を参照し、ここでは再掲しない）。ミッションworktree内で
`git diff $(git merge-base HEAD <base-branch>)..HEAD` を取得し、一時ファイルへ保存し、そのファイルパスと
変更ファイル数（`--stat` の要約行から読み取る）を下記の**全 8 Agent へ渡す**。コンテキストに収まらない
規模なら、変更ファイル一覧のみ（`git diff --name-only <base>..HEAD`）を同様に保存する。

**8 Agent**（全て `model: sonnet` 明示。4体は `Read`/`Grep`/`Glob` のみ — 供給されたファイルパスを
`Read` で読む。残り4体〈security/perf-simd/shell-config/infra-config〉は追加で `Bash` を持つ —
security/perf-simd は `Bash` を `git log`/`git blame`/`grep -r` 等の読み取り専用の履歴調査・
クロスファイルパターン検索に使い、shell-config/infra-config は `Bash` を shellcheck/shfmt や
`nix-instantiate --parse`/`luac -p` 等の parse-only 静的解析ツール実行に限定する（git は使わない）。
これは各 Agent 定義の本文指示による運用上の制約であり、Claude Code の `tools`
frontmatter 自体はコマンド単位の制限を提供しないため機構的な強制ではない点に注意する。信頼境界・
完全性の自己検証・最小権限の詳細は SWARM.md §2 参照。具体的な tools 構成は各 Agent 定義側の
frontmatter が管理する）:

| #   | `subagent_type`                     | レビュー観点                     | 既存 agent との関係                                    |
| --- | ----------------------------------- | -------------------------------- | ------------------------------------------------------ |
| 1   | `security-adversarial-reviewer`     | セキュリティ                     | `security-audit` と二段階防御                          |
| 2   | `architecture-adversarial-reviewer` | アーキテクチャ整合性             | 新規領域                                               |
| 3   | `perf-simd-adversarial-reviewer`    | 性能・SIMD                       | `perf-analyzer`/`ann-perf-engineer` と二段階防御       |
| 4   | `code-quality-adversarial-reviewer` | コード品質                       | `code-reviewer` と二段階防御                           |
| 5   | `docs-comment-adversarial-reviewer` | 技術文書・コメント品質           | 新規領域                                               |
| 6   | `systems-lang-adversarial-reviewer` | Go/Rust/C++ 言語仕様             | `go-expert`/`rust-expert`/`code-reviewer` と二段階防御 |
| 7   | `shell-config-adversarial-reviewer` | Shell/ZSH/Makefile 言語仕様      | 新規領域                                               |
| 8   | `infra-config-adversarial-reviewer` | Nix/Lua/Yaml/Json 構文・スキーマ | 新規領域（`vald-reviewer` とは非重複）                 |

**実行順序（3 並列プール、8 Agent をキューとして投入。SWARM.md §1「最大 3 並列」、
`swarm-parallel-gate.sh` が機械強制する既存制約にそのまま従う）**:

8 Agent（security, architecture, perf-simd, code-quality, docs-comment, systems-lang, shell-config,
infra-config）をキューに積み、先頭 3 件を並列起動する。各 Agent 呼び出しの prompt に
`[parallel-task:review-<agent短縮名>-<mission-slug>]` マーカーを含める（`swarm-implement` の既存規約と
同一機構、SWARM.md §1）。いずれか 1 件が完了したら、その task-id について
`~/.claude/skills/swarm-implement/scripts/parallel-gate.sh --release <task-id>` でスロットを解放し、
直ちにキューの次の 1 件を起動する（固定バッチでの一括起動・一括解放は行わない — 8 Agent の実行時間は
一様ではなく、完了したスロットを次バッチまで遊ばせない）。全 8 件が完了するまで繰り返す（3 並列の上限は
`swarm-parallel-gate.sh` が引き続き機械強制する。判定集約契約・8 Agent 全員 PASS 必須は変更しない）。

**判定集約**: 各 Agent の応答末尾の `VERDICT: PASS | FAIL` 行を読む。欠落・停滞時はSWARM.md §2「名前付き
Agent呼び出しの停滞対応」に従う。

- **8 Agent全員がPASSの場合のみ** GATE（Phase 5）へ進む。
- **1つでもFAILがあれば**、FAILしたAgentのFindings(file:line)と、`@fix_plan.md` Tasksテーブルの
  各task-idが変更したファイル一覧（`worktree`列のブランチdiff、または個別タスクworktreeの
  `git diff --name-only`）を突き合わせ、所有task-idを特定する。
  - 一意に1 task-idへ帰属できる場合: そのタスクをPhase 4 CHECKPOINTのMAST分類`task verification
failure`として扱い、次試行の入力にFindingsを反映する（既存のタスク単位試行予算=最大5試行に従う）。
  - 複数task-idに跨る、またはどのtask-idにも一意に帰属できない場合: 推測でtask-idを選ばず、Phase 4の
    既存ESCALATE手順（人間へ報告）に従う。
  - 修正後は**PASS済みのAgentも含め8 Agent全員を再実行**する。
- **Phase 4.5自体の往復上限は1ミッション最大3回**とする（タスク単位の5試行予算とは別枠。帰属不能な
  FAILが続く場合に無限往復しないための安全弁）。3回到達時点で全AgentがPASSしていなければ、Phase 4の
  既存ESCALATE手順に従い人間へ報告して停止する。

**永続化**: 8 Agentの結果とラウンド数を`@fix_plan.md`の新設節`## Adversarial Review`に追記する
（single-writer規約）。

下記「ループ不変条件」節の原則をそのまま継承する。

## Phase 5: GATE → REPORT

1. `Skill(swarm-release-gate)` を自動的に起動する（2026-08-13 変更、`disable-model-invocation: false`
   のため直接呼び出し可能。人間への `/swarm-release-gate` 手動入力は不要 — 明示的に入力してもよいが
   同じ内容を人間主導で実行するだけで結果は同じ）。決定論的検証（`verify.sh`）が全パス
   していても、それは**既知の回帰を防ぐだけで新規の失敗モードを事前に予見しない**（`SWARM_REFERENCES.md`）。
   したがって GATE では「全チェック green」を安全の証明として扱わず、diff の要約・影響範囲・新規性の
   高い変更点を人間が一目でパターンマッチできる形で提示する。`@fix_plan.md` の `## Out of Scope` 節に
   `self-improve-check.sh` による `OVERLAP` 記録（過去ミッション slug・differentiation angle）があれば、
   それもこの提示に含める。fable スポットを消費したミッションでは、`fable-spot-log.jsonl` の該当分
   （発動トリガー・grant/deny・診断書要約）も提示する。
   **統合 consistency-verify（worktree 2 件以上並列時は必須）**: 本ミッションで 2 件以上のタスクを
   worktree 隔離並列実行した場合、個々の Maker/Checker とは独立に、全 worktree ブランチの変更ファイル
   一覧を突き合わせ（`git diff --name-only <base>..<branch>` 等）、同一ファイルへの重複所有権
   （overlap）の有無と、新設ファイルへの相互参照漏れ（他ノードの成果物を参照すべき箇所が未更新の
   まま残っていないか）を確認する統合検証を release-gate 招集の前に実行し、結果（overlap 件数・
   検出した参照漏れ）を上記の提示に含める。overlap を検出した場合は該当ブランチの diff を人間へ
   個別提示し、機械的なマージを前提としない。
   **フォールバック**: 人間が `/swarm-release-gate` を入力せず「続けて」等で応答した場合は、
   `swarm-release-gate/scripts/verify.sh` を Bash で直接実行して生出力を提示し、下記 3. の完了メニューの
   選択を人間の最終承認として扱う（`disable-model-invocation: true` の skill は Skill tool から起動
   できないため。gate の本質は人間の最終判断であり skill 起動の儀式ではない）。フォールバック実行で
   `verify.sh` が失敗を検出した場合は、人間に `/swarm-release-gate` の明示招集かフォールバックの再実行かを
   選ばせる（同一ターンでの無限リトライはしない）。
2. **`swarm-evolve` 自動証跡収集**: `Skill(swarm-evolve)` を内部呼び出しし、証拠収集(Step1)→Drafter(Step2)→
   Checker(Step3)→Checker合格分の人間提示(Step4)まで自動実行する（Step5=適用は人間の個別承認を経てからのみ、
   swarm-evolve 本体の「自動呼び出し時の範囲」節を参照 — 省略不可の原則は変わらない）。Checker 合格分が
   あれば、上記 1. の release-gate 提示と同じ会話ターンで人間に提示する。証拠 0 件・提案 0 件・Checker
   全却下のいずれかであれば非ブロッキングでスキップし、GATE 本来の提示を妨げない。
3. **完了時の選択肢提示**（旧 dig のブランチ完了メニュー）: `swarm-release-gate` 承認後、人間に選ばせる:

   ```
   1. <base-branch> にローカルマージ  2. Push + PR 作成  3. このまま保持  4. 破棄
   ```

   `@fix_plan.md` ヘッダに `- meta-managed: true` があるミッションでは、メニュー提示時に「終了後に
   swarm-meta の M3 RECORD（`harness-record.sh`）を忘れないこと」を併記する。
   **cross-repo handoff（任意）**: `## Escalations / 学び` に他 repo（vald⇔dotfiles）にも関連しうる
   学びがあれば、`swarm-relay/SKILL.md` §4.4 に従い `ListAgents`/`SendMessage` で該当 repo の
   セッションへ伝えてよい（見つからなければ既存の軌跡ログ/auto-memory への記録のみで完結する — 追加の
   即時伝達手段であり必須ではない）。

4. **precommit-check（任意・main tree での commit 直前）**: Option 1（ローカルマージ）でこのミッションが
   main tree に commit する前に、`swarm-relay/SKILL.md` §4.3 に従い `ListAgents` で同一 repo 上の他
   セッションの在席を確認してよい。見つかった場合は自動でブロックせず、人間に警告として提示してから
   続行判断を仰ぐ（git index/HEAD 競合の早期検知。cross-session messaging 非対応環境では no-op で
   劣化しこの手順を単にスキップする）。
   承認・統合後（**順序規定**: 自分でコミットを作る統合〈Option 1 のローカルマージ〉では
   `self-improve-register.sh` 実行をコミット**前**にミッション本体と同一コミットへ含める — 後追い chore
   コミットでの登録漏れ再発防止。軌跡ログは別リポジトリのため同一コミットにはできず、この手順内で
   都度追記・commit する）: 軌跡ログへ追記して commit（2 回目の学びは機械化チェックへ昇格済みか確認）→
   **自己改善ミッション（`self-improve-targets` を指定して `mission-init.sh` した場合のみ）は**
   `~/.claude/skills/swarm-loop/scripts/self-improve-register.sh <slug> <date> <targets>` **を実行して
   `self-improve-registry.tsv` へ登録する（手動追記の失念が 2 回連続で発生したため機械化済み。冪等なので
   再実行しても重複行は作らない）→**
   `Skill(swarm-memory-sync)` を、今回軌跡ログに追記した行 + `@fix_plan.md` の
   `## Escalations / 学び` 節を明示的な入力として渡して呼び、一般化可能なものを auto-memory へ蒸留
   （人間承認不要、ドメイン知識の記録のみで SKILL.md/hooks/SWARM.md 自体は変更しない）→
   worktree 回収を `~/.claude/skills/swarm-implement/scripts/mission-cleanup.sh <slug>
--release-worktrees [--delete-branches]` で一括実行する（Option 1/4 のみ、必ずミッションworktree
   ルートから実行。**タスク単位のネストworktreeのみが対象** — ミッションworktree自体は下記で別途
   回収する。Option 1〈ローカルマージ済み〉は`--delete-branches`無しでブランチを保持、
   Option 4〈破棄〉は`--delete-branches`付きでブランチも削除し `swarm/*` の残骸を残さない。
   Tasks節から全task-id/worktreeを自動抽出するため個別呼び出しは不要）→
   **ミッションworktree自体の統合・回収**（タスク単位worktree回収の**後**に実行 — ネストworktreeが
   残った状態でミッションworktreeを削除すると、その実体ディレクトリも失われgit worktreeメタデータが
   danglingになる）:
   - Option 1（ローカルマージ）: main treeへ戻り、ミッションブランチ（`swarm-<scale>/<slug>-<ts>`）を
     `<base-branch>` へマージしてから `worktree-release.sh <mission-worktree-path>`（ブランチ保持）で
     ミッションworktreeを回収する。
   - Option 2（Push + PR）: ミッションブランチをpushしPR作成後、
     `worktree-release.sh <mission-worktree-path>`（ブランチ保持 — PR/remoteが参照するため削除しない）
     でミッションworktreeを回収する。
   - Option 3（このまま保持）: ミッションworktree・ブランチとも回収しない（次回同じslugでの
     `/swarm-loop`等の再開判定がこのworktreeを見つけてresumeする）。
   - Option 4（破棄）: `worktree-release.sh <mission-worktree-path> --delete-branch` でミッション
     worktreeとブランチを両方削除する。
     ミッション予算カウンタ掃除を `~/.claude/skills/swarm-implement/scripts/mission-cleanup.sh <slug>
--budget-only` で一括実行する（Tasks テーブル全 task-id の `budget-guard.sh --reset` を1スクリプトへ
     集約、`--mission`は自動付与。fable カウンタ・未消費 grant も掃除されるが、`fable-spot-log.jsonl` は
     観測記録のため削除しない。**Option 2/3では本手順のみ実行し、上記のworktree回収手順は実行しない**）→
     `@fix_plan.md` を削除またはアーカイブ →
     最終レポート（done/blocked 一覧・学び・残課題・auto-memory 反映件数）を提示して終了。
5. **Quick モードの完了処理**: `@fix_plan.md` が無いため、テスト全通過を確認し、変更要約を提示する。
   ミッションworktreeは常に存在するため、上記 3. と同じ完了メニュー（1.ローカルマージ 2.Push+PR 3.保持 4.破棄）を提示し、選択に応じて上記 4. の「ミッションworktree自体の統合・回収」手順のみを
   実行する（タスク単位worktree回収・budget掃除・軌跡ログ追記は対象外 — Quickはそれらの状態を
   持たない）。軌跡追記は変更が非自明だった場合のみ行う。Quick は規模上 `swarm-evolve` 自動証跡収集
   (上記 2.)も行わない（1 ファイル 15 行以下の変更が対象のため証跡が薄く、コスト対効果が低い）。

## ループ不変条件（全 Phase 共通）

- モデルルーティングは SWARM.md §1 の表を Agent/Workflow の `model` パラメータで**明示**する。Fable の
  スポット利用は §1 スポット判断層の発動 4 条件に合致し `budget-guard.sh --fable` が許可した場合のみ
  （1 タスク 1 回・1 ミッション 2 回）。Fixer（debugger）は `model: sonnet` を明示し、暗黙のセッション
  モデル継承で Fable を消費しない。
- Haiku 生ログを上位層へ流さない。層間の受け渡しは構造化レポートのみ（Observation Masking）。
- 「完了しました」の自己申告を状態遷移の根拠にしない。根拠は Checker 判定・lint/test の実行結果・
  Stop hook 通過・**今このメッセージ内で実行したテスト結果**のみ（過去の実行結果を信頼しない）。
- `@fix_plan.md` が唯一の進行状態（Quick を除く）。コンテキスト圧縮・セッション断で失われて困る情報は
  即座にそこへ書く。
- 一時ファイルはリポジトリルートではなく `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/` 以下に置く
  （セッションスコープ。他セッションの一時ファイルと混在させない）。却下・保留分の evolve-proposals 等、
  セッションを跨いで参照する必要があるものに限り `$HOME/.claude/session-data/swarm/` 配下への配置を認める。
- 隣接コードの改善・整形・リファクタは行わない。変更行はすべてタスクにトレース可能なこと（Surgical changes）。

## Memory Protocol（Skill 自己メンテナンス、軌跡ログとは別軸）

軌跡ログ/`@fix_plan.md`（Phase 5 参照）は**プロジェクト単位**のミッション軌跡であり、個々のタスクの
学びを記録する。これとは別に、`~/.claude/skill-memory/swarm-loop/MEMORY.md` には**本 skill 自体の
運用パターン**（SCALE 判定が実態と乖離した傾向、CHECKPOINT での MAST 分類の傾向等、skill 運用一般の
知見）を蓄積する。Phase 0 開始時に存在すれば読み、判断材料にする。存在しなければ気にせず進めてよい。

Phase 5 の完了処理の一部として、今回のミッション固有の詳細ではなく本 skill の運用一般に通用する知見が
得られた場合のみ追記する。プロジェクト固有の学びは引き続き軌跡ログへ、本 skill 自体の運用知見のみ
ここへ、と役割を分ける。一般化可能な学びが無ければ何も書かずに終える。
