---
name: swarm-evolve
description: >-
  Skill 自体のメタ進化ループ（SWARM.md §5「Skill自体のメタループ」の実装）。軌跡ログと hook
  rejection ログを走査し、複数ミッションで繰り返されている訂正パターンを検出して SKILL.md / hooks への
  差分を起案する。トリガー: 人間による /swarm-evolve の明示招集、`/loop <interval> /swarm-evolve` による
  定期起動、または `swarm-loop` Phase 5 GATE からの内部呼び出し（Step 1=証拠収集→Step 2=Drafter→
  Step 3=Checker→Step 4=Checker 合格分を人間へ提示するのみ、まで自動実行。Step 5=適用は常に人間が
  個別承認する。詳細は本文「自動呼び出し時の範囲」参照）。
  境界条件: **いかなる差分も人間の明示承認なしに適用しない**（docs-only であっても例外なし、トリガー経路に
  依らず不変）。エージェント自身の行動規範ファイルを書き換えるという性質上、swarm-architect/swarm-release-gate
  と同格の最高警戒レベルで扱う。コード（vald/dotfiles のプロダクトコード）の変更はこの skill の対象外
  （swarm-implement を使う）。
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent, Skill, SendMessage]
user-invocable: true
disable-model-invocation: false
---

# swarm-evolve — 人間承認必須のメタ進化ループ

開始前に `~/.claude/SWARM.md` を Read する（CLAUDE.md の常時 import ではなく本 skill が個別に
読み込む設計。統治規約・verifier 独立性原則・MAST 分類等、本 skill 全体の前提はそこにある）。

Drafter → Checker → **人間承認（省略不可）** → 適用、の 4 段階を必ず踏む。
Maker/Checker の verifier 独立性原則（SWARM.md §2）をそのまま流用する。

## 自動呼び出し時の範囲（`swarm-loop` Phase 5 GATE からの内部呼び出し）

`disable-model-invocation: false` は「モデルが自然文からこの skill を起動できるか」だけを制御する設定であり、
`swarm-loop` が Phase 5 GATE で本 skill を内部的に呼び出せるようにするための変更（`swarm-memory-sync` と
同じ理由）。**Step 1（証拠収集）→ Step 2（Drafter）→ Step 3（Checker）→ Step 4（Checker 合格分を人間へ
提示するのみ、適用は含まない）までは自動実行してよい**が、Step 5（適用）は本文「4. 人間承認」「5. 適用」の
記述どおり、経路に関わらず常に人間の個別承認を経てから実行する。「Step 4 まで自動実行」は提示という
表示行為の自動化を指し、人間の承認そのものを自動化する意味ではない。自動呼び出しであることを理由に
Step 4/5 を省略・簡略化しない。証拠 0 件・Drafter 提案 0 件・Checker 全却下のいずれの場合も非ブロッキングで
スキップし、GATE 本来の release-gate 提示を妨げない。

## 手順

### 1. 証拠収集（機械的、解釈しない）

```bash
~/.claude/skills/swarm-evolve/scripts/collect-evidence.sh <repo-root> [days=30]
```

軌跡ログの全行 + hook rejection ログの集計（カテゴリ別件数・最終発生日）+ 直近の
SKILL.md 変更履歴を機械的に集めるだけのスクリプト。パターン判定はしない。

### 2. Drafter（`model: sonnet`）

証拠一式を渡し、次を求める:

- 同一の根本原因・同一の訂正カテゴリが **証拠内に 2 回以上**現れているパターンのみを列挙する
  （1 回しか無い単発事象は過学習を避けるため対象外 — この skill は反復実証されたパターンのみを対象にする）。
- パターンごとに:
  - `pattern`: 何が繰り返されているか（具体的に）
  - `evidence`: 該当する軌跡ログの行 or rejection ログのエントリを引用
  - `target`: 変更対象ファイル（`SKILL.md` / `hooks/*.sh` / `SWARM.md` 等）
  - `diff_type`: `docs-only`（説明追加・曖昧さ解消・誤った相互参照の修正など、許可事項・状態機械・
    閾値を変えない）・`behavioral`（禁止事項の追加削除、allowed-tools、試行回数・並列数等の閾値、
    状態遷移ロジックの変更）・**`prune`**（既存のルール・禁止事項・引用の削除または弱体化。下記
    「既存ルールの証拠実在性audit」参照）のいずれかに分類する。
  - `proposed_diff`: 実際の diff（unified diff 形式、または Edit にそのまま使える old_string/new_string）
- 証拠に基づかない改善提案（一般論としての「ベストプラクティス」）は禁止。
- **既存ルールの証拠実在性audit（prune-capable受理ゲート、Phantom Guardrails対策）**: add-onlyの
  自己改善ループは、ルール形状の入力パターンから存在しないguardrailをLLM proposerが捏造し、それが
  持続・再発する（arXiv:2607.13083, confidence=medium, 単一preprint・独立再現なし）。この対策として、
  証拠収集で得た対象SKILL.md/hooks/SWARM.mdの既存ルールのうち、**その正当化根拠として明示的に引用
  されている軌跡ログ行・rejectionログ・実験値**が今回の証拠一式の中に実在しない(削除された・
  該当エントリが見つからない)ものを見つけたら、そのルールの削除または「根拠不明」への弱体化を
  `diff_type: prune` として提案してよい(毎回の実施は必須ではないが、証拠収集の過程で気づいた場合は
  黒塗りにしない)。
- 出力を `~/.claude/session-data/swarm/evolve-proposals/<日付>-draft.md` に Write する（却下・保留分は
  次回実行時の再提示抑制のためセッションを跨いで参照する必要があり、`/tmp/` ではなくここに置く）。

### 3. Checker（`model: opus`、Drafter とは独立コンテキスト）

**Drafter の理由づけは渡さない。** 渡すのは「証拠一式」と「proposed_diff」のみ。この隔離は prompt
指示だけでなく機械的にも行う: draft から Checker へ渡す入力は手で編集せず、必ず
`~/.claude/skills/swarm-evolve/scripts/extract-checker-input.sh <draft.md> <提案見出しの部分文字列>`
の出力（`pattern` を含む地の文を機械的に除去し `evidence`/`target`/`diff_type`/diff コードブロックのみを
残す）をそのまま使う。反証指向で判定する:

- 証拠は本当に 2 回以上の独立した繰り返しを示しているか（同一インシデントの重複記録・言い換えに
  よる水増しでないか）。
- **`diff_type: prune` の場合のみ追加で**: Drafter の「この根拠は証拠一式に実在しない」という主張の
  逆（実は実在する）を反証指向で確認する — Drafter 自身が見落とした箇所に該当根拠が実際にあるかを
  探す。本当に実在しないことを確認できた場合のみ承認する（ADD 提案の逐語的忠実性チェックの鏡像:
  ADD は「捏造していないか」、PRUNE は「本当に存在しないか」を検証する）。
- `proposed_diff` は指摘されたパターンにのみ対応しているか（無関係な変更が紛れ込んでいないか、
  スコープが証拠の範囲を超えていないか）。
- `diff_type` の分類は正しいか（挙動を変える差分を `docs-only` に偽装していないか — これが最も
  重大な誤分類なので優先的に確認する）。
- **証拠引用の逐語的忠実性**: `proposed_diff` の `new_string` が証拠一式に無い数値・実験内訳・確度表現
  （例:「adversarial 検証済み」と「一次ソースのみ」の混同、証拠に無い実験条件・モデル数の補完）を
  捏造・水増ししていないか、証拠一式と `new_string` を逐語比較する。
- 対象ファイルの既存原則（`SWARM.md`、Vald Law、`.hadolint.yaml` の意図的 ignore 等）と矛盾しないか。
- 不合格なら理由を返し、その提案だけを却下する（他の提案は個別に判定を続ける）。

出力は `~/.claude/session-data/swarm/evolve-proposals/<日付>-verdict.md` に各提案の `approved: bool` と理由。

### 4. 人間承認（省略不可・全提案が対象）

Checker 合格分のみを人間に提示する。提示フォーマット:

```markdown
## 提案 N: <pattern>

- 証拠: <軌跡ログ行 or rejection ログの引用、件数>
- 分類: docs-only | behavioral
- 対象: <ファイル>
- 差分:
  <diff>
```

**docs-only であっても人間承認なしに適用しない。** 分類は人間が優先順位をつけるための情報であり、
自動適用の免除条件ではない（要件どおり）。人間が個別に 承認/却下/保留 を選べるようにする。

### 5. 適用

承認された提案のみ Edit で適用する。対象が Tier B 保護パス（`write-scope-lib.sh` の
`write_scope_is_protected` 判定に一致するファイル）の場合、Edit の**直前**に
`~/.claude/skills/swarm-implement/scripts/budget-guard.sh --write-scope-grant <file-path>` で
単発 grant（TTL 300s）を発行する — `swarm-write-scope-gate.sh`（PreToolUse:Write|Edit|MultiEdit|
NotebookEdit hook）がこの grant を要求するため、grant 無しの Edit は hook に exit 2 で拒否される。
**既知の限界**: grant発行自体はエージェントがBashで直接呼び出せるため、これは人間承認そのものを
暗号学的に証明するものではなく、偶発的・カジュアルな直接編集を防ぐインターロック＋
`write-scope-log.jsonl`による監査証跡である（SWARM.md §2「既知の未機械化ギャップ」対応、
ただし完全な機械強制ではないことを明記する。`swarm-fable-gate.sh`のgrant機構と同じ限界。
詳細は`write-scope-lib.sh`冒頭コメント参照）。
Edit の old_string 不一致等で再試行する場合はその都度 grant を再発行する（単発消費のため）。
適用後:

- 通常の PostToolUse/Stop hook がそのまま走る（他の編集と同様、特別扱いしない）。
- 軌跡ログに追記する（`日付 | swarm-evolve: <pattern> | - | applied | <対象ファイルと変更概要>`）。
  自己改変というメタな行為自体を軌跡として残すことで、進化の進化（無限後退）を防ぎ追跡可能にする。
- 任意で `Skill` tool経由で `swarm-memory-sync` を呼び出し、本ラウンドで Checker が繰り返し発見した
  パターン（誤ったdiff_type分類・証拠水増し等）が一般化可能なら auto-memory へ蒸留させてよい
  （dmi:falseなskill同士のSkill tool直接相互呼び出し、SWARM.md §1「dmi:false skill間のSkill tool
  相互呼び出し」参照。人間承認はswarm-memory-sync自身の既存設計どおり不要）。
- 却下・保留分は `~/.claude/session-data/swarm/evolve-proposals/` に残し、次回 `/swarm-evolve` 実行時に
  再提示しない（却下理由をファイル名に含めて識別する。セッションを跨ぐ判断材料のため `/tmp/` ではなく
  `.claude/` 配下に置く）。

## 定期実行パターン（任意）

```
/loop 1d /swarm-evolve
```

証拠収集・提案作成の cadence を自動化するだけで、上記「4. 人間承認」の人間承認プロセスは loop 実行時も
変わらない。

## 禁止事項

- 人間承認なしの SKILL.md / hooks / SWARM.md への適用（docs-only でも例外なし）
- 単発事象（証拠 1 件のみ、上記「2. Drafter」の「2 回以上」要件の裏返し）に基づく提案
- Drafter の主観的理由づけを Checker に渡すこと（verifier 独立性の毀損。`extract-checker-input.sh`
  経由が既定であり、これを介さない手渡しは禁止事項に当たる）
- Drafter/Checker の名前付き Agent 呼び出しが `idle_notification` のみ・要求した出力形式（Checker合否等）
  欠落で停滞した場合に再スポーンすること（SWARM.md §2「名前付きAgent呼び出しの停滞対応」参照。
  `SendMessage` で当該エージェントへ再要求する）
- vald/dotfiles のプロダクトコードへの変更（対象は本基盤の運用ファイルのみ。コードは `swarm-implement`）
- 却下された提案を理由を変えずに再提出すること
