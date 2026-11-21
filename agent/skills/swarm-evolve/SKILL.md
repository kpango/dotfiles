---
name: swarm-evolve
description: Skill自己進化メタループ（SWARM.md §5）。軌跡/hookログから訂正パターンを検出し SKILL.md/hooks 差分を起案。トリガー `/swarm-evolve`・GATE自動起動。適用は人間承認必須。
allowed-tools: [Read, Grep, Glob, Bash, Write, Edit, Agent, Skill, SendMessage]
user-invocable: true
disable-model-invocation: false
---

# swarm-evolve — 人間承認必須のメタ進化ループ

開始前に `~/.claude/skills/_swarm-common/load.sh core --once` を実行して共通要約を読む（SWARM.md 全文 63KB は読まない。
§N の詳細が必要なときだけ、CORE.md の節インデックスの行範囲を `offset`/`limit` 付きで Read する）。
同一コンテキストで既読なら本文の代わりにスタブが返る。コンテキスト圧縮後は `--force`。

Drafter → Checker → **人間承認（省略不可）** → 適用、の 4 段階を必ず踏む。
Maker/Checker の verifier 独立性原則（SWARM.md §2）をそのまま流用する。

## 自動呼び出し時の範囲（`swarm-loop` Phase 5 GATE からの内部呼び出し）

`disable-model-invocation: false` はモデルが自然文からこの skill を起動できるかだけを制御し、`swarm-loop` が
Phase 5 GATE で内部呼び出しできるようにするための設定（`swarm-memory-sync` と同じ理由）。**Step 1〜3（証拠収集・
Drafter・Checker）と Step 4（Checker 合格分を人間へ提示するのみ）は自動実行してよい**が、Step 5（適用）は経路に
関わらず常に人間の個別承認後に実行する（「Step 4 まで自動」は提示の自動化で、承認の自動化ではない。自動呼び出しを
理由に Step 4/5 を省略・簡略化しない）。証拠 0 件・Drafter 提案 0 件・Checker 全却下のいずれも非ブロッキングで
スキップし、GATE 本来の release-gate 提示を妨げない。

## モデル階層投資の指針（参考、単一preprint・adversarial検証未完了）

harness-updating 能力（Drafter/Checker が良い差分を生成・検証する能力）はモデル階級に対し比較的フラットで、
実行担当（`swarm-implement` の Maker/Checker、Fixer）への投資の方が成果への効きが大きいという報告がある
（arXiv:2605.30621）。Drafter/Checker の階層引き上げが提案されたら、同じ予算を `swarm-implement` 側へ振る案と
比較する。ただし示すのは Drafter への追加投資の飽和のみで、Checker を弱める根拠にはならない（生成能力の飽和と
検証能力の必要性は別問題。verifier 独立性原則、SWARM.md §2 の階層差を弱める理由に使わない）。

## 手順

### 1. 証拠収集（機械的、解釈しない）

```bash
~/.claude/skills/swarm-evolve/scripts/collect-evidence.sh <repo-root> [days=30]
```

軌跡ログの全行 + hook rejection ログの集計（カテゴリ別件数・最終発生日）+ 直近の
SKILL.md 変更履歴を機械的に集めるだけのスクリプト。パターン判定はしない。

### 2. Drafter（`model: High` / OMP: `@good`、旧互換: `sonnet`）

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
  - `category`（仮説分類、1 提案 = 1 カテゴリで混在させない）: **A** Domain Learning（`.trail/` への知識追記）・
    **B** Skill Refinement（`agent/skills/`）・**C** Harness / Routing / Context Config（`agent/harnesses/`・
    `agent/models/`・hooks・extensions。omp / sol-pi / model-routing）。複数カテゴリに跨る変更は提案を分割する。
    `target` から導出されるカテゴリと食い違う宣言は `harness2-offline.py` が `category_mismatch` で棄却する
    （どれにも当たらない target は導出 null = `unclassified`、宣言があっても一致しないため棄却される）。
  - `proposed_diff`: 実際の diff（unified diff 形式、または Edit にそのまま使える old_string/new_string）
- 証拠に基づかない改善提案（一般論としての「ベストプラクティス」）は禁止。
- **proposed_diff の逐語自己検査（提出前必須、scope creep対策）**: 各提案の `new_string`/diff を証拠一式の
  引用箇所と突き合わせ、(a) 許可範囲・閾値・主体・回数等の具体的主張で証拠に無いものを足していないか、
  (b)「既存の許可範囲は変更しない」と自己申告する場合に実際は新しい許可経路や閾値緩和を作っていないか、
  (c) 引用元ミッション名・件数が証拠の実数と一致するかを1つずつ確認する。なお不確実な箇所は提案から削るか
  `target` のスコープを狭める（最終防御は Checker の逐語照合。Drafter の自己申告は信頼できないため
  Checker 到達前に自己検査を置く）。
- **既存ルールの証拠実在性audit（prune-capable受理ゲート、Phantom Guardrails対策）**: add-only の自己改善
  ループは、ルール形状の入力パターンから存在しない guardrail を LLM proposer が捏造し、それが持続・再発する
  （arXiv:2607.13083, confidence=medium, 単一preprint・独立再現なし）。対策として、対象 SKILL.md/hooks/SWARM.md
  の既存ルールのうち、**正当化根拠として明示引用されている軌跡ログ行・rejectionログ・実験値**が今回の証拠一式に
  実在しない（削除された・見つからない）ものは、削除または「根拠不明」への弱体化を `diff_type: prune` として
  提案してよい（毎回の実施は必須ではないが、気づいたものは黙殺しない）。
- 出力を `~/.claude/session-data/swarm/evolve-proposals/<日付>-draft.md` に Write する（却下・保留分は
  次回実行時の再提示抑制のためセッションを跨いで参照する必要があり、`/tmp/` ではなくここに置く）。

### 3. Checker（`model: XHigh` / OMP: `@review`、旧互換: `opus`、Drafter とは独立コンテキスト）

**Drafter の理由づけは渡さない。** 渡すのは「証拠一式」と「proposed_diff」のみ。この隔離は prompt
指示だけでなく機械的にも行う: draft から Checker へ渡す入力は手で編集せず、必ず
`~/.claude/skills/swarm-evolve/scripts/extract-checker-input.sh <draft.md> <提案見出しの部分文字列>`
の出力（`pattern` を含む地の文を機械的に除去し `evidence`/`target`/`diff_type`/diff コードブロックのみを
残す）をそのまま使う。反証指向で判定する:

- 証拠は本当に 2 回以上の独立した繰り返しを示しているか（同一インシデントの重複記録・言い換えに
  よる水増しでないか）。
- **`diff_type: prune` の場合のみ追加で**: 「この根拠は証拠一式に実在しない」という Drafter の主張の逆（実は
  実在する）を反証指向で探し、本当に実在しないと確認できた場合のみ承認する（ADD は「捏造していないか」、
  PRUNE は「本当に存在しないか」を検証する鏡像）。
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
**既知の限界**: grant はエージェントが Bash で直接発行できるため、人間承認の暗号学的証明ではなく、偶発的な
直接編集を防ぐインターロック＋`write-scope-log.jsonl` の監査証跡に過ぎない（SWARM.md §2「既知の未機械化
ギャップ」対応。`swarm-fable-gate.sh` の grant と同じ限界、詳細は `write-scope-lib.sh` 冒頭コメント）。
Edit の old_string 不一致等で再試行する場合も都度 grant を再発行する（単発消費）。
適用後:

- 通常の PostToolUse/Stop hook がそのまま走る（他の編集と同様、特別扱いしない）。
- 軌跡ログに追記する（`日付 | swarm-evolve: <pattern> | - | applied | <対象ファイルと変更概要>`）。
  自己改変というメタな行為自体を軌跡として残すことで、進化の進化（無限後退）を防ぎ追跡可能にする。
- 任意で `Skill` tool 経由で `swarm-memory-sync` を呼び、Checker が繰り返し発見したパターン（誤った
  diff_type 分類・証拠水増し等）が一般化可能なら auto-memory へ蒸留させてよい（dmi:false な skill 同士の
  直接呼び出し、SWARM.md §1 参照。人間承認は swarm-memory-sync 自身の設計どおり不要）。
- 却下・保留分は `~/.claude/session-data/swarm/evolve-proposals/` に残し、次回 `/swarm-evolve` 実行時に
  再提示しない（却下理由をファイル名に含めて識別する）。

## Harness² オフライン検証（任意、arXiv:2610.14224）

上流は 2 層: **タスクレベル再帰**（Propose→Probe→Compose）と**ハーネスレベル再帰**（経験リフレクタ）。
ハーネスは 8 コンポーネント（system prompt / guardrails / memory / tool guidance / subagents / skills / scripts /
plugins）のツリーとして扱う。本 script が移植するのは決定論部分のみ:

- Propose = Drafter、Probe = `harness2-offline.py`（Training/Held-Out probe + Security Monotonicity Gate）、
  Compose = Checker 合格差分の合成 diff の提示のみ（適用は 5. の grant 経路。同 script は対象を書かない）。
- **ツリー検証**（`validate_tree`）: always-on cap・skill の `description:` 必須と `name:` のディレクトリ一致・
  未トリガ skill・subagent の `name:`/`description:`・参照スクリプトの実在・`.py` のコンパイル。エラーは ` | `
  連結の 1 メッセージで、候補が**新規に導入した**エラーのみ `tree_invalid` として棄却する。
  候補なしの検証は `--check-tree`（`tree`/`census`/`always_on_chars` を JSON で返す）。
- **Compose**: 受理候補を base tree に適用した合成ツリーを再検証し、単一 diff にまとめる。同一パスへの
  競合は `fallback`（現ハーネス維持）として報告し、`diversity`（行 Jaccard 平均）で 1 本への収束を検出する。
- 常時ロード層（C1/C2/C4/C6）への差分は **Net Token Budget <= 0** を満たすまで Checker へ渡さない（分類・判定は
  同 script が SoT）。C6 はローカル保守則として**ファイル全体の delta** で課金し、上流の常時ロード面
  （name + description）の delta は `advertised_delta_tokens` として報告のみ行う（上流は本文を課金しない）。

```bash
collect-evidence.sh <repo-root> 30 --traces <変更対象の repo 相対 path> > traces.jsonl &&
  python3 -I -B <dotfiles>/agent/scripts/evolve/harness2-offline.py --traces traces.jsonl --candidates cand.json --dry-run --json
```

`--dry-run` を外すと repo の EXPERIENCE.md へ追記するため、人間承認後にのみ外す。

## 定期実行パターン（任意）

```
/loop 1d /swarm-evolve
```

証拠収集・提案作成の cadence を自動化するだけで、上記「4. 人間承認」の人間承認プロセスは loop 実行時も
変わらない。

## Handoff Contract

形式・規則・stats 記録: `~/.claude/skills/_swarm-common/load.sh handoff`（HANDOFF.md、正典）。`from: swarm-evolve`。
完了条件（`status: done` の定義）: 提案(差分起案)が出揃った。適用は Tier B grant 経路のまま(本契約は適用を代替しない)

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
