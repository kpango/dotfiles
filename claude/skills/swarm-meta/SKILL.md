---
name: swarm-meta
description: >-
  ミッション着手前に「どのハーネス（swarm-loop / swarm-graph）で走るか」を決定論第一で選択・検証し、
  選択先ハーネスへ委譲し、実行後の実績を registry に記録して次回選択を改善する 2 段階進化のメタハーネス層。
  トリガー: 人間による `/swarm-meta` の明示招集のみ（費用高感度エントリのため自然文からの自動発火は
  無効化されている）。境界条件: 実行中のハーネス自己改変は行わない（唯一の例外は swarm-graph の
  GRAPH-FIT UNFIT 時の swarm-loop への 1 回限りの保守的降格）。SKILL.md/hooks/検証構成テンプレート自体の
  変更は本 skill の対象外であり `/swarm-evolve`（人間承認必須）へ証拠起案（draft 出力）までを引き継ぐ。
  委譲先候補 `swarm-graph` が存在しない環境では `swarm-loop` へ保守的降格する。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent, Skill]
user-invocable: true
disable-model-invocation: true
---

# swarm-meta — メタハーネス選択・検証・委譲・実績記録

## 1. 位置づけ

`swarm-loop`（0 段: ミッション実行の状態機械そのもの）・`swarm-graph`（1 段: 並行探索型の代替ハーネス、
並行タスク新設中）に対し、`swarm-meta` は **2 段目 = メタ層**である（機能の詳細は本 skill の frontmatter
`description` および下記フロー図を参照）。

**研究根拠（1 段落要約）**: per-mission のアーキテクチャ選択は固定最適化構成に勝る（MaAS vs ADAS/AFlow:
GAIA で +18% vs +2〜3%、ADAS は vanilla を下回る事例あり arXiv:2502.04180）。タスク特性からのトポロジー
予測は 260 構成の 87% で成立する（arXiv:2512.08296）— メタ層による選択の先行実証。ただし meta-harness の
実像はオフライン探索＋実行可能評価（ADAS/AFlow, arXiv:2603.22386/2408.08435）であり、探索は有界（ADAS は
30 反復/ドメイン）・sandbox＋人間検査つきである。DGM は reward hacking を実際に起こした（検証マーカー
除去・テスト実行偽装, arXiv:2505.22954）ため検証は二重化する: 着手前の best-effort lint
（`harness-lint.sh`）＋実行時の hook（dispatch 先の PostToolUse/Stop hook が最終権威）。METR の報告
（成功実行の 16%+ がチートで失格・LLM モニタは jailbreak 可能）は決定論的検証第一権威の根拠を補強する。
Three Laws（Endure（安全）> Excel（性能保持）> Evolve（最適化）、辞書式優先, arXiv:2507.21046 系）により、
LLM は推薦をより保守的な側にのみ上書きできる（規範。機械強制ではない）。proxy 単一指標の最適化は隠れ
目標との乖離を拡大するため（specification gaming 系、記録方法は下記 5. M3 RECORD 参照）。
LLM 生成コンテキストファイルは -3%/+20% cost（Gloaguen et al.）であるため設定・メモリファイルの自動生成は
禁止する。進化済み構成は LLM backbone 更新で silently degrade するため、registry に model-version を
記録する。MOSS（arXiv:2605.22794、一次ソースのみ・adversarial 検証未完了）は本番 agent harness
（OpenClaw + DeepSeek V3.2）のソースレベル自己書き換えで、単一進化サイクルにより 4task claweval
benchmark 平均が 0.2526→0.6100 に向上した実運用実績を報告するが、自己改変の適用（container swap）
には人間の明示コマンド（`moss evo apply`）による承認が必須というゲート設計であり、本 skill の
Tier B 人間承認原則を独立に裏づける一次資料である一方、reward hacking 対策自体は明示されず
health-probe rollback のみに留まるという限界も併せ持つ。PACE（arXiv:2606.08106、同じく一次ソース
のみ・adversarial 検証未完了）は自己改変の受理判定を単純な貪欲採択ではなく sequential hypothesis
testing（testing-by-betting e-process）として再定式化し、素朴な貪欲採択が決定論的評価下で
30-42%・確率的評価下で 72-100% の誤採択（false-commit）を起こすのに対しユーザー設定の α 以下に
抑制できることを示し、本 skill の「単一 proxy スコアによる構成最適化を禁ずる」（下記 7.）を補強する。

```
PROFILE ─▶ SELECT(+lint) ─▶ DISPATCH ─▶ (ハーネス実行) ─▶ RECORD ─▶ EVOLVE-FEED（非ブロッキング）
```

### Tier A / Tier B（冒頭で明示する 2 層構造・強制の実態）

- **Tier A（承認不要・全て可逆）**: 既存ブロック（swarm-loop / swarm-graph）からの構成選択、
  `harness-registry.tsv` への追記/置換、`/tmp/` への harness-plan.json 出力。本 skill の通常動作は
  すべて Tier A に属する。
- **Tier B（人間承認必須）**: SKILL.md / hooks / 検証構成テンプレート自体の変更。本 skill はこの層に
  一切触れず、`/swarm-evolve` への draft 起案（EVOLVE-FEED、下記 6.）までで停止する。ただしこの境界・
  「保守側上書きのみ」「レンズ削減禁止」（下記 7.）はいずれも規範であり、`swarm-meta` 自身への機械強制は
  無い。`harness-lint.sh` は harness-plan の**着手前 best-effort スクリーニング**であり `swarm-meta`
  自身の実行時 Write/Edit を検査しない — 実際の書き込み阻止は dispatch 先ハーネスの PostToolUse/Stop
  hook が実行時の最終権威として担う。`harness-lint.sh` が機械強制するのは絶対フロア＝ VERIFIER_FLOOR /
  ROUTING / BUDGET_BOUNDS / WRITE_SCOPE（best-effort、完全性は保証しない）のみである。既知の残課題
  （best-effort の限界）として、`re_toolcall` の複数行にまたがるツール呼び出し検出の制限・`budget` 値の
  負数検証の欠如・`deterministic` 配列要素の型検証の欠如があるが、いずれも致命的ではなく将来の改善候補
  として記録するに留める。

### SWARM.md §0 との関係

自走ループの入口を `/swarm-loop` 単独から `/swarm-loop` ・ `/swarm-graph` ・ `/swarm-meta`（いずれも
人間招集限定）へ拡張する SWARM.md §0 の改訂は**本 skill の外**（本ミッションの wiring タスク）で行われ、
Phase 5 GATE の人間承認を prerequisite とする。`swarm-meta` 自身は SWARM.md に一切書き込まない。
**`swarm-meta` の成果物と §0/CLAUDE.md の wiring diff は同一 GATE で不可分（all-or-nothing）に承認・
適用し、片方のみの適用を禁ずる**（skill だけ merge され §0 が旧文言のまま残る不整合ウィンドウを作らない）。

なお `allowed-tools` の `Skill` は **dispatch 用ではない**（dispatch は Read＋インライン追従、下記 4.）。
インライン追従中に起動先ハーネスが呼ぶ下位 skill（`swarm-explore` / `swarm-implement` / `swarm-secretary`、
いずれも `disable-model-invocation: false`）のためにのみ使う。

## 2. M0 PROFILE

```bash
~/.claude/skills/swarm-meta/scripts/harness-select.sh --profile-only "<goal>"
```

この出力（`profile.signals.{parallel,sequential,risk,primary}` / `est_tasks` / `langs`）を会話内に記録
する。決定論的な語彙一致・正規表現のみで抽出され、LLM は関与しない。exit は常に 0（推薦を含まないため
強制判定の対象外）。

## 3. M1 SELECT

```bash
~/.claude/skills/swarm-meta/scripts/harness-select.sh "<goal>"
```

の推薦（`recommendation.harness` / `lenses` / `budget` / `rationale`）を第一候補とする。

推薦ロジック（`harness-select.sh` 実装、決定論・LLM 不使用）: (B) harness 決定は語彙一致数
`parallel_n`（並行/並列/複数/全域/全体/一括/監査/audit/横断/swarm 等）と `sequential_n`（順に/手順/逐次/
段階的/一つずつ/1ファイル/リネーム/typo 等）を比較し、上から最初に真になった規則で確定する:
`sequential_n > parallel_n` または `est_tasks<=2` → `swarm-loop`、`parallel_n > sequential_n` かつ
（`est_tasks` 未検出または `>=3`）→ `swarm-graph`、どちらでもなければ保守デフォルト（Endure>Excel>Evolve）
で `swarm-loop`。(C) `harness=swarm-graph` の場合のみ、同一 `profile.signals.primary` の過去 registry
行のうちパース可能な行の過半数（`blocked_majority*2 > parseable`）が blocked>done なら `swarm-loop` へ
降格する。registry の各行は独立レコードとして扱われ、不正 UTF-8 の行は当該行のみ skip し件数を rationale
に記録する（`registry-unreadable: N lines skipped (decode errors)`）。列数不足の行は当該行のみ沈黙 skip
する（rationale には記録されない）。ファイル自体が読めない場合のみ全体を registry-unreadable として
記録する。いずれの場合も all-or-nothing で握り潰さない（`harness-status.sh` の registry 集計も同じ
fail-safe パターン）。

セッション（LLM）による上書きは**保守側のみ許可**する: `swarm-graph → swarm-loop` への降格・レンズの
追加・予算の削減。**逆方向（swarm-loop → swarm-graph への昇格・レンズの削除・予算の拡大）はしない**
（規範であり機械強制はない点を明記する — `harness-lint.sh` はレンズ削減や予算拡大それ自体を検出する
チェックではなく、あくまで絶対フロアの検査に留まる）。上書きした場合は理由を harness-plan の
`rationale` 配列に追記する。

確定した harness-plan.json を次の形式で Write する:

```
/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/harness-plan-<slug>.json
```

続けて lint を通す:

```bash
~/.claude/skills/swarm-meta/scripts/harness-lint.sh /tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/harness-plan-<slug>.json
```

**lint が非 0 を返した plan では dispatch しない**（exit code に応じて該当箇所を修正し再度 lint を
通す。優先順は harness-lint.sh 契約どおり 1→4→5→2→3）。

## 4. M2 DISPATCH

1. 選択ハーネスの SKILL.md の実在を確認する（`~/.claude/skills/<harness>/SKILL.md`）。無ければ
   `swarm-loop` へ保守的降格し、rationale に `harness-unavailable:<name>` を記録する（`harness-select.sh`
   の存在ガードと同じ判定を dispatch 直前にもう一度行う — select 実行後に環境が変化した場合の防御）。
   `swarm-loop` 自体も無い場合は他に降格先が無いため推薦値は `swarm-loop` のまま変えず、rationale の
   警告文言（`... (swarm-loop also unavailable, no other option)`）で異常を明示するに留める（使用不可と
   宣言した harness を推薦してしまう自己矛盾ではなく、この状態では直後の Read 自体が失敗し異常が可視化
   される、という設計。`harness-select.sh` の case16 参照）。
2. **`Skill()` は呼ばない。** 選択した SKILL.md を Read し、その状態機械（`swarm-loop` なら Phase -1
   以降、`swarm-graph` なら Phase G-1 以降）に同じ目標で従う。`swarm-loop`/`swarm-graph` は
   `disable-model-invocation: true` のため Skill tool から起動不能であり、人間の `/swarm-meta` 明示
   招集そのものが自走ループ起動の承認を構成する。
3. harness-plan の要約を `@fix_plan.md` の `## Harness Plan` 節に永続化する（`mission-init.sh` 実行後）。
   同時に `@fix_plan.md` ヘッダへ `- meta-managed: true` 行を追記する（dispatch 先ハーネスの GATE
   完了メニューが M3 RECORD の実行リマインドを表示するためのマーカー。Quick 分岐では `@fix_plan.md`
   自体が無いため付与しない）。
   **Quick 分岐**: dispatch 先の `swarm-loop` が Phase -1 で **Quick** と判定した場合、`@fix_plan.md` は
   生成されないため本ステップ（`## Harness Plan` 節への永続化・`meta-managed` マーカー付与）は行わず、
   harness-plan の要約は会話内報告に代える（`harness-select.sh` の `scale` は推薦の既定値であり、
   `swarm-loop` Phase -1 の判定が優先される — select は Quick を判定しない）。
4. GATE・ESCALATE・人間承認は**起動先ハーネスのもの**が働く。`swarm-meta` は追加のゲートを作らない。
5. **実行中のハーネス切替は禁止**する。唯一の例外: `swarm-graph` が GRAPH-FIT で UNFIT を返した、または
   replan 上限で行き詰まった場合に、`swarm-loop` へ 1 回だけ保守的降格する（rationale を記録する）。

## 5. M3 RECORD

ミッション終了（GATE 完了 / ESCALATE）後、実行する:

```bash
~/.claude/skills/swarm-meta/scripts/harness-record.sh <mission-slug> <harness> <profile-primary> <model-version> "<outcome>"
```

`model-version` はセッションモデル ID（例: `claude-fable-5`）。`outcome` は `done=N blocked=N attempts=N
replans=N` の多次元サマリであり、**単一スコア化しない・実測値のみ**を記録する（捏造禁止、下記 7.）。

Quick で終了したミッションの RECORD は outcome を `quick=1` 形式で記録する（Tasks テーブルが無いため
done/blocked 集計は生成されない）。`harness-record.sh` 自体は `outcome` 引数の形式を検証しない
（TAB/CR/LF の正規化のみを行う自由形式の文字列として受け取る）ため、`done=N blocked=N ...` も
`quick=1` も呼び出し側の慣習の一つに過ぎない。

## 6. M4 EVOLVE-FEED（非ブロッキング）

反復判定は目視の registry 読解ではなく決定論スクリプトで行う:

```bash
~/.claude/skills/swarm-meta/scripts/harness-status.sh [profile-primary]
```

（registry の集計・harness 別傾向・model-version 別件数を表示し、`profile-primary` 指定時は同型の
blocked>done が 2 回以上反復していれば REPEAT を表示する。表示ツールであり exit 0 固定。）
REPEAT が示された、すなわち同一 `profile-primary` で同型の失敗・手直しが**2 回以上**反復していたら、
`swarm-evolve` の draft スキーマ（`pattern` / `evidence` / `target` / `diff_type` / `proposed_diff`）で
次に Write する:

```
~/.claude/session-data/swarm/evolve-proposals/<日付>-swarm-meta-draft.md
```

**`swarm-meta` は Checker 起動も適用も行わない。** 次回 `/swarm-evolve` 実行時に Step 1（証拠収集）が
既存 draft として検出し、Step 3（Checker）→ Step 4（人間承認）の通常フローに乗る（`swarm-evolve` 側への
受理配線の追加は本タスクの範囲外）。反復パターンが 0 件なら黙ってスキップする（非ブロッキング）。

## 7. 禁止事項

- **実行中の自己改変**（唯一の例外は上記 4. の GRAPH-FIT UNFIT 時の 1 回限りの降格）。
- `SKILL.md` / `hooks/*.sh`（具体的には `swarm-fable-gate.sh` / `swarm-stop-verify.sh` /
  `swarm-post-edit-lint.sh`）/ `SWARM.md` / `budget-guard.sh` / `verify.sh` への書き込み
  （`harness-lint.sh` の WRITE_SCOPE 正規表現 `PROTECTED` と同じ保護対象。`swarm-meta` 自身にも
  適用される規範であり、実行時は dispatch 先 hook が最終権威）。
- **検証レンズの削減**（追加のみ可）。
- 単一 proxy スコアによる構成最適化。
- `AGENTS.md` / `CLAUDE.md` 等コンテキストファイルの自動生成。
- registry 実績の捏造（`harness-record.sh` は実測値のみを記録する）。
- `swarm-evolve` の Step 3（Checker）以降の代行。

## 8. Memory Protocol（Skill 自己メンテナンス、AGENTS.md とは別軸）

`AGENTS.md`/`@fix_plan.md` はプロジェクト単位のミッション軌跡であり、個々のタスクの学びを記録する。
これとは別に、`~/.claude/skill-memory/swarm-meta/MEMORY.md` には**本 skill 自体の運用パターン**
（ハーネス推薦が実際の実行結果と乖離した傾向、registry 降格の閾値が実態に合わなかった事例、
存在ガードが誤って発火した状況等）を蓄積する。開始前に存在すれば読み、判断材料にする。存在しなければ
気にせず進めてよい。

完了処理（M3 RECORD の直後）の一部として、今回のタスク固有の詳細ではなく本 skill の運用一般に通用する
知見が得られた場合のみ追記する。プロジェクト固有の学びは引き続き `AGENTS.md` へ、本 skill 自体の運用
知見のみここへ、と役割を分ける。一般化可能な学びが無ければ何も書かずに終える。
