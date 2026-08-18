# 影響範囲分類 (impact-A/B/C)

変更のデグレ risk を3段階で表す共通語彙。`code-reviewer` / `vald-reviewer` の重点指定、および `swarm-loop` の
Phase 1 昇格チェック（影響ファイル数基準）を補完する精密な判定として使う。分類する側は本ファイルを SoT とし、
各所で定義を再掲しない。

## 分類

| 分類         | 定義                                             | 典型例                                                 |
| ------------ | ------------------------------------------------ | ------------------------------------------------------ |
| **impact-A** | 新規 file / 葉領域のみ。既存 code からの参照なし | 新規 file の追加、未参照の新 package / 新 symbol       |
| **impact-B** | 既存 code に使用が足される。既存 logic は不変    | 新要素の呼び出し追加、wiring への行追加                |
| **impact-C** | 既存 logic の変更。デグレ risk あり              | 挙動変更、共有 code path の変更、既存 signature の変更 |

- 判定単位は file ではなく**変更 symbol**。同一 file 内で新規 symbol 追加（A）と既存 logic 変更（C）が混在する場合は C
- 1 変更が複数に跨る場合は**最も重い分類を採る**（C > B > A）

## 判定手順

### 完全判定（実装計画がある場合）

1. 変更予定の file / symbol を列挙する
2. 各 symbol の参照元を grep する（`codegraph_search` / `graphify query` があれば優先して使う）
3. 「対象 symbol → 参照元」の対応表とともに3分類する

### 簡易判定（diff だけがある場合 — レビュー時）

`--stat` と diff 本体から機械的に落とす:

| diff の状態                                                          | 分類     |
| -------------------------------------------------------------------- | -------- |
| 新規 file のみ（既存 file の変更行が0）                              | impact-A |
| 既存 file への追加のみ（削除行が0 かつ既存 symbol の本体に変更なし） | impact-B |
| 既存 file の既存行に変更・削除がある                                 | impact-C |

簡易判定は**安全側に倒す** — 判別がつかない変更は impact-C として扱う（review 観点の重点指定側に倒れる）。

## 使い方

- `code-reviewer` / `vald-reviewer` への委譲プロンプトに分類結果を含め、impact-C を correctness /
  test-adversarial 観点の重点対象として明示する
- `swarm-implement` の Checker への入力に添える場合、Maker の自己評価は伴わせない（judged 側の独立性を保つ）
