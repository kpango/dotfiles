---
name: swarm-evolve
description: >-
  Skill 自体のメタ進化ループ（SWARM.md §5「Skill自体のメタループ」の実装）。AGENTS.md の軌跡と hook
  rejection ログを走査し、複数ミッションで繰り返されている訂正パターンを検出して SKILL.md / hooks への
  差分を起案する。トリガー: 人間による /swarm-evolve の明示招集、`/loop <interval> /swarm-evolve` による
  定期起動、または `swarm-loop` Phase 5 GATE からの内部呼び出し（Step 1-4=証拠収集→Drafter→Checker→
  人間提示のみを自動実行、Step 5=適用は常に人間が個別承認する。詳細は本文「自動呼び出し時の範囲」参照）。
  境界条件: **いかなる差分も人間の明示承認なしに適用しない**（docs-only であっても例外なし、トリガー経路に
  依らず不変）。エージェント自身の行動規範ファイルを書き換えるという性質上、swarm-architect/swarm-release-gate
  と同格の最高警戒レベルで扱う。コード（vald/dotfiles のプロダクトコード）の変更はこの skill の対象外
  （swarm-implement を使う）。
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent]
user-invocable: true
disable-model-invocation: false
---

# swarm-evolve — 人間承認必須のメタ進化ループ

「自己進化」を「自己申告なしの自己改造」にしないため、Drafter → Checker → **人間承認（省略不可）** →
適用、の 4 段階を必ず踏む。Maker/Checker の verifier 独立性原則（SWARM.md §2）をそのまま流用する。

## 自動呼び出し時の範囲（`swarm-loop` Phase 5 GATE からの内部呼び出し）

`disable-model-invocation: false` は「モデルが自然文からこの skill を起動できるか」だけを制御する設定であり、
`swarm-loop` が Phase 5 GATE で本 skill を内部的に呼び出せるようにするための変更（`swarm-memory-sync` と
同じ理由）。**Step 1（証拠収集）→ Step 2（Drafter）→ Step 3（Checker）→ Step 4（Checker 合格分の人間提示）
までは自動実行してよい**が、Step 5（適用）は本文「4. 人間承認」「5. 適用」の記述どおり、経路に関わらず
常に人間の個別承認を経てから実行する。自動呼び出しであることを理由に Step 4/5 を省略・簡略化しない。
証拠 0 件・Drafter 提案 0 件・Checker 全却下のいずれの場合も非ブロッキングでスキップし、GATE 本来の
release-gate 提示を妨げない。

## 手順

### 1. 証拠収集（機械的、解釈しない）

```bash
~/.claude/skills/swarm-evolve/scripts/collect-evidence.sh <repo-root> [days=30]
```

`AGENTS.md` の軌跡テーブル全行 + hook rejection ログの集計（カテゴリ別件数・最終発生日）+ 直近の
SKILL.md 変更履歴を機械的に集めるだけのスクリプト。パターン判定はしない。

### 2. Drafter（`model: sonnet`）

証拠一式を渡し、次を求める:

- 同一の根本原因・同一の訂正カテゴリが **証拠内に 2 回以上**現れているパターンを列挙する
  （1 回しか無いものは対象外 — 単発事象を過学習しない）。
- パターンごとに:
  - `pattern`: 何が繰り返されているか（具体的に）
  - `evidence`: 該当する AGENTS.md の行 or rejection ログのエントリを引用
  - `target`: 変更対象ファイル（`SKILL.md` / `hooks/*.sh` / `SWARM.md` 等）
  - `diff_type`: `docs-only`（説明追加・曖昧さ解消・誤った相互参照の修正など、許可事項・状態機械・
    閾値を変えない）か `behavioral`（禁止事項の追加削除、allowed-tools、試行回数・並列数等の閾値、
    状態遷移ロジックの変更）かを分類する。
  - `proposed_diff`: 実際の diff（unified diff 形式、または Edit にそのまま使える old_string/new_string）
- 証拠に基づかない改善提案（一般論としての「ベストプラクティス」）は禁止。**この skill は反復実証された
  パターンのみを対象にする**。
- 出力を `~/.claude/session-data/swarm/evolve-proposals/<日付>-draft.md` に Write する（却下・保留分は
  次回実行時の再提示抑制のためセッションを跨いで参照する必要があり、`/tmp/` ではなくここに置く）。

### 3. Checker（`model: opus`、Drafter とは独立コンテキスト）

**Drafter の理由づけは渡さない。** 渡すのは「証拠一式」と「proposed_diff」のみ。反証指向で判定する:

- 証拠は本当に 2 回以上の独立した繰り返しを示しているか（同一インシデントの重複記録・言い換えに
  よる水増しでないか）。
- `proposed_diff` は指摘されたパターンにのみ対応しているか（無関係な変更が紛れ込んでいないか、
  スコープが証拠の範囲を超えていないか）。
- `diff_type` の分類は正しいか（挙動を変える差分を `docs-only` に偽装していないか — これが最も
  重大な誤分類なので優先的に確認する）。
- 対象ファイルの既存原則（`SWARM.md`、Vald Law、`.hadolint.yaml` の意図的 ignore 等）と矛盾しないか。
- 不合格なら理由を返し、その提案だけを却下する（他の提案は個別に判定を続ける）。

出力は `~/.claude/session-data/swarm/evolve-proposals/<日付>-verdict.md` に各提案の `approved: bool` と理由。

### 4. 人間承認（省略不可・全提案が対象）

Checker 合格分のみを人間に提示する。提示フォーマット:

```markdown
## 提案 N: <pattern>

- 証拠: <AGENTS.md行 or rejection ログの引用、件数>
- 分類: docs-only | behavioral
- 対象: <ファイル>
- 差分:
  <diff>
```

**docs-only であっても人間承認なしに適用しない。** 分類は人間が優先順位をつけるための情報であり、
自動適用の免除条件ではない（要件どおり）。人間が個別に 承認/却下/保留 を選べるようにする。

### 5. 適用

承認された提案のみ Edit で適用する。適用後:

- 通常の PostToolUse/Stop hook がそのまま走る（他の編集と同様、特別扱いしない）。
- `AGENTS.md` に軌跡を追記する（`日付 | swarm-evolve: <pattern> | - | applied | <対象ファイルと変更概要>`）。
  自己改変というメタな行為自体を軌跡として残すことで、進化の進化（無限後退）を防ぎ追跡可能にする。
- 却下・保留分は `~/.claude/session-data/swarm/evolve-proposals/` に残し、次回 `/swarm-evolve` 実行時に
  再提示しない（却下理由をファイル名に含めて識別する。セッションを跨ぐ判断材料のため `/tmp/` ではなく
  `.claude/` 配下に置く）。

## 定期実行パターン（任意）

```
/loop 1d /swarm-evolve
```

これは「定期的に証拠を集めて提案を作る」cadence を自動化するだけで、**適用フェーズの人間承認は
loop によってスキップされない**。毎回 Checker 合格分が人間に提示され、無応答なら何も適用されず終わる。

## 禁止事項

- 人間承認なしの SKILL.md / hooks / SWARM.md への適用（docs-only でも例外なし）
- 単発事象（証拠 1 件のみ）に基づく提案
- Drafter の主観的理由づけを Checker に渡すこと（verifier 独立性の毀損）
- vald/dotfiles のプロダクトコードへの変更（対象は本基盤の運用ファイルのみ。コードは `swarm-implement`）
- 却下された提案を理由を変えずに再提出すること
