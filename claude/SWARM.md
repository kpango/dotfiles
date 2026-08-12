# SWARM — 階層型 Agent Swarm 制御規約

対象ミッション: vdaas/vald コア開発と kpango/dotfiles 自律保守の並行推進。
人間の介入は「最終意思決定」「/swarm-loop・/swarm-graph・/swarm-meta・/swarm-architect（フル設計モード）・
/swarm-release-gate・/swarm-evolve の招集」のみに限定する（swarm-architect のスポット診断モードのみ、
§1 スポット判断層の条件発火で人間招集なしに単発起動される）。

本規約は 2026-07 の Deep Research（multi-agent orchestration 失敗研究・self-refine 収束性・verifier 独立性等の
一次文献調査、`SWARM_REFERENCES.md` 参照）を反映して改訂されている。研究で反証された想定（「検証層さえ強化すれば失敗は解消する」等）は
削除・修正済み。

## 0. 起動 — Massive Agents Loop（人間招集限定エントリポイント）

自走ループの入口は `/swarm-loop`（0 段・線形状態機械）・`/swarm-graph`（1 段進化・タスク依存 DAG の
フロンティア実行）・`/swarm-meta`（2 段進化・ミッション適応型ハーネス選択）の 3 つで、**いずれも人間招集
限定**（3 skill とも `disable-model-invocation: true`。モデルの自然文自動発火による Mission 規模の誤爆・
費用ガード迂回を機械的に遮断する）。進化系 2 skill は swarm-loop を置換しない — `swarm-graph` は
GRAPH-FIT 採用ゲート（タスク≤2 または幅 1 の純鎖なら loop へ保守的降格。graph の価値は運用面であり
逐次タスクへの強制は劣化するという 2026-07 Deep Research の実証知見に基づく）を持ち、`swarm-meta` は
決定論プロファイル+実績 registry からハーネス構成を選択して loop/graph へ委譲する（実行中の自己改変は
しない。ハーネス自体の進化提案は swarm-evolve の人間承認フローのみ）。dmi:true の skill は Skill tool
から起動できないため、skill 間の委譲は「選択した SKILL.md を Read して状態機械に従う」方式で行う
（人間の明示招集が自走ループ起動の承認を構成する）。「1 行の typo 修正」から「100 体規模の Haiku 探索を
伴う大規模自律ミッション」まで、人間が事前にどちらの skill を使うか判断するコストをなくすことが目的。

Phase -1（SCALE 判定）で Quick / Interactive / Mission のいずれかに自動分類し、SCALE 判定 → INIT →
EXPLORE → PLAN(+設計インタビュー) → EXECUTE → CHECKPOINT → GATE の状態機械で全層を駆動する。判定は昇格のみ
（安全側に倒す）。進行状態は `@fix_plan.md` に永続化される（Quick は状態ファイルを作らない。セッション再開も
`/swarm-loop` から）。状態確認は `swarm-loop/scripts/loop-status.sh`、新規開始は `mission-init.sh` を用いる。
詳細な判定基準・各 Phase の分岐は `swarm-loop/SKILL.md` を参照。`/swarm-graph` 実行時の状態確認は
`loop-status.sh` ではなく `graph-status.sh` を使う（frontier・critical path・stale 等のグラフ固有状態を
解釈できるのは `graph-status.sh` のみで、`loop-status.sh` はグラフ構造を解釈しない）。

ミッション駆動（`/swarm-loop`）とは別に、**継続的なドリフト監視には汎用 `loop` skill を使う**（例:
`/loop 30m make lint && make test`）。こちらは完了条件を持たない定期監視であり、`/swarm-loop` の
Definition-of-Done 型の一回性ミッションとは目的が異なる。lint/test の恒常的な健全性チェックに用い、
異常を検知したら `/swarm-loop` でミッション化する。

Claude Code の Workflow ツール（Anthropic 公式には「Dynamic Workflows」と呼ばれる）は、本規約が
前提とする「Haiku 群 fan-out → 秘書集約」「独立 Checker による反証的検証」を実行する具体的な実装手段
である（`swarm-explore`・`swarm-implement` 内のコード例が実際に使用）。公式には単一セッション内で
数十〜数百体の subagent を fan-out（上限 1000/run・同時実行 16）し、組み込みの検証パターンとして
「独立した角度からの攻撃 + 敵対的反証による収束」を持つ（confidence=medium・2-1 vote、詳細は
`SWARM_REFERENCES.md` の 2026-08-01 追加分を参照）。本規約の Maker/Checker 分離・秘書集約はこの機能上に構築されているが、
機能自体が持つ収束保証をそのまま信用せず、§2 の verifier 独立性の限界・決定論的ツール第一権威の
原則を継続して適用する。

## 1. 組織トポロジーと動的モデルルーティング

| 層                 | モデル                    | 責務                                                                                                                                                | 入口                                                                           |
| ------------------ | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Swarm 層           | `haiku`                   | コードベース全域探索・golangci-lint 等の大量ログ解析・文献調査。読み取り専用。最大 100 体を Workflow でスポーン（同時実行数は Workflow が自動制御） | `swarm-explore`                                                                |
| 情報集約層（秘書） | `sonnet`                  | Haiku 群の生レポートの重複排除・構造化・依存関係に基づく優先順位づけ **のみ**。新規調査禁止                                                         | `swarm-secretary`（内部専用）                                                  |
| 実装層 Maker       | `sonnet`                  | 秘書レポートに基づく実装。worktree 隔離必須                                                                                                         | `swarm-implement`                                                              |
| 検証層 Checker     | `opus`                    | Maker と独立コンテキストで単発の反証的判定を行う（討論はしない、§2 参照）。Maker の自己申告を信用しない                                             | `swarm-implement`                                                              |
| スポット判断層     | `fable`（明示指定）       | 高難易度・状況判断が鍵の局面での単発診断（発動 4 条件・1 タスク 1 回・1 ミッション 2 回、下記ルーティング規則参照）。原則読み取り専用・診断書のみ   | `swarm-architect`（スポット診断モード）／`swarm-implement`（Fable Maker 例外） |
| 指揮・設計層       | セッションモデル（Fable） | VStream の LSH 動的パーティショニング等の高度設計・難局突破の提案書出力のみ。コード編集禁止                                                         | `/swarm-architect`（フル設計モード、人間招集のみ）                             |

実装層 Maker/Checker の並列実行は独立タスクにつき**最大 3 並列**までとする（Checker の品質とレビュー可能性
を落とさないため。旧 dig の並列上限 5 はレビュー品質の実証知見により本基盤では不採用。詳細は
`swarm-loop/SKILL.md` Phase 3 EXECUTE 参照）。4 並列以上は禁止。

ルーティング規則:

- Agent / Workflow の `model` パラメータで上表を **明示** する。`model` 省略（＝セッションモデル継承）が許されるのは指揮・設計層のみ。
- **スポット判断層（Fable スポットルート）**: 高難易度・状況判断が鍵になる局面に限り、`model: 'fable'` の
  明示指定で Fable を単発起動できる。発動条件は次の 4 つ**のみ**:
  1. **Fixer 失敗後の最終診断**（`swarm-implement`）— Fixer(debugger) でも根本原因を特定できず
     ESCALATE / BUDGET_EXCEEDED に至る直前の 1 発診断。
  2. **`blocked(design)` 前の設計スクリーニング**（`swarm-loop` PLAN / CHECKPOINT）— MAST system design
     issue と分類したタスク、または Mission モードの PLAN 段階でアーキテクチャ判断未確定のまま
     `blocked(design)` としようとするタスクについて、人間へ `/swarm-architect`（フル設計モード）招集を
     要請する前の一次診断（招集要否の判断材料を作る。招集の代替ではない）。
  3. **`complex` 複雑度タスクの実装計画レビュー**（`swarm-implement` の着手前承認ゲート）。
  4. **Checker と決定論的検証の矛盾診断** — 再判定でも矛盾が解消しない場合に「なぜ食い違うか」の原因診断のみを
     行う。判定の上書きはしない（決定論的ツール第一権威の §2 原則は不変）。
     各起動の**前に** `swarm-implement/scripts/budget-guard.sh --fable <task-id> [--mission=<slug>]` を通し、
     **1 タスク 1 回・1 ミッション 2 回**を機械的に強制する（拒否時は消費なし）。`FABLE_BUDGET_EXCEEDED` の
     場合は Fable を使わず各発動点の**従来経路へフォールバック**する — 条件 1 は人間へ ESCALATE、条件 2 は
     直接 `blocked(design)`、条件 3 は既存の complex 承認フロー（人間 / Checker(opus)）、条件 4 は hook 優先の
     従来の矛盾処理。権限は原則読み取り専用・診断書のみ（`swarm-architect` スポット診断モード）。
     例外として、`complex` タスクまたは条件 1 のルートでスポット診断が「診断のみでは不十分・最小差分の実装介入が
     必要」と明示判断した場合のみ、同一スポット消費の継続として `swarm-implement` 内で Maker を `model: 'fable'`
     で起動してよい（**Fable Maker**。hook の 1 grant = 1 スポーン要件を満たす継続用 grant は
     `budget-guard.sh --fable-maker <task-id>` で発行する — base spot の消費実績を機械的に検証し、
     mission 枠を追加消費せず、継続も 1 回のみ。手順は swarm-implement 参照）。その場合も判定集約は不変 — Checker(opus)・並行レビュー・決定論的検証を
     通し、Fable の自己申告では完了させない。スポット判断層も intra-family であり verifier 独立性の限界（§2）を
     免れない — その出力は補助 heuristic であり、hook/lint/test の機械的結果に優先しない。
     Quick モード（`swarm-loop`）はスポット判断層の対象外（1 ファイル 15 行以下の変更に発動 4 条件は実質
     生じず、`@fix_plan.md` を持たないため mission 枠の帰属も無い）。本ルートは hook でも機械的に強制される:
     `swarm-fable-gate.sh`（PreToolUse:Task|Agent）が `model: 'fable'` の起動を budget-guard 発行の未消費
     grant トークン（1 grant = 1 スポーン、TTL 600s、**task 束縛**）と突き合わせ、無許可スポーンをブロック
     する。fable スポーンの prompt には `[fable-spot:<task-id>]` マーカー（budget-guard に渡したのと同一の
     task-id）が**必須**で、hook は同一 task の grant のみを消費する（マーカー無し・不一致はブロック —
     他 task の grant を窃取できない）。grant/deny は `~/.claude/session-data/swarm/fable-spot-log.jsonl`
     に記録され（1000 行超で直近 500 行へ自動ローテーション）、発動頻度・上限の調整証跡になる
     （`swarm-evolve` の `collect-evidence.sh` が decision 別集計を証拠に含める）。本段落の数値
     （上限・TTL・ローテーション）の単一ソースは `swarm-implement/scripts/fable-budget.conf` —
     budget-guard / hook / loop-status が source するため、変更はそこで行い本文の記載も追随させる。
- Fixer（`swarm-implement` の `debugger` サブエージェント）は `model: sonnet` を**明示**する。`debugger` の
  frontmatter は `model: inherit` のため、明示を怠ると Fable セッションでは暗黙に Fable を継承し、スポット
  判断層の発動条件・回数制限を迂回する経路になる（Fable 消費はスポット判断層へ集約する）。
- Swarm 層は `effort` もモデルと独立にルーティングする: シャード規模（対象ファイル数）に応じ静的に
  low/medium を割り当て、秘書が「findings が曖昧・矛盾・不自然に少ない」と判定したシャードのみ 1 段階
  昇格させ限定的に差分再探索する。コストメリットは大半のシャードで維持しつつ、Haiku が収集した情報を
  要約する段階で欠落するリスクを下げる（実装は `swarm-explore`／`swarm-secretary` 参照。秘書判定に依らない
  一律の effort 引き上げは禁止 — コストメリットを失うため）。
- Haiku の生出力を実装層・指揮層のコンテキストへ直接流さない。必ず秘書レポートを経由する。
- 探索 → 集約 → 実装 → 検証は独立コンテキストで行い、各層間の受け渡しは構造化レポート（JSON / Markdown）のみとする。

**並列数上限の機械強制**: 上記「最大 3 並列」は `swarm-parallel-gate.sh`（PreToolUse:Task|Agent）が
機械強制する。`swarm-implement` が起動する Test Maker/Maker/Checker/並行レビュー/Fixer の prompt に
`[parallel-task:<task-id>]` マーカーを含めることで、同一 task-id は 1 スロットとしてカウントし、
distinct task-id が 3 スロットを超える 4 タスク目以降を exit 2 でブロックする（TTL 既定 1800s で
自動失効、明示解放は `parallel-gate.sh --release <task-id>`）。

**dmi:false skill 間の Skill tool 相互呼び出し**: `swarm-implement`／`swarm-explore`／`swarm-secretary`／
`swarm-architect`／`swarm-evolve`／`swarm-memory-sync`（いずれも `disable-model-invocation: false`）は
互いを `Skill` tool 経由で呼び出し先（callee）にしてよい。ただし発信側（caller）になれるのは
`allowed-tools` に `Skill` を持つ skill のみで、現時点では `swarm-implement`／`swarm-explore`／
`swarm-evolve` の 3 つに限られる（`swarm-secretary`／`swarm-architect`／`swarm-memory-sync` は各自の
既存の scope 制限——ノイズ遮断専用・読み取り専用・auto-memory 限定——を優先し `Skill` を付与しない。
発信の必要が生じた時点で個別に allowed-tools を見直す）。`swarm-loop`／`swarm-graph`／`swarm-meta`／
`swarm-release-gate`（`disable-model-invocation: true`、人間招集限定の 4 skill）はこの解禁の対象外
— dmi:false な skill がモデルの自然文で自動起動された際にそこからチェーンで Mission 規模の自走ループや
マージ操作が人間不在のまま誤爆することを防ぐため、この 4 skill への委譲は引き続き「Skill tool は呼ばず
SKILL.md を Read して状態機械に従う」既存方式のみとする（§0 参照）。

## 2. 検証層の設計原則 — MAST 失敗分類と verifier 独立性の限界

Multi-Agent System Failure Taxonomy（MAST、150 件超の専門家注釈トレース由来、arXiv:2503.13657）は失敗を
3 カテゴリ・14 モードに分類する。CHECKPOINT でのブロック分類・ESCALATE 先の判断にこの 3 分類を用いる:

| MAST カテゴリ                 | 意味                                                           | 本基盤での対応                                                 |
| ----------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------- |
| (i) system design issues      | 役割・仕様定義の不備                                           | `swarm-secretary` の構造化・`swarm-architect` への設計差し戻し |
| (ii) inter-agent misalignment | 層間の前提のズレ（秘書レポートと Maker の解釈違い等）          | `swarm-loop` PLAN での task 分割見直し・depends 明記           |
| (iii) task verification       | 検証不足・**時期尚早な終了（FM-3.1）**・不完全な検証（FM-3.2） | Stop hook・Checker 層・`swarm-release-gate`                    |

**検証層だけを強化しても失敗は解消しない**ことが実証されている（同論文、3-0 で確認）。実際、役割仕様やトポロジーへの
介入（ChatDev で 25.0%→40.6%）でも改善は部分的で、実運用に足る水準には至らなかった。したがって:

- Checker 層は必要条件であって十分条件ではない。`swarm-secretary`（仕様の構造化）と `swarm-architect`（設計是正）が
  カテゴリ (i)(ii) を担うことで初めて Checker（カテゴリ iii）が機能する。3 層のどれか 1 つだけを厚くしない。
- **Maker (Sonnet) と Checker (Opus) は同一ベンダー系列 (intra-family)**である。verifier の独立性研究では、
  solver と verifier の推論分布が近いほど verifier が誤りを見逃しやすく、self-verification や intra-family
  verification は cross-family verification（系列の異なるモデル・手法）に劣ることが示されている（一次ソースの
  みで adversarial 検証は未完了 — `SWARM_REFERENCES.md` 参照。ただし複数独立研究で一貫した方向性）。
  - この限界への対処: **決定論的ツール（golangci-lint / hadolint / gofmt / make test）を第一権威とし、Opus
    Checker の LLM 判定は補助的 heuristic として扱う**。Stop hook・PostToolUse hook の機械的検証結果に反する
    Checker の「合格」判定は無効。両者が食い違う場合は hook 側を優先し、Checker には理由を再提示させる。
    この優先順位づけは GroundEval（arXiv:2606.22737、`SWARM_REFERENCES.md` 参照）が示す実例——2 つの frontier LLM judge が
    根拠アーティファクト未取得のもっともらしい応答を 0.85–0.90 と誤評価した一方、決定論的スコアリングは
    0.000 を正しく検出した——によっても裏づけられる。
  - 可能な範囲でツールチェーンの多様性を上げる（例: golangci-lint の複数 linter、Rust の clippy + miri 等）。
    Claude Code の制約上モデル系列自体を変えることはできないため、これは構造的な残存リスクとして
    `swarm-release-gate` の人間承認ステップで明示する（§6）。
  - **hooks も「necessary but insufficient」である**: Anthropic 公式ガイダンス（2026-06）は hooks を
    決定論的強制の意図された配置場所として明示するが、実運用では hooks 自体もサイレントに失敗しうる・
    subagent 経由でバイパスされうる・モデルにより書き換えられうるという限界が実務コミュニティから
    指摘されている（GitHub RFC issue、confidence=medium・3-0 vote、詳細は `SWARM_REFERENCES.md` の
    2026-08-01 追加分を参照）。本基盤にも同種の限界の実例がある: `swarm-fable-gate.sh` は `subagent_type: debugger` を
    `model` 未指定で起動した場合に警告のみで実行を止めない（非ブロッキング、`swarm-implement/SKILL.md`
    自身が既知の残課題として明記。ただし `model: 'fable'` の起動自体は未消費 grant が無ければ exit 2 で
    確実にブロックする — hook 内の判定経路によって強制力が異なる点に注意）。hook を「あるから安全」と
    見なさず、hook 自体の強制力（exit code でブロックするか、警告のみか）を経路ごとに個別に確認する。
    同種の教訓として、hook の `block()` 実装は exit 2 時に stdout ではなく stderr へ reason を出力する
    必要がある（Claude Code は exit 2 で stdout を無視し stderr のみを読む、公式仕様）。「JSON 出力＝正しい
    実装」という類推は誤りであり、出力先と exit code の組み合わせで意味が変わる点に注意する。
  - **未機械化ギャップの一部を機械化**: 本節冒頭の「両者が食い違う場合は hook 側を優先し、Checker には
    理由を再提示させる」という規範のうち矛盾検出は `swarm-implement/scripts/verify-consistency.sh` が
    機械化した（hook 結果と Checker 判定を 2 つの状態ファイルから読み矛盾（hook 失敗 かつ Checker 合格）
    を検出する。検出結果を実際に尊重し再判定させるかはオーケストレーターの運用に依然依存し、hook 自体
    によるツール呼び出し阻止ではない点に注意）。同様に、Maker/Checker 並列数上限（§1「最大 3 並列・
    4 並列以上禁止」）は `swarm-parallel-gate.sh`（PreToolUse:Task|Agent）がマーカー+スロットファイル
    方式で機械強制するようになった。3 試行目ソフトチェックポイントの自動判定（§3）は
    `budget-guard.sh` が attempt=3 到達時に `SOFT_CHECKPOINT_DUE` を出力するようになった（判断・分岐
    自体はオーケストレーターに委ねる、フラグの提示のみ）。`swarm-evolve` の Drafter/Checker 独立性の
    実装的隔離は `extract-checker-input.sh` が draft から `pattern`（Drafter の理由づけ）を機械的に
    除去し `evidence`/`target`/`diff_type`/diff コードブロックのみを Checker へ渡す経路を用意した。
    **残る未機械化ギャップ**: テストアサーション弱化検出（§6「データの完全性」、意味的 diff 解析が必要
    でヒューリスティックな誤検知リスクが高いため見送り）・`swarm-implement` の Checker 判定行
    （`VERDICT: PASS|FAIL`）欠落検出（呼び出し元 LLM 自身の grep 実行に依存する案を検討したが、それ
    自体が「LLM が実行するかどうかに依存する」という点で prompt 強制と同じ enforcement カテゴリに留まり、
    2 ミッションで実証済みの再発を防げないため不採用——真の機械化には `PostToolUse:Agent` 相当の hook
    新設が必要で、入力スキーマの確証が取れていないため見送った）がある。いずれも解決には専用の設計判断が
    必要であり、次回の `/swarm-architect` 設計レビュー候補として記録するに留める。
- **Maker/Checker は討論（debate）させない。** Multi-agent debate はラウンドを重ねるほど position/verbosity/CoT
  バイアスを増幅させ、後続ラウンドでも解消しないことが実証されている（3-0 確認）。一方、単一の集約判定
  （meta-judge 型）はバイアス増幅に対して頑健。Checker は Maker の弁明を受け取らず、仕様＋ diff のみを見て
  **一発で** 合否を出す（既存設計どおり。往復修正の要求はループの次試行として扱い、同一 Checker コンテキスト内で
  Maker と直接やり取りさせない）。
- **自動化された指摘の severity 表示・自作チェックスクリプトの出力も鵜呑みにしない**: Haiku 探索・秘書
  レポートが severity=critical/high と分類した finding であっても、設定の階層構造・意図的な fail-safe/
  fail-open 挙動・コメントに明記された設計意図を Haiku 群は読み取れず誤検知しやすい（誤検知率の高さが
  複数回観測されている）。severity の高さは一次ファイルでの裏取りを省略する理由にならない。同じ厳格さは、
  Haiku 由来の指摘に限らず**自分自身が書いた機械的検証スクリプト（grep/awk 等）の出力**にも適用する
  （情報源が「他エージェント」か「自分の書いたツール」かを問わず同じ検証基準を適用する）。
- **名前付き Agent 呼び出しの停滞対応**: `idle_notification` のみが返る、または要求した出力形式
  （`VERDICT: PASS|FAIL` 等）が欠落するなどで名前付き Agent 呼び出し（`name` 指定、`subagent_type:
"fork"` 以外）が停滞することがある。この場合は**再スポーンせず** `SendMessage` で当該エージェントへ
  報告本文・判定行を直接再要求する（完了済みエージェントは resume され文脈を保ったまま回答できる）。
  これは討論（debate）の再導入ではない——Maker/Checker 間の往復修正・弁明の受け渡しは引き続き禁止であり、
  本原則が許すのは「同一の出力を出し直させる」催促のみである。繰り返し催促しても得られない場合は
  無限に待たず `TaskStop` して呼び出し元が直接代替手段を実行する。`swarm-implement`（Maker/Checker/
  Fixer/Test Maker）・`swarm-evolve`（Drafter/Checker）が名前付き Agent を起動する全 skill であり、
  いずれもこの原則を適用する（詳細な運用例は `swarm-implement/SKILL.md` 参照）。

## 3. リソース制約 — Unified Credit Feedback

- **1 修正ループ = 最大 5 試行、ただし 3 試行目でソフトチェックポイント**を置く。RL 訓練した構造化 reflection の
  再現実験では Repair@1/3/5 = 4.7% / 20.5% / 26.4%（対ベースライン 0.7% / 5.1% / 6.8%）で、回復の大半は
  3 試行目までに積み上がり、4–5 試行目の追加効果は逓減する（単一の一次ソース、adversarial 検証は未完了 — 参考値
  として扱う）。したがって:
  - 試行 3 終了時点で修正が収束していなければ、**同じ仮説のまま試行 4–5 を消費する前に仮説そのものを疑う**
    （Maker への入力を変える: 秘書レポートの別項目、Checker 指摘の再解釈、または `/swarm-architect` 招集の検討）。
  - 試行 5 で `BUDGET_EXCEEDED` になったら即座に停止して人間に報告する（`@fix_plan.md` に状況を書き出してから）。
  - 本段落のタスク単位の試行上限（既定 5）・ミッション単位の試行上限（既定 20）の単一ソースも §1 の
    fable 関連定数と同じ `swarm-implement/scripts/fable-budget.conf`（`BUDGET_TASK_MAX_DEFAULT` /
    `BUDGET_MISSION_MAX_DEFAULT`）であり、変更はそこで行い本文の記載も追随させる。
- 各試行の頭で `swarm-implement/scripts/budget-guard.sh <task-id>` を呼ぶ。
- Fable スポット判断（§1 スポット判断層）は各起動の前に `budget-guard.sh --fable <task-id> [--mission=<slug>]`
  を通す（1 タスク 1 回・1 ミッション 2 回、許可時のみ消費）。超過は `FABLE_BUDGET_EXCEEDED` として扱い、
  Fable を追加消費せず各発動点の従来経路へフォールバックする（発動条件別の扱いは §1）。
- Stop hook（`swarm-stop-verify.sh`）の差し戻しも 5 回で強制エスカレーション（停止を許可し人間へ報告）。
- Workflow スクリプトでは `budget.total && budget.remaining()` をループガードに使う。
- Haiku 100 体探索は 1 ミッションにつき原則 1 回。再探索が必要なら差分（前回の秘書レポート）を入力して範囲を絞る。
- `/swarm-graph` 実行時の replan（Phase G4、構造変更を伴う計画再構築）は **1 ミッション最大 2 回**まで
  （`swarm-graph/SKILL.md` §7 参照。swarm-loop には無い概念であり graph 固有の制約）。

## 4. Git Worktree Isolation

- ファイル編集を伴うサブエージェントを 2 体以上並列で動かす場合、タスクごとに `swarm-implement/scripts/worktree-alloc.sh <task-slug>` で `<repo>/.claude/worktrees/` 配下に独立 worktree を割り当てる。
- メイン作業ツリーの直接編集は「編集エージェントが 1 体のみ」のときに限る。
- 完了後は `worktree-release.sh` で回収する（ブランチはデフォルトで保持）。
- ミッション状態管理スクリプト（`graph-compile.sh` / `graph-status.sh` 等）は常に main リポジトリルートから
  起動する — worktree 内で `git rev-parse --show-toplevel` を無引数実行すると worktree 根が返り、
  split-brain（状態の二重管理）を起こす（詳細は `swarm-graph/SKILL.md` §9）。

## 5. Explicit Global Memory — 破滅的忘却の防止と機械化エスカレーション

- 自己改善ミッション（ゴールが Claude Code 自体の設定・コンテンツ改善であるもの）の重複判定は、
  `self-improve-registry.tsv` と同じ固定語彙（`CLAUDE.md` / `settings.json` / `hooks` / `agents-content` /
  `skills-content` / `multi-agent-mechanism`）でトークン化される（定義・使用箇所は `swarm-loop/SKILL.md`
  Phase 0 INIT の `self-improve-check.sh`）。
- 成功・失敗の軌跡は `swarm-implement/scripts/agents-log-lib.sh` が返すパスの軌跡ログに追記する
  （形式: `日付 | タスク | 試行回数 | 結果 | 学び（根本原因・有効だった手順）`）。プロジェクトルートの
  `AGENTS.md` には書かない — 一部のコーディングエージェントは `AGENTS.md` を `CLAUDE.md` と同格の
  指示ファイルとして自動読み込みするため、追記専用ログと本来のプロジェクト指示を混在させない
  （そのプロジェクトの `AGENTS.md` が正規の指示文書として使われている場合は一切変更しない）。
- 進行中の修正計画・残タスクは `@fix_plan.md`（プロジェクトルート）に置き、セッションを跨いで引き継ぐ。
- **同一エラーへ同一対処を 2 回連続で行わない**。修正ループに入る前に必ず軌跡ログと `@fix_plan.md` を読む。
- **学びの 3 段階モデル（点修正 → 明文化ルール → 機械化チェック）を強制する。** 運用インシデント分析では、
  「点修正」で止まった学びは全件が再発し、「点修正 → 明文化 → 機械化スキャナ/チェック」まで到達した学びは
  再発ゼロだったという結果がある（一次ソース、adversarial 検証は未完了）。したがって:
  - 軌跡ログの同一根本原因が **2 回目に出現した時点**で、その学びを prose のままにせず、
    hook（`swarm-post-edit-lint.sh` へのルール追加）・lint 設定・テストケースのいずれかへ**必ず機械化**する。
  - 機械化されていない「2 回目の学び」は CHECKPOINT でのブロック要因として扱い、機械化が完了するまで
    同種タスクを先に進めない。
- vdaas/vald では `fix_plan.md` は `.git/info/exclude` によりローカル専用（OSS リポジトリを汚染しない）。
  vald の `AGENTS.md` は本来の開発ガイド文書であり軌跡ログの追記対象ではない（上記参照）。
- **Fixer パターン（理解負債の遮断）**: 同一タスクで試行を重ねるほど Maker のコンテキストは失敗履歴で汚染され、
  同じ誤った仮説に固執しやすくなる。3 試行目のソフトチェックポイント（§3）では、失敗履歴を持たない新規の
  `debugger` サブエージェントを「現在のコード＋直近のエラーのみ」で起動し、汚染されていない視点から根本原因を
  再診断させる（詳細は `swarm-implement` skill）。
- **Skill 自体のメタループ（`/swarm-evolve` として実装済み）**: 同じ手直し・同じ人間からの訂正が複数ミッション
  にまたがって繰り返される場合、それは軌跡ログの機械化対象であると同時に、**該当 SKILL.md の記述不足の
  シグナル**でもある。`swarm-evolve` skill が軌跡ログと hook rejection ログ（`evolve-log.jsonl`）
  から繰り返しパターンを検出し、Drafter(sonnet)/Checker(opus) の独立判定を経て SKILL.md / hooks への差分を
  起案する。**いかなる差分も人間の明示承認なしには適用しない**（docs-only であっても例外なし — エージェントが
  自身の行動規範を無断で書き換えることを防ぐため）。定期実行したい場合は `/loop 1d /swarm-evolve` を使う
  （承認フェーズは loop によってスキップされない）。
- **ドメイン知識の蒸留（`/swarm-memory-sync` として実装済み）**: `swarm-evolve` が「Skill 自体の行動規範」を
  進化させるのに対し、`swarm-memory-sync` は軸が異なる — ミッション実行・人間対話で得た一般化可能な
  ドメイン知識を `~/.claude/memory/`（auto-memory）へ蒸留する。軌跡ログの学びは per-repo・非構造化の
  ミッション軌跡ログであり、`swarm-loop` Phase 0 INIT でしか読まれないため、swarm-loop 以外の通常セッションや
  他プロジェクトでは再利用されない。auto-memory は逆にセッション開始時に自動注入されるが、swarm-loop から
  そこへ書き込む機械的な経路が無ければ「気づいたら書く」という非機械的運用に留まる。`swarm-memory-sync` は
  `swarm-loop` Phase 5 GATE（および Phase 2 PLAN の設計インタビュー終了時）から内部的に呼ばれ、軌跡ログ /
  `@fix_plan.md` の学びのうち一般化可能なものだけを既存の user/feedback/project/reference 4 分類へ振り分けて
  書く。SKILL.md / hooks / SWARM.md 自体には一切触れないため、**行動規範の変更ではなく知識の記録**であり、
  `swarm-evolve` と異なり人間の明示承認は不要（memory はいつでも Edit・削除できる可逆な操作）。ただし
  一般化可能性の判定基準・既存メモリとの重複チェックは厳格に適用し、単発事象やこのミッション限りの詳細は
  書かない（memory 肥大化の防止。auto-memory の `MEMORY.md` は先頭 200 行 / 25KB のみが自動ロードされる
  という制約があるため、無闇な追記はむしろ想起されるべき知見を締め出す）。

## 6. クローズドループ — 自己申告終了の禁止

- 「完了しました」という自己申告のみでの終了は禁止。以下の hooks が機械的に強制する:
  - **PostToolUse (Write/Edit)**: `swarm-post-edit-lint.sh` — dotfiles では hadolint（`.hadolint.yaml` 準拠）、vald では編集パッケージ限定の golangci-lint を即時実行し、失敗は exit 2 で差し戻す。
  - **Stop**: `swarm-stop-verify.sh` — セッション中に編集したファイルを対象に検証（JSON validity / hadolint / zsh -n / gofmt / golangci-lint）。失敗時はエラーログと共に修正ループへ強制的に引き戻す。
- より重い検証（`make test/pkg` 等）を Stop 時に強制したい場合は `<repo>/.claude/swarm-stop-check.conf` に 1 行 1 コマンドで記述する（make ターゲット経由のみ）。
- **「fail-plausible」失敗モードへの対処**: 破損したコンテキスト（古いエラーページ、失敗したツール出力の断片等）を
  モデルが流暢な虚偽の成功報告として提示してしまう失敗が報告されている（一次ソース、adversarial 検証は未完了）。
  対策として、Maker・Checker とも「完了」「合格」を主張する際は**生のコマンド出力（テスト結果・lint 出力・diff）を
  根拠として添付**することを必須とし、prose のみの完了報告は評価対象にしない（既存の hook 強制検証と整合）。
- マージ・デプロイ・破壊的変更は必ず `/swarm-release-gate` を経由し、`scripts/verify.sh` 全パス後に人間の最終承認を得る。
- **データの完全性**: テスト・アサーション・許容誤差・スキップ指定を、失敗を回避する目的で弱める・削除することを
  固く禁ずる。グリーン化それ自体は目的ではなく、検証が機能している状態を保つことが目的である。テストの期待値が
  実際に誤っていた場合のみ修正してよいが、その根拠を Checker に提示できることを条件とする。

## 7. プロジェクト固有ドメイン憲法

### vdaas/vald

- 1,060 行超の `Makefile` + `Makefile.d/` の構造を **絶対に破壊しない**。ビルド・テスト・生成は既存 make ターゲット経由のみ（`make test/pkg`, `make proto/all` 等）。
- Vald Law 1–5 を遵守（`*.pb.go` 直接編集禁止・ホストでの go build/cargo build 禁止・panic/log.Fatal 禁止・エラー破棄禁止・stdlib 直接 import 制限）。law gate hooks が機械的に強制する。

### kpango/dotfiles

- `.hadolint.yaml` の `ignored` ルール（DL3002, DL3007 等）は **インフラ固有の意図的設定**。一般的ベストプラクティスを理由に修正・削除・「改善」することを禁止する。lint 対応はこの設定ファイルを尊重した上で行う。
- インストール・リンクは make ターゲット（`make dotfiles/install`, `make claude/docker/install`）経由のみ。手動 symlink 禁止。

## 8. 参考文献

詳細な参考文献一覧（確度別引用・Deep Research 追加分の履歴）は `SWARM_REFERENCES.md` に分離した
（本ファイルのトークン占有量を抑えるため）。§0–§7 中の「SWARM_REFERENCES.md 参照」は同ファイルの
対応する記述を指す。新しい根拠が反証された場合、または追加の Deep Research で確度が上がった場合は
`SWARM_REFERENCES.md` の該当セクションを更新すること。
