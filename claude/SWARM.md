# SWARM — 階層型 Agent Swarm 制御規約

対象ミッション: vdaas/vald コア開発と kpango/dotfiles 自律保守の並行推進。
人間の介入は「最終意思決定」「/swarm-loop・/swarm-architect（フル設計モード）・/swarm-release-gate・
/swarm-evolve の招集」のみに限定する（swarm-architect のスポット診断モードのみ、§1 スポット判断層の
条件発火で人間招集なしに単発起動される）。

本規約は 2026-07 の Deep Research（multi-agent orchestration 失敗研究・self-refine 収束性・verifier 独立性等の
一次文献調査、§8 参照）を反映して改訂されている。研究で反証された想定（「検証層さえ強化すれば失敗は解消する」等）は
削除・修正済み。

## 0. 起動 — Massive Agents Loop（単一エントリポイント）

自走ループの唯一の入口は `/swarm-loop`（人間招集限定）。旧 `dig` skill はここに完全統合され、単独では
存在しない（`/dig` は `swarm-loop` への薄いリダイレクトとして後方互換のみ残る）。「1 行の typo 修正」から
「100 体規模の Haiku 探索を伴う大規模自律ミッション」まで、人間が事前にどちらの skill を使うか判断する
コストをなくすことが統合の目的。

Phase -1（SCALE 判定）で Quick / Interactive / Mission のいずれかに自動分類し、SCALE 判定 → INIT →
EXPLORE → PLAN(+設計インタビュー) → EXECUTE → CHECKPOINT → GATE の状態機械で全層を駆動する。判定は昇格のみ
（安全側に倒す）。進行状態は `@fix_plan.md` に永続化される（Quick は状態ファイルを作らない。セッション再開も
`/swarm-loop` から）。状態確認は `swarm-loop/scripts/loop-status.sh`、新規開始は `mission-init.sh` を用いる。
詳細な判定基準・各 Phase の分岐は `swarm-loop/SKILL.md` を参照。

ミッション駆動（`/swarm-loop`）とは別に、**継続的なドリフト監視には汎用 `loop` skill を使う**（例:
`/loop 30m make lint && make test`）。こちらは完了条件を持たない定期監視であり、`/swarm-loop` の
Definition-of-Done 型の一回性ミッションとは目的が異なる。lint/test の恒常的な健全性チェックに用い、
異常を検知したら `/swarm-loop` でミッション化する。

## 1. 組織トポロジーと動的モデルルーティング

| 層                 | モデル                    | 責務                                                                                                                                                | 入口                                                                           |
| ------------------ | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| Swarm 層           | `haiku`                   | コードベース全域探索・golangci-lint 等の大量ログ解析・文献調査。読み取り専用。最大 100 体を Workflow でスポーン（同時実行数は Workflow が自動制御） | `swarm-explore`                                                                |
| 情報集約層（秘書） | `sonnet`                  | Haiku 群の生レポートの重複排除・構造化・依存関係に基づく優先順位づけ **のみ**。新規調査禁止                                                         | `swarm-secretary`（内部専用）                                                  |
| 実装層 Maker       | `sonnet`                  | 秘書レポートに基づく実装。worktree 隔離必須                                                                                                         | `swarm-implement`                                                              |
| 検証層 Checker     | `opus`                    | Maker と独立コンテキストで単発の反証的判定を行う（討論はしない、§2 参照）。Maker の自己申告を信用しない                                             | `swarm-implement`                                                              |
| スポット判断層     | `fable`（明示指定）       | 高難易度・状況判断が鍵の局面での単発診断（発動 4 条件・1 タスク 1 回・1 ミッション 2 回、下記ルーティング規則参照）。原則読み取り専用・診断書のみ   | `swarm-architect`（スポット診断モード）／`swarm-implement`（Fable Maker 例外） |
| 指揮・設計層       | セッションモデル（Fable） | VStream の LSH 動的パーティショニング等の高度設計・難局突破の提案書出力のみ。コード編集禁止                                                         | `/swarm-architect`（フル設計モード、人間招集のみ）                             |

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
  みで adversarial 検証は未完了 — §8 参照。ただし複数独立研究で一貫した方向性）。
  - この限界への対処: **決定論的ツール（golangci-lint / hadolint / gofmt / make test）を第一権威とし、Opus
    Checker の LLM 判定は補助的 heuristic として扱う**。Stop hook・PostToolUse hook の機械的検証結果に反する
    Checker の「合格」判定は無効。両者が食い違う場合は hook 側を優先し、Checker には理由を再提示させる。
    この優先順位づけは GroundEval（arXiv:2606.22737、§8 参照）が示す実例——2 つの frontier LLM judge が
    根拠アーティファクト未取得のもっともらしい応答を 0.85–0.90 と誤評価した一方、決定論的スコアリングは
    0.000 を正しく検出した——によっても裏づけられる。
  - 可能な範囲でツールチェーンの多様性を上げる（例: golangci-lint の複数 linter、Rust の clippy + miri 等）。
    Claude Code の制約上モデル系列自体を変えることはできないため、これは構造的な残存リスクとして
    `swarm-release-gate` の人間承認ステップで明示する（§6）。
- **Maker/Checker は討論（debate）させない。** Multi-agent debate はラウンドを重ねるほど position/verbosity/CoT
  バイアスを増幅させ、後続ラウンドでも解消しないことが実証されている（3-0 確認）。一方、単一の集約判定
  （meta-judge 型）はバイアス増幅に対して頑健。Checker は Maker の弁明を受け取らず、仕様＋ diff のみを見て
  **一発で** 合否を出す（既存設計どおり。往復修正の要求はループの次試行として扱い、同一 Checker コンテキスト内で
  Maker と直接やり取りさせない）。
- **自動化された指摘の severity 表示・自作チェックスクリプトの出力も鵜呑みにしない**: Haiku 探索・秘書
  レポートが severity=critical/high と分類した finding であっても、設定の階層構造・意図的な fail-safe/
  fail-open 挙動・コメントに明記された設計意図を Haiku 群は読み取れず誤検知しやすい（2026-07-13
  skill-effectiveness-audit で 61 件中 55 件が誤検知、2026-07-17 all-skills-phrasing-audit で同型の
  誤検知パターンがドメイン非依存で再現）。severity の高さは一次ファイルでの裏取りを省略する理由にならない。
  同じ厳格さは、Haiku 由来の指摘に限らず**自分自身が書いた機械的検証スクリプト（grep/awk 等）の出力**にも
  適用する（2026-07-17 の自作 awk スクリプト・2026-07-18 の自作 grep スクリプトの誤検知は、いずれも実
  ファイル確認で自ら破棄・訂正できた実例であり、情報源が「他エージェント」か「自分の書いたツール」かを
  問わず同じ検証基準を適用する）。

## 3. リソース制約 — Unified Credit Feedback

- **1 修正ループ = 最大 5 試行、ただし 3 試行目でソフトチェックポイント**を置く。RL 訓練した構造化 reflection の
  再現実験では Repair@1/3/5 = 4.7% / 20.5% / 26.4%（対ベースライン 0.7% / 5.1% / 6.8%）で、回復の大半は
  3 試行目までに積み上がり、4–5 試行目の追加効果は逓減する（単一の一次ソース、adversarial 検証は未完了 — 参考値
  として扱う）。したがって:
  - 試行 3 終了時点で修正が収束していなければ、**同じ仮説のまま試行 4–5 を消費する前に仮説そのものを疑う**
    （Maker への入力を変える: 秘書レポートの別項目、Checker 指摘の再解釈、または `/swarm-architect` 招集の検討）。
  - 試行 5 で `BUDGET_EXCEEDED` になったら即座に停止して人間に報告する（`@fix_plan.md` に状況を書き出してから）。
- 各試行の頭で `swarm-implement/scripts/budget-guard.sh <task-id>` を呼ぶ。
- Fable スポット判断（§1 スポット判断層）は各起動の前に `budget-guard.sh --fable <task-id> [--mission=<slug>]`
  を通す（1 タスク 1 回・1 ミッション 2 回、許可時のみ消費）。超過は `FABLE_BUDGET_EXCEEDED` として扱い、
  Fable を追加消費せず各発動点の従来経路へフォールバックする（発動条件別の扱いは §1）。
- Stop hook（`swarm-stop-verify.sh`）の差し戻しも 5 回で強制エスカレーション（停止を許可し人間へ報告）。
- Workflow スクリプトでは `budget.total && budget.remaining()` をループガードに使う。
- Haiku 100 体探索は 1 ミッションにつき原則 1 回。再探索が必要なら差分（前回の秘書レポート）を入力して範囲を絞る。

## 4. Git Worktree Isolation

- ファイル編集を伴うサブエージェントを 2 体以上並列で動かす場合、タスクごとに `swarm-implement/scripts/worktree-alloc.sh <task-slug>` で `<repo>/.claude/worktrees/` 配下に独立 worktree を割り当てる。
- メイン作業ツリーの直接編集は「編集エージェントが 1 体のみ」のときに限る。
- 完了後は `worktree-release.sh` で回収する（ブランチはデフォルトで保持）。

## 5. Explicit Global Memory — 破滅的忘却の防止と機械化エスカレーション

- 成功・失敗の軌跡はプロジェクトルートの `AGENTS.md` に追記する。形式: `日付 | タスク | 試行回数 | 結果 | 学び（根本原因・有効だった手順）`。
- 進行中の修正計画・残タスクは `@fix_plan.md`（プロジェクトルート）に置き、セッションを跨いで引き継ぐ。
- **同一エラーへ同一対処を 2 回連続で行わない**。修正ループに入る前に必ず `AGENTS.md` と `@fix_plan.md` を読む。
- **学びの 3 段階モデル（点修正 → 明文化ルール → 機械化チェック）を強制する。** 運用インシデント分析では、
  「点修正」で止まった学びは全件が再発し、「点修正 → 明文化 → 機械化スキャナ/チェック」まで到達した学びは
  再発ゼロだったという結果がある（一次ソース、adversarial 検証は未完了）。したがって:
  - `AGENTS.md` の同一根本原因が **2 回目に出現した時点**で、その学びを prose のままにせず、
    hook（`swarm-post-edit-lint.sh` へのルール追加）・lint 設定・テストケースのいずれかへ**必ず機械化**する。
  - 機械化されていない「2 回目の学び」は CHECKPOINT でのブロック要因として扱い、機械化が完了するまで
    同種タスクを先に進めない。
- vdaas/vald では `AGENTS.md` / `fix_plan.md` は `.git/info/exclude` によりローカル専用（OSS リポジトリを汚染しない）。
- **Fixer パターン（理解負債の遮断）**: 同一タスクで試行を重ねるほど Maker のコンテキストは失敗履歴で汚染され、
  同じ誤った仮説に固執しやすくなる。3 試行目のソフトチェックポイント（§3）では、失敗履歴を持たない新規の
  `debugger` サブエージェントを「現在のコード＋直近のエラーのみ」で起動し、汚染されていない視点から根本原因を
  再診断させる（詳細は `swarm-implement` skill）。
- **Skill 自体のメタループ（`/swarm-evolve` として実装済み）**: 同じ手直し・同じ人間からの訂正が複数ミッション
  にまたがって繰り返される場合、それは AGENTS.md の機械化対象であると同時に、**該当 SKILL.md の記述不足の
  シグナル**でもある。`swarm-evolve` skill が AGENTS.md の軌跡と hook rejection ログ（`evolve-log.jsonl`）
  から繰り返しパターンを検出し、Drafter(sonnet)/Checker(opus) の独立判定を経て SKILL.md / hooks への差分を
  起案する。**いかなる差分も人間の明示承認なしには適用しない**（docs-only であっても例外なし — エージェントが
  自身の行動規範を無断で書き換えることを防ぐため）。定期実行したい場合は `/loop 1d /swarm-evolve` を使う
  （承認フェーズは loop によってスキップされない）。
- **ドメイン知識の蒸留（`/swarm-memory-sync` として実装済み）**: `swarm-evolve` が「Skill 自体の行動規範」を
  進化させるのに対し、`swarm-memory-sync` は軸が異なる — ミッション実行・人間対話で得た一般化可能な
  ドメイン知識を `~/.claude/memory/`（auto-memory）へ蒸留する。AGENTS.md の学びは per-repo・非構造化の
  ミッション軌跡ログであり、`swarm-loop` Phase 0 INIT でしか読まれないため、swarm-loop 以外の通常セッションや
  他プロジェクトでは再利用されない。auto-memory は逆にセッション開始時に自動注入されるが、swarm-loop から
  そこへ書き込む機械的な経路が無ければ「気づいたら書く」という非機械的運用に留まる。`swarm-memory-sync` は
  `swarm-loop` Phase 5 GATE（および Phase 2 PLAN の設計インタビュー終了時）から内部的に呼ばれ、AGENTS.md /
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

## 8. 参考文献（2026-07 Deep Research、確度別）

**確定（adversarial 3 票中 2 票以上で確認）:**

- MAST: Multi-Agent System Failure Taxonomy — 14 失敗モード・3 カテゴリ（system design / inter-agent
  misalignment / task verification）。arXiv:2503.13657, OpenReview fAjbYBmonr。
- ChatDev 等 SOTA オープンソース MAS の正答率は最低 25%、7 システム横断で失敗率 41–86.7%（1600+ 実行トレース）。
- 役割仕様・トポロジー改善で ChatDev は 25.0%→40.6% まで改善するが実運用水準には未達（+15.6pt、部分的改善に留まる）。
- 検証層の強化のみでは失敗は解消しない（仕様・設計・エージェント間通信も原因）。
- LLM-as-judge（o1 few-shot）は人間注釈との一致度 accuracy 94% / Cohen's κ 0.77 で失敗モードを検出可能。
- Multi-agent debate はラウンドを重ねるほど judge バイアスを増幅・持続させ、meta-judge（単一集約）はより頑健。
- Self-Preference Bias はモデルの生成能力と相関しない（強いモデル＝公平な judge ではない）。
- BEI/CIG: LLM 検証者間の behavioral entanglement（行動的もつれ）を統計的に定量化するメトリクス（18 モデル・
  6 ベンダー系列で実験、COLM 2026 採択）。もつれの強さ（CIG）は judge の over-endorsement bias と有意に相関する
  （GPT-4o-mini judge で Spearman ρ=0.64, p<0.001; Llama3 系 judge で ρ=0.71, p<0.01）。もつれを考慮した
  再重み付けにより単純多数決比で最大 4.5pt（84.7%→89.6%）の精度向上。arXiv:2604.07650。
- Nine Judges Two Effective Votes: 9 体 7 ファミリーの frontier LLM judge パネルは実効的に約 2 票分の独立情報
  しかない（Kish 実効サンプルサイズ n_eff≈2.0–2.5）。真に独立な投票との比較で 8–22pt の精度差が生じ、ボトル
  ネックは judge 間の相関でありパネル拡大では解決しない。arXiv:2605.29800。**注意**: 同論文由来の「最良単体
  judge がパネル全体と同等以上」という一般化 claim は独立検証で 0-3 棄却済み — この知見を根拠に「パネルは
  無意味」という結論へ飛躍しないこと。
- GroundEval: 決定論的スコアリングを LLM-as-Judge の明示的代替として位置づける手法。2 つの frontier LLM
  judge（Kimi-K2.6, ChatGPT-5.5）が根拠アーティファクトを一度も取得していないもっともらしいエージェント応答
  を 0.85–0.90 と評価した一方、trace 分析ベースの GroundEval スコアは 0.000 を検出。arXiv:2606.22737。
- Multi-agent debate の flip 率は自発的不安定性・迎合的同調・推論駆動説得の 3 メカニズムに反実仮想条件で分離
  可能。MMLU-Pro では自己反省のみ（ピア影響なし）でも 37% が回答を変え、厳密な意味での同調は 29%、モデル
  横断 57–77% が correct→wrong という有害な方向に偏っていた。arXiv:2606.00820。
- debate 中の sycophancy（ピア意見の無批判採用）は self-bias（自説固執）より圧倒的に多い（20 組中 18 組で
  sycophancy 優位、ACL2026 Main 採択）。arXiv:2510.07517。対策の response anonymization（身元マーカー除去）
  提案自体は 2-1 split（別の低信頼度論文が stylometric 指紋による匿名化の不完全性を指摘）であり確定扱いしない。

**一次ソースのみ・adversarial 検証未完了（レート制限により中断、参考情報として扱う）:**

- Cross-family verification が self/intra-family verification に優る（arXiv:2512.02304）。
- 学びの 3 段階モデル（点修正→明文化→機械化）到達で再発ゼロ、点修正止まりは全件再発（arXiv:2606.14589）。
- 自動監査は新規失敗の事前予防 0%、既知回帰の事後ブロック 87%（arXiv:2606.14589）。
- 「fail-plausible」failure mode: 破損コンテキストが流暢な虚偽出力として提示される（arXiv:2606.14589）。
- Tool-Reflection-Bench: RL 訓練した構造化 reflection で Repair@1/3/5 = 4.7%/20.5%/26.4%
  （ベースライン比 0.7%/5.1%/6.8%）、回復の大半は 3 試行目までに集中（arXiv:2509.18847）。
- CoRefine: 信頼度誘導型 self-refinement は平均 2.7 ステップで大規模並列サンプリングに匹敵、
  信頼度に基づく打ち切り判断の正解率 92.6%（arXiv:2602.08948）。
- Multi-Agent Verification（MAV、arXiv:2502.20379）: 複数の Aspect Verifier（異なる観点で検証する
  LLM）を組み合わせる BoN-MAV は self-consistency・単一 reward-model 検証よりスケーリング特性が良く、
  弱い verifier 複数の組み合わせでも強い generator の性能を改善できる（weak-to-strong generalization）。
  同一モデルが generator/verifier 双方を兼ねる self-improvement でも性能向上を確認。ただし adversarial
  検証は未完了の単一一次ソースであり、§2 の「Checker は単一の Opus による一発判定・討論禁止」という
  既存設計を変更するには至らない（複数 Checker 化は §3 のリソース制約とのトレードオフが未評価のため、
  現時点では参考文献に留め採用は見送る）。見送りの理由は Nine Judges Two Effective Votes（arXiv:2605.29800、
  confidence=high 3-0、本節「確定」参照）によってより具体化される: 複数 judge/Checker パネルは相関により
  実効投票数が名目数より大幅に少なくなり（n_eff≈2.0–2.5）、単純な多数決やパネル拡大では改善しない。
  複数 Checker 化を将来検討する場合は、単純多数決ではなく judge 間相関を考慮した再重み付け（BEI/CIG、
  arXiv:2604.07650）が前提条件となる。
- Entropy Principle（arXiv:2606.08162）: LLM エージェントシステムのエントロピー（出力一貫性・タスク精度・
  セッション間一貫性の崩れ）は相互作用ラウンド数に対し指数的に増大する（S(t) = S0 * e^(alpha*t)）。
  40,000 件超の統制実験・100,000 件超の本番エージェント相互作用から 22 の内在的失敗寄与要因
  （6 ライフサイクル層）を導出し、対策として決定論的ガバナンス（PIG Engine / ADE プロトコル）を提案。
  §2 の「決定論的ツール（golangci-lint / hadolint / gofmt / make test）を第一権威とし、Opus Checker の
  LLM 判定は補助的 heuristic として扱う」という既存スタンスを独立に補強する一次ソース（adversarial
  検証は未完了）。既存方針を変更する必要はなく、根拠の追加としてのみ扱う。
- Anthropic 公式: “Multi-agent research system”, “Effective context engineering for AI agents”,
  “Building agents with the Claude Agent SDK”, “Subagents in Claude Code”（vendor 一次情報、
  組織トポロジー・コンテキスト管理・subagent 設計の実務知見として §1–§5 の設計判断に反映済み）。
- 4 段階検証権威階層（confidence=medium）: 形式的検証者（証明）＞実行フィードバック（テスト）＞学習型
  判定器（報酬モデル・LLM-as-judge）＞内在的シグナル（確信度・尤度）という階層で、実証された自己改善の
  強さがこの序列に沿う傾向がある（著者自身が定性的パターンと明記し、測定された法則ではないと限定）。
  arXiv:2607.07663。同じ論文由来の他の claim（mirror loop、SkillsBench+16.2pt）は独立検証で 0-3 棄却済み
  であり、本項目のみを confidence=medium として切り出して扱う（他の claim は不採用）。既存の「決定論的
  ツールを第一権威とする」§2 方針への追加根拠として扱う。
- 金融 MAS の創発的バイアス増幅（confidence=medium、金融ドメイン限定・サンプル 20 構成×2 データセットと
  やや小規模）: 多エージェント意思決定システムでシステム全体のバイアスが構成 LLM 単体比最大 10 倍まで増幅
  する事例。全構成員が低バイアスでもシステム全体が高バイアスを示すことがあり、バイアスが個々のエージェント
  に単純還元されない創発的失敗モード。arXiv:2512.16433。この知見と、本節「確定」の identity 駆動 sycophancy
  （arXiv:2510.07517、debate 中の sycophancy が self-bias より優位という知見）は、いずれも既存の並行レビュー
  設計（Checker と code-reviewer / vald-reviewer / security-audit を互いの出力を見せずに独立実行する設計 —
  結果的に response anonymization 相当が既に実現されている）および判定集約が単純多数決ではなく AND 集約
  （Checker 合格 かつ 決定論的検証パス かつ 該当レビュアー合格）である既存設計が、debate 型の相互汚染や
  創発的バイアス増幅に対して既に理にかなっていることの裏づけとして扱う。新たな必須事項・禁止事項の追加は
  行わない。

新しい根拠が反証された場合、または追加の Deep Research で確度が上がった場合は本節と該当セクションを更新すること。

**外部レポート（2026-07-13 提出、人間による二次資料）由来で採用した項目 / 見送った項目:**

採用: Fixer パターン（§5、`debugger` サブエージェントによる汚染されていないコンテキストでの根本原因再診断）、
domain タグによる Maker のタスクルーティング（`swarm-loop` PLAN フェーズ）、テストアサーション整合性の明文化
（§6「データの完全性」）、継続監視への `loop` skill 併用（§0）、Skill 自体のメタループ改善（§5）、
Test Maker によるテスト先行記述（`swarm-implement` step 0、MAST (i)(ii) 対策）、Checker と並行する
`code-reviewer` / `vald-reviewer` / `security-audit` サブエージェント起動（グローバル CLAUDE.md の既存方針を
swarm-implement に配線）、コア設計変更のプロアクティブな architect ゲート（`swarm-loop` PLAN、事後対応の
`blocked(design)` を補完）、Plan-Action-Observe-Verify の Observe を独立ステップとして明示し既存の `verify`
skill を配線（静的検証だけでは新規失敗モードを捉えられないという §8 の知見への対処）。これらは実在する
Claude Code の機構（Agent tool の subagent_type、既存 `loop`/`verify` skill、SKILL.md 編集）のみで実現できる。

見送り（要再検証）: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`（有効化手段が本環境変数であるかは未確認）による
マルチセッション協調（Agent Teams）は、2026-03-24 付 Anthropic 公式資料（primary、adversarial 検証は未完了）
により**機能自体の実在は確認された**（"Orchestrate teams of Claude Code Sessions" — 独立ワークストリームに
分割可能なタスクでの並列化を想定）。ただし本確認は一次資料（スライド/プレゼン記載）の存在確認に留まり、
**現行 Claude Code バージョンでの実際の有効化・動作、`~/.claude/tasks/{team-name}/` という Mailbox 機構の
実装詳細、モデル別のトークン単価は未検証**である。したがって「実在確認ができない」という従来の見送り理由は
取り下げるが、動作・採用可否が未確認である以上、現時点でも本基盤への採用は見送る。エージェント間のタスク
共有・状態管理は引き続き既存の実在ツール（TaskCreate / TaskList / TaskUpdate、`@fix_plan.md`）で代替する。
再検討のトリガー: (1) 現行 Claude Code バージョンでの Agent Teams 動作確認、(2) 有効化手段・Mailbox 機構の
実装詳細確認、(3) 既存ツール代替との比較優位性評価 — のいずれかが完了した時点。

**現状の食い違い（2026-07-13 skill-effectiveness-audit で判明）**: `claude/settings.json` の
`env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` は実際には `"1"`（有効）に設定済みである。上記「見送り」は
方針判断であり、settings.json の設定値そのものを変更するものではない。この食い違いは人間の判断により
現状維持（設定値はそのまま・SWARM.md 本文もそのまま）とした。挙動観察（Agent tool 経由のサブエージェントから
`idle_notification` 形式のメッセージが届く等）が本環境変数と関係する可能性があるが未検証であり、上記の
再検討トリガーとは独立に記録するに留める。

**skill 統廃合（2026-07-13）:** 既存の `dig` skill が `swarm-loop` と大きく重複していたため（両者とも
探索→設計→実装→検証の自走ループを持つ）、人間が事前にどちらを使うか判断するコストを排除するために
`dig` を `swarm-loop` へ完全統合した。統合時に双方向の改善を行った: `dig` の Code Quality Reviewer が
Implementer と同じ `sonnet`（intra-family、§2 の verifier 独立性の限界そのもの）だった点を §1 の
Checker 層（`opus`）に格上げし（本節で以前「opusplan」と表記していたのは `opus` の意図であり、
実際の model 値・別モデル名ではない — 2026-07-13 skill-effectiveness-audit で判明した表記揺れを訂正）、
逆に `dig` の Circuit Breaker（Transient/Permanent エラー分類・失敗シグネチャ 2 回一致での
早期検知・強制内省テンプレート）を `swarm-implement` の Fixer トリガーへ逆輸入した。`dig` の
Quick/Research/Full モード判定は `swarm-loop` の Phase -1（Quick/Interactive/Mission）に、対話的設計
インタビューと TDAD Iron Law・複雑度ガードは `swarm-loop` の PLAN フェーズと `swarm-implement` の
複雑度ガードにそれぞれ統合済み。`dig/SKILL.md` は後方互換のための薄いリダイレクトのみを残す。
