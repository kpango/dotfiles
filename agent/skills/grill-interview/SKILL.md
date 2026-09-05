---
name: grill-interview
description: Interactive design-tree interview protocol for cognitive drift prevention, clarifying ambiguities, and synthesizing ADR and CONTEXT.md before implementation.
allowed-tools: [Read, Grep, Glob, Bash, Write]
user-invocable: true
---

# grill-interview — 設計ツリー対話型面談プロトコル

認知ドリフト（Cognitive Drift: 実装が進むにつれて初期仕様や暗黙の前提から乖離する現象）を未然に防止し、
曖昧な要件・エッジケース・アーキテクチャ上のトレードオフをコード作成前に合意形成するための設計面談スキル。

面談完了時に、決定事項を **ADR（Architecture Decision Record）** および **`CONTEXT.md`（ドメイン用語・不変条件集）**
として自律合成し、後続の実装層（Maker / Worker）および検証層（Checker / Reviewer）への入力契約を確定する。

---

## 1. コア原則 (Core Principles)

1. **認知ドリフトの予防 (Cognitive Drift Prevention)**:
   コードを1行も書く前に、設計上の分岐点と境界条件をすべて洗い出し、決定事項の合意を形成する。
2. **1問1答ツリー走査 (1-Question-at-a-Time)**:
   質問リストを一括で投げてはならない（情報過多による認知負荷と焦点の拡散を防ぐ）。
   決定ツリーの親ノードの回答が確定した後に、その回答に紐づく子ノードの質問を 1 題ずつ行う。
3. **推奨付き選択肢の提示 (Explicit Option Recommendation)**:
   「どうしますか？」という自由記述のオープン質問は禁止。
   必ず 2〜4 個の具体的かつ排他的な選択肢を提示し、明確な根拠とともに `[Recommended]` バッジを明記する。
4. **不変条件の即時ドキュメント化 (Living Invariants)**:
   面談で決定したドメイン規約・不変条件は `CONTEXT.md` に、設計トレードオフと採択理由は `docs/adr/ADR-xxxx-slug.md` に
   即座に永続化し、エージェント間の前提ズレ（MAST カテゴリ ii: inter-agent misalignment）を構造的に遮断する。

---

## 2. 質問優先度階層 (Question Priority Hierarchy)

質問は以下の優先度順にツリーを降下しながら行う。下位の具体論（テストケース等）から質問してはならず、
上位の境界・設計方針が固まってから下位の質問を展開する。

```
Level 1: Architecture & Boundaries (アーキテクチャ・責務境界・モジュール分割・データフロー)
    ↓
Level 2: Behavior & Edge Cases (入出力仕様・エッジケース・異常系・エラー伝播・障害回復)
    ↓
Level 3: Consistency & Compatibility (既存規約・命名規則・後方互換性・API安定性)
    ↓
Level 4: Implementation & Tests (ファイル配置・依存ライブラリ・テスト方針・検証コマンド)
```

---

## 3. 4段階ツリー面談ワークフロー (4-Phase Tree Elicitation)

### Phase 1: 曖昧性・スコープ検出 (Ambiguity & Scope Detection)

- ユーザー要求またはタスク定義から、以下の要素を自動抽出する:
  - 曖昧な表現（「よしなに」「高速に」「柔軟に」「必要に応じて」）
  - 暗黙の前提（特定OS依存、シングルスレッド前提、特定の環境変数等）
  - スコープ境界の未確定点（「どこまで今回のPRに含めるか」）
- 検出結果に基づき、設計上の意思決定ツリー（Decision Tree）を構築する。

### Phase 2: 技術・アーキテクチャ選択 (Technical & Architectural Choices)

- 1問1答形式でツリーを走査する。
- 質問フォーマット:
  ```markdown
  ### [Grill Q{N}] {質問タイトル}

  {背景・なぜ今この質問が必要かの説明}

  - [ ] **Option A** {概要}: {メリット・デメリット}
  - [x] **Option B [Recommended]** {概要}: {推奨理由・トレードオフ評価}
  - [ ] **Option C** {概要}: {メリット・デメリット}

  **推奨理由**: {Option B を推奨する根拠（既存コードの整合性、シンプルさ、YAGNI適合性など）}
  ```
- ユーザーの回答を取得し、次のツリーノードへ進む。

### Phase 3: ドメイン用語・不変条件の抽出 (`CONTEXT.md`)

- インタビューを通じて合意されたドメインモデル、状態遷移、制約条件を `CONTEXT.md` に集約する。
- 複数エージェントが協調動作する際の共通コンテキスト（Single Source of Truth）として機能する。

### Phase 4: ADR 合成 (`docs/adr/ADR-xxxx-slug.md`)

- 面談の決定事項、検討された代替案、採用理由、トレードオフを標準 ADR 形式で永続化する。
- ADR 番号は `docs/adr/` 配下の既存 ADR 番号の最大値 + 1（初回は `ADR-0001-slug.md`）を自動付番する。

---

## 4. 成果物標準スキーマ (Standard Schemas)

### 4.1 CONTEXT.md 標準スキーマ

リポジトリルートまたは対象モジュール直下に配置する。

```markdown
# CONTEXT — {モジュール名 / ドメイン名}

## 1. ドメイン用語集 (Domain Glossary)

- **{用語 1}**: {厳密な定義とスコープ}
- **{用語 2}**: {厳密な定義とスコープ}

## 2. システム不変条件 (System Invariants)

- **Invariant-1 (事前条件)**: {常に満たされるべき入力条件・状態}
- **Invariant-2 (状態遷移)**: {許可される状態遷移と禁止される遷移}
- **Invariant-3 (事後条件 / 保証)**: {操作完了時に保証される結果}

## 3. 責務境界と入出力規約 (Boundary & Contracts)

- **許可される依存方向**: {コンポーネント A -> コンポーネント B (逆方向は禁止)}
- **エラー処理規約**: {エラー伝播方式、Sentinel Error の定義}

## 4. 既知の制約と非目標 (Constraints & Non-Goals)

- **制約**: {プラットフォーム制約、パフォーマンス目標値など}
- **Non-Goals**: {今回のスコープ外として明示的に除外された機能}
```

### 4.2 ADR 標準スキーマ (`docs/adr/ADR-xxxx-slug.md`)

```markdown
# ADR-{xxxx}: {タイトル}

- **ステータス**: Accepted (または Proposed / Superseded)
- **日付**: YYYY-MM-DD
- **対象コンポーネント**: {対象ファイル / モジュール / パッケージ}
- **決定者**: {kpango / agent名}

## 1. コンテキストと問題提起 (Context & Problem Statement)

{解決すべき課題、背景、なぜ現状維持では不十分なのか}

## 2. 決定推進要因 (Decision Drivers)

- Driver 1: {例: メモリフットプリントの最小化}
- Driver 2: {例: 既存 API との後方互換性維持}
- Driver 3: {例: 外部依存の最小化 (YAGNI / Ponytail 原則適合)}

## 3. 検討された選択肢 (Considered Options)

- **Option 1**: {概要}
- **Option 2 [Selected]**: {概要}
- **Option 3**: {概要}

## 4. 決定結果と根拠 (Decision Outcome & Rationale)

{Option 2 を選択した理由、トレードオフ、失われるものと得られるもの}

## 5. 不変条件と影響 (Invariants & Consequences)

### 正の影響 (Positive Consequences)

- {改善点 1}

### 負の影響・トレードオフ (Negative Consequences)

- {制約事項や受け入れた不利益}

### システム不変条件 (Invariants)

- {本決定により新たに導入・固定される規約}

## 6. 検証方法 (Verification Method)

- {本 ADR の決定がコードに正しく反映されているかを機械的に検証するコマンドやテスト手法}
```

---

## 5. 面談プロトコルの終了条件とハンドオフ

1. **終了判定**:
   - Level 1 から Level 4 までの主要な決定ノードがすべて走査・回答済みであること。
   - ユーザーから明示的な合意（「これで進めてください」「LGTM」等）が得られたこと。
2. **ハンドオフ**:
   - `docs/adr/ADR-xxxx-slug.md` を書き込み。
   - `CONTEXT.md` を書き込み（または更新）。
   - 実装層（`teamwork_preview_worker` / `swarm-implement`）へ制御を引き継ぐ。
