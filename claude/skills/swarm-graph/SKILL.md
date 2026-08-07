---
name: swarm-graph
description: >-
  swarm-loop の姉妹 skill。`@fix_plan.md` の `## Tasks` テーブルを明示的な DAG (有向非巡回グラフ)へ
  機械コンパイルし、依存関係が満たされ次第複数タスクへ並列着手するフロンティア実行でミッションを
  完走させる。トリガー: 人間による `/swarm-graph` の明示招集、または `/swarm-meta` からの委譲
  (Skill tool 経由ではなく本 SKILL.md を Read して状態機械に従う方式)。swarm-loop と同格の
  重量級 skill のため自動発火は無効。境界条件: グラフ構造として不適合と機械判定されたミッション
  (タスク数 2 件以下、または依存の最大レベル幅が 1 の純粋な線形鎖)は Phase G-1 GRAPH-FIT ゲートが
  `swarm-loop/SKILL.md` の状態機械へフォールバックし、本 skill 内では続行しない。マージ・デプロイの
  実行判断は本 skill では行わず人間へ `/swarm-release-gate` 招集を要請して停止する。
allowed-tools:
  [
    Read,
    Edit,
    Write,
    Bash,
    Grep,
    Glob,
    Agent,
    Skill,
    TaskCreate,
    TaskUpdate,
    TaskList,
  ]
user-invocable: true
disable-model-invocation: true
---

# swarm-graph — フロンティア実行 DAG（swarm-loop 姉妹 skill）

## 1. 位置づけ

**swarm-loop の置換ではない**（詳細は frontmatter description 参照）— 両者は共存し、後述の
GRAPH-FIT ゲートが「どちらで実行すべきか」を機械判定する。

**研究根拠（1 段落要約）**: Loop 型の逐次実行は暗黙依存・回復意味論の無際限性・可変実行履歴という
構造的弱点を持つとの提案があるが実証はされていない (arXiv:2604.11378)。グラフ化の価値はモデル出力
品質そのものではなく inspect/repair/pause/resume/govern といった運用面にあり、採用は条件付きとすべき
とされる (arXiv:2607.19297)。一方で反証事例として、手続き型対話では in-context 自己オーケストレーション
が LangGraph 相当の明示グラフ構成に 15/15 で勝つ結果も報告されている (arXiv:2604.27891) — したがって
本 skill は「常にグラフを使う」設計ではなく、不適合なミッションを機械判定で `swarm-loop` へ返す
GRAPH-FIT ゲートを持つ。逐次的な性質のタスクへマルチエージェント構成を強制すると最大 -70% の性能
劣化が報告されており (arXiv:2512.08296)、動的グラフ化は明示的な予算ガード・検証・停止基準の負担を
増やす (arXiv:2603.22386) ため既存の `budget-guard` を継続強化する。依存グラフ駆動の再検証は「staged
update の不伝播」失敗モードへの対処として位置づけられる (arXiv:2606.31174)。

```
FIT判定(相0-2) ─▶ INIT ─▶ EXPLORE ─▶ GRAPH-PLAN(+FIT確定) ─▶ FRONTIER-EXECUTE ⇄ REPLAN(≤2) ─▶ GATE
```

## 2. Phase G-1: GRAPH-FIT（採用ゲート、機械判定・相 0〜2）

グラフ機構を使うべきミッションかどうかを **人間の直感ではなく `graph-compile.sh --fit` の exit code
のみ**で判定する。判定は必ず main リポジトリルートから実行する（worktree 内からの無引数起動は
split-brain を起こす、§9 参照）。

**相 0（Quick 事前スクリーニング）**: 目標が `swarm-loop` Phase -1 の Quick 判定基準（1 ファイル 15 行
以下・新規ロジックなし）に該当する場合は、`@fix_plan.md` や state-dir を作らず、直ちに
`swarm-loop/SKILL.md` を Read してその Quick 軽量パスに従う（判定基準は `swarm-loop` の表を参照し
複製しない。誤って重量級の graph 起動へ進む前の最軽量ゲート）。Quick 非該当なら通常どおり相 1 へ
進む。相 0 でカバーされない 3 タスク以上の Quick 相当ミッションは、相 1/相 2 の既存の
width/タスク数判定（UNFIT 判定）に委ねる。

**相 1（起動直後）**:

```bash
scripts/graph-compile.sh --fit
```

| exit code | 意味                                                 | 行動                                                                                                                                                                                  |
| --------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 6         | 有効な `## Tasks` 節が無い                           | 新規ミッション扱い。ゲートを保留し Phase G0 へ進む                                                                                                                                    |
| 0         | 既存 plan が graph として妥当                        | 再開ミッション。`graph-status.sh` で状態復元し Phase G3 以降を再開                                                                                                                    |
| 2         | UNFIT (タスク数<=2 または width==1)                  | **UNFIT フォールバック**（下記）                                                                                                                                                      |
| 3/4/5/7   | 既存 plan が壊れている（CYCLE 等）または PARSE_ERROR | PLAN 差し戻し（Phase G2 へ。exit 7 は plan ファイル自体の破損 — 不正 UTF-8・plan-path がディレクトリ・権限エラー等 — なので、まず `warnings` の原因を人間可読で報告してから修復する） |

**複数該当時の優先順位**: `graph-compile.sh` は複数の異常が同時に該当しうる場合、
`PARSE_ERROR`(exit 7、例外時に既に emit 済み) → `NO_TASKS`(exit 6、既に上で処理済み) →
`CYCLE`(exit 3) → `MISSING_DEP`(exit 4) → `VERIFIER_FLOOR`(exit 5) → (`--fit` 時のみ)
`UNFIT_FALLBACK_LOOP`(exit 2) → `OK`(exit 0) の順で先勝ちする（`graph-compile.sh` 実装コメント
参照）。上表の行動判断はこの優先順位を前提とする — 例えば CYCLE と MISSING_DEP が同時に成立する
plan では exit 3 (CYCLE) が報告され、exit 4 は報告されない。**正典は `graph-compile.sh` の実装
コメントであり本節はその要約に過ぎない** — 一方を変更した場合は必ずもう一方も追随させ、乖離
させないこと。

**UNFIT フォールバック（exit 2）**: フォールバック実行前に `~/.claude/skills/swarm-loop/SKILL.md` の
実在を確認し、無ければ人間へ報告して停止する（`swarm-meta` M2 の存在ガードと同型）。存在すれば
グラフ機構を使わず、`swarm-loop/SKILL.md` を Read してその状態機械（Phase 0 以降）に同じ目標で従う。
`Skill(swarm-loop)` の呼び出しは行わない —
`disable-model-invocation: true` の skill は Skill tool から起動できないため、本文を Read して直接
その手順に従う。フォールバックの事実と理由（fit 判定の生出力）を人間向け報告と `@fix_plan.md` に
記録し、`@fix_plan.md` ヘッダの `- graph-managed: true` を `- graph-managed: false (UNFIT降格 <日付>)`
に更新する（降格後の再開セッションを `graph-status.sh` へ誤誘導しないため）。フォールバック中の状態
復元は `swarm-loop` Phase 0 の `loop-status.sh` 手順を**上書きして `graph-status.sh` を使う**
（frontier/critical path/stale 等のグラフ固有状態を表示できるのは `graph-status.sh` のみのため。
`loop-status.sh` はグラフ構造を解釈しない。`graph-managed: false` 化以降は新規 v 節が増えない）。人間が
その場にいる Interactive 相当の場合は、続行前に「`/swarm-loop` での実行が適切」と提示して確認して
よい。

**相 2（Phase G2 でテーブル確定直後、必須）**: `--fit` を必ず再実行する。exit 2 → 上記 UNFIT
フォールバックを同様に行う。exit 3/4/5/7 → PLAN 差し戻し。exit 0 → Phase G3 へ進む。

## 3. Phase G0: INIT

- **新規ミッション**（`@fix_plan.md` 不在、相 1 が exit 6）: `swarm-loop/scripts/mission-init.sh
<slug> "<goal>" <interactive|mission> [self-improve-targets]` を再利用する（scale 判定基準は
  `swarm-loop` Phase -1 と同一。同じ `@fix_plan.md` を単一の真実源とし、自己改善ミッションの重複
  チェックも共有する）。ゴールが Claude Code 自体（設定/Skill/Agent/hooks）の改善・監査なら
  `swarm-loop` Phase 0 と同じ固定語彙（`CLAUDE.md`/`settings.json`/`hooks`/`agents-content`/
  `skills-content`/`multi-agent-mechanism`）でトークン化し第 4 引数に渡す（渡し忘れると共有している
  はずの重複チェックが配線されない）。生成直後に `@fix_plan.md` ヘッダへ `- graph-managed: true` 行を
  追記する（graph ミッションのマーカー）。
- **再開ミッション**（`@fix_plan.md` 既存、相 1 が exit 0）: `mission-init.sh` は呼ばない。
  `graph-status.sh` で状態を復元する。
- いずれの場合も `AGENTS.md` を読み（過去の学びの継承）、ベースラインテストの既存失敗有無を確認する
  （`swarm-loop` Phase 0 と同一規約）。
- **状態確認は `graph-status.sh` のみを使う** — frontier・critical path・stale 等のグラフ固有状態を
  表示できるのは `graph-status.sh` のみのため（`loop-status.sh` はグラフ構造を解釈しない。不変条件、
  §9）。

## 4. Phase G1: EXPLORE

`swarm-loop` Phase 1 と同一規約。Mission 規模は `swarm-explore`（Haiku 群 → 秘書集約）、Interactive
規模は単体 Haiku Explore Agent を dispatch する。Haiku の生ログを直接上位層へ流さず、必ず秘書レポート
（Mission）または JSON サマリー（Interactive）を経由する。Haiku 100 体探索は 1 ミッション原則 1 回。

## 5. Phase G2: GRAPH-PLAN

秘書レポート/Explore 結果を実装タスクへ変換する規約は `swarm-loop` Phase 2 と同一（mast 列の
`note` への転記・`blocked(design)` 運用・コア設計変更の事前ゲート）。加えて本 skill 固有の要件:

- **Interactive scale の設計インタビューは Tasks テーブル確定前に 1 回で完結させる**（`swarm-loop`
  Phase 2 の質問の具体化ルールに従う）。ノード単位の逐次インタビューはしない（フロンティア実行の
  並列着手を対話待ちでブロックしないため）。
- **`depends` 列の記入を必須とする**（swarm-loop では推奨だが本 skill では省略不可 — フロンティア
  実行の ready 集合計算の根拠そのものであるため）。
- **domain 語彙に `docs-wiring` を追加定義する**（文書・設定表の配線変更のみを指すタグ。
  `verify:skip`（Observe step のみの省略。決定論的検証は省略不可、§9）を許容する唯一の domain —
  `go-core`/`rust-core`/`k8s-infra`/`docker-eng` 等、他のいかなる domain タグにも `verify:skip` は
  許容されない）。
- テーブル確定後 `graph-compile.sh`（`--fit` なし）で検証する。CYCLE/MISSING_DEP/VERIFIER_FLOOR は
  いずれも PLAN 差し戻し（Phase G2 へ戻り、テーブルを修正して再検証）。
- 検証通過後、Phase G-1 相 2 の FIT 判定を実施する（`--fit`）。
- `graph-compile.sh` の `metrics`（width/depth/critical_path）を `## Graph Plan v1` 節として
  `@fix_plan.md` に記録する（plan version の永続化。REPLAN 時は `v<N+1>` として追記、§7）。
  **width の定義**: 全ノードを「ルートからの最長経路長」でレベル分けし、そのうち最大のレベル幅を
  width とする（最大反鎖の近似）。非連結な森（複数の独立したコンポーネント）であっても、
  コンポーネントごとに分けず全体で 1 つの値として計算する。Phase G-1 の UNFIT 判定（width==1）は
  この width 値を直接参照する。この定義の正典も `graph-compile.sh` の実装コメント（Kahn 法の
  ラウンド処理部分）であり本節は要約に過ぎない — §2 と同じ運用ルールで両方を追随させること。

## 6. Phase G3: FRONTIER-EXECUTE

ループ本体:

1. main リポジトリルートで `graph-compile.sh`（引数なし）を実行し `ready` 配列を取得する。
2. **最大 3 並列**で各 ready ノードを `swarm-implement` 契約に従い実行する（Test Maker →
   Maker(`model: sonnet`) → Checker(`model: opus`) + 並行レビュー(`code-reviewer`/`vald-reviewer`/
   `security-audit`) → 決定論的検証 → Observe・判定行強制。fable スポット 4 条件は `swarm-implement`
   側の既存配線をそのまま使う）。
   - **worktree はオーケストレーターが確保する**: 各 ready ノードの Maker をスポーンする前に
     `swarm-implement/scripts/worktree-alloc.sh <node-id>` で隔離済み worktree を割り当て、パスを
     Maker への入力として渡す。
   - **TaskCreate で進捗を可視化する**: 各 ready ノードの Maker スポーン時に TaskCreate でノード単位
     のタスクを登録し、done/blocked への遷移で TaskUpdate する（複数ノード同時進行の進捗可視化。
     allowed-tools に既に含まれる）。
3. ノード終了ごとに（成功・予算超過とも）`@fix_plan.md` の該当行の `status`/`attempts` を更新する。
4. `ready` が空になるまで 1〜3 を繰り返す。`ready` が空になったら Phase G4 の ESCALATE 行列で
   GATE/ESCALATE を判定する。**フェーズバリアは置かない** — あるノードの Checker 中に
   別の ready ノードの Maker が並行して走ってよい（フロンティア実行の本質）。

**single-writer 規約**: `@fix_plan.md` への書き込みは **オーケストレーター（swarm-graph 本体、main
tree 常駐）のみ**が行う。Maker/Checker（worktree 内で動作）は `@fix_plan.md` に一切触れない。
`graph-compile.sh` / `graph-status.sh` は常に main リポジトリルートから起動する（worktree 内の
`git rev-parse --show-toplevel` は worktree 根を返すため、worktree からの無引数起動は split-brain を
起こす）。

**上流成果物の伝播**: 上流ノードの成果物に依存するノードの Maker 入力には、上流タスクの最終成果物
（diff 要約・生成物パス）を構造化して渡す（「staged update の不伝播」失敗モードへの対策）。

## 7. Phase G4: REPLAN（有界・明示）

ノードが `blocked` に至ったら MAST 3 分類（SWARM.md §2、`swarm-loop` Phase 4 と同じ表）でルーティング
する（Fable スポット設計スクリーニングを含む）。

構造変更が必要な場合のみ **replan** を行う（**1 ミッション最大 2 回**）:

1. 新しい `## Tasks (v<N+1>)` 節を `@fix_plan.md` **末尾に追記**する。旧節は改変しない
   （append-only）。
2. 継続するノードはステータスごと新節へ転記する。
3. replan の理由と差分ノードを新節冒頭の HTML コメントに記す。
4. 再コンパイル（CYCLE/MISSING_DEP/VERIFIER_FLOOR の検証込み）+ Phase G-1 相 2 の FIT 再判定を行う。
5. 上流ノードを修正した場合は `graph-compile.sh --stale <id>` の閉包に該当する `done` ノードを
   `stale` へ更新する（新節内で。stale は依存が全て done なら `ready` に自動的に戻る、フロンティア
   実行との整合）。オーケストレーターがこの更新を書き忘れた場合、該当ノードは `pending` のまま
   残り、後続の frontier 実行で再処理されうる（警告機構はまだ無い）。

**残課題**: replan 回数の上限（1 ミッション最大 2 回）は現時点ではオーケストレーターの手動カウント
に依存し機械強制はない。機械化は本タスクでは見送り、GATE で人間へ報告する。

**ready が空になった場合の ESCALATE 行列**（`swarm-loop` Phase 4 で実証済みの停止条件の graph 版）:

| 状況                                                                                      | 行動                  |
| ----------------------------------------------------------------------------------------- | --------------------- |
| `ready` が空 かつ 全ノード done                                                           | Phase G5 GATE へ      |
| `ready` が空 かつ 未完ノードが残る（blocked が過半、または残ノードが全て blocked に依存） | ループ停止 → ESCALATE |
| Stop hook から 5 回差し戻し                                                               | ループ停止 → ESCALATE |

**ESCALATE**: `@fix_plan.md` に全 blocked ノードの失敗軌跡・試した仮説・MAST 分類を書き、人間へ報告して
停止する。エスカレーションなしに同じループを回し続けることを禁止する。

**silent な既存行の書き換え・履歴の削除は禁止**（append-only 原則、`swarm-loop` の
「隣接コードの改善・整形・リファクタは行わない」原則の plan ファイル版）。

## 8. Phase G5: GATE → REPORT

`swarm-loop` Phase 5 と同一の手順に従う（release-gate 招集要請・`swarm-evolve` 証跡収集・完了メニュー・
`AGENTS.md` 追記 → `self-improve-register.sh`（自己改善ミッションのみ）→ `swarm-memory-sync` →
worktree 回収 → `@fix_plan.md` アーカイブ）。手順詳細は `swarm-loop/SKILL.md` Phase 5 を参照する。
本 skill 固有の追加事項のみ以下に記す:

- **`budget-guard --reset` は全ノードの task-id について繰り返し実行する**（`--mission=<slug>` を
  必ず付ける。1 ノード = 1 task-id のため、単一 task-id のリセットでは済まない）。
- SWARM.md §0 は 3 エントリ体制（loop/graph/meta、人間招集限定）へ改訂済み（2026-07-30）。本 skill と
  SWARM.md/CLAUDE.md の相互参照に食い違いを発見した場合のみ GATE で人間へ提示する。
- `@fix_plan.md` ヘッダに `- meta-managed: true` があるミッションでは、完了メニュー提示時に「終了後に
  `swarm-meta` の M3 RECORD（`harness-record.sh`）を忘れないこと」を併記する。

## 9. ループ不変条件（全 Phase 共通）

`swarm-loop` と共通の不変条件（モデルルーティング明示・Haiku 生ログ遮断・自己申告終了禁止・
`@fix_plan.md` が唯一の進行状態・一時ファイルは `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/` 以下・
Surgical changes）に加え、グラフ固有の不変条件:

- **plan version は append-only**（詳細は §7 参照）。
- **replan は 1 ミッション最大 2 回**（機械強制なし、残課題は §7 参照）。
- **`ready` 集合は `graph-compile.sh` の出力のみを根拠にする** — LLM の記憶で ready を判断しない
  （decision の唯一の権威は決定論的ツール、SWARM.md §2 の延長）。
- **`@fix_plan.md` は single-writer**（オーケストレーターのみが書き込む、§6）。
- **状態確認は `graph-status.sh` のみ**（frontier・critical path・stale 等のグラフ固有状態を表示
  できるのは `graph-status.sh` のみのため。`loop-status.sh` はグラフ構造を解釈しない）。
- `graph-compile.sh` / `graph-status.sh` は常に main リポジトリルートから起動する。

## 10. Memory Protocol

`~/.claude/skill-memory/swarm-graph/MEMORY.md`（`swarm-implement` の同節と同型）:

- Phase G0 開始時、このファイルが存在すれば読む。
- skill 運用一般の知見（ミッション固有の詳細ではなく、今後の `/swarm-graph` 起動全般に有用な学び）
  のみを追記する。
- ファイルが無ければ何も書かない（初回起動時に空ファイルを作る必要はない）。
