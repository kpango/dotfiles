# Grilling 設計ツリー面談規則 (Cognitive Drift Prevention)

認知ドリフト（Cognitive Drift）を防止し、要件の曖昧さやアーキテクチャ上の不確実性をコード実装前に
解消するための共通規範。

## 1. 適用条件 (Trigger Conditions)

`impact-scope.md` に基づく影響範囲分類において、以下に該当するタスクはコード変更（Write/Edit）に着手する前に
**Grilling 設計面談プロトコル（`Skill(grill-interview)`）**の実施を必須とする:

1. **impact-C（既存ロジックの変更・デグレリスクあり）**:
   共有コードパスの変更、公開 API/シグネチャの変更、アーキテクチャ方針の決定を伴うもの。
2. **impact-B のうち曖昧性を含むもの**:
   既存コードへの新要素呼び出し追加であっても、複数の設計選択肢が存在する場合やエラー処理規約が未定義の場合。

※ 完全な自明バグ修正（typo修正や単一の1行修正で選択肢が存在しないもの）および impact-A の純粋な独立新規スクリプトで仕様が確定しているものは対象外。

## 2. 遵守義務 (Mandatory Invariants)

1. **質問一括投下の禁止 (1-Question-at-a-Time)**:
   質問リストを一括で提示してはならない。決定ツリーの親ノードから順に 1 問ずつ質問し、回答に応じて次のノードを深掘りする。
2. **推奨選択肢の明示 (Recommended Options)**:
   すべての質問には 2〜4 個の具体的な選択肢を含め、必ず `[Recommended]` バッジと推奨理由を付与する。
3. **優先順位の遵守**:
   Architecture & Boundaries → Behavior & Edge Cases → Consistency & Compatibility → Implementation & Tests の順序で質問を展開する。
4. **成果物の合成義務**:
   設計面談完了後、Phase 3 EXECUTE（実装）へ入る前に以下を出力・永続化する:
   - アーキテクチャ決定事項: `docs/adr/ADR-xxxx-slug.md`
   - ドメイン用語・システム不変条件: `CONTEXT.md`

## 3. レビューと検証における扱い

- `code-reviewer` および `teamwork_preview_reviewer` (Opus Checker) は、impact-C の変更に対して対応する ADR または CONTEXT.md の存在を確認し、決定事項と実装の乖離がないかを検査する。
- 乖離が検出された場合は MAST カテゴリ (i) system design issues または (ii) inter-agent misalignment として差し戻す。
