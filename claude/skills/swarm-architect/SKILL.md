---
name: swarm-architect
description: >-
  指揮・設計層 (Fable) の高級カード。VStream の LSH 動的パーティショニング等の高度なアーキテクチャ設計、
  分散インデックスの整合性設計、および 5 試行予算を超過した難局の突破指示を「提案書」として出力する。
  トリガー: (a) フル設計モード = 人間による /swarm-architect の明示招集のみ。(b) スポット診断モード =
  SWARM.md §1 スポット判断層の発動 4 条件 (Fixer 失敗後の最終診断 / blocked(design) 前の設計スクリーニング /
  complex 実装計画レビュー / Checker と決定論的検証の矛盾診断) に合致し、かつ budget-guard.sh --fable が
  許可した場合のみ swarm-loop / swarm-implement から自動起動できる (1 タスク 1 回・1 ミッション 2 回)。
  境界条件: いずれのモードでもコード編集・状態変更コマンドの実行は禁止。読み取り (Read/Grep/Glob/graphify) と
  提案書/診断書 Markdown の出力のみ。実装は swarm-implement、マージは swarm-release-gate へ委譲する。
allowed-tools: [Read, Grep, Glob, Bash, Write]
user-invocable: true
disable-model-invocation: false
---

# swarm-architect — 指揮・設計層 + スポット判断層

## 位置づけ

このスキルは Fable を使う層。トークン単価が最も高いため、起動を 2 モードで厳格に制限する:

- **フル設計モード**（従来）: 人間の明示招集のみ。成果物は提案書。
- **スポット診断モード**（Fable スポットルート、SWARM.md §1 スポット判断層）: `swarm-loop` /
  `swarm-implement` からの条件発火で自動起動できる。発動 4 条件・回数上限（1 タスク 1 回・
  1 ミッション 2 回）は SWARM.md §1 に規定され、起動前の `budget-guard.sh --fable` 通過が必須
  （機械的強制）。成果物は診断書のみ。

frontmatter の `disable-model-invocation: false` はスポット診断モードの条件発火を通すためであり、
フル設計モードの人間招集限定・発動 4 条件外での自動起動禁止は本文の規範として不変（swarm-evolve が
frontmatter を緩和しつつ本文で人間承認を必須とし続けるのと同じパターン）。

MAST 失敗分類（SWARM.md §2）では本層は主に「system design issues」カテゴリの是正を担う。検証層
（swarm-implement の Checker）を強化するだけでは仕様・設計に起因する失敗は解消しないことが実証されている
ため、`swarm-loop` の CHECKPOINT が `blocked(design)` と分類したタスクは、Checker の追加試行ではなく
本層への招集で解くべきシグナルである。

## スポット診断モード（自動発火）

0. **起動前ゲート（呼び出し元が実行）** — `swarm-loop` CHECKPOINT / `swarm-implement` は起動前に必ず:

   ```bash
   ~/.claude/skills/swarm-implement/scripts/budget-guard.sh --fable <task-id> [--mission=<mission-slug>]
   # exit 1 (FABLE_BUDGET_EXCEEDED) ならスポット起動せず、発動トリガーの従来経路へ
   # フォールバックする (SWARM.md §1: 条件1=ESCALATE / 2=blocked(design) / 3=既存complex承認 / 4=hook優先)
   ```

   mission-slug は `@fix_plan.md` の mission。存在しない場合（Quick モード等）は `--mission` を省略
   （タスク上限 1 回のみ適用）。続けて本モードを `Agent(model: 'fable')` で起動する際、prompt に
   `[fable-spot:<task-id>]`（budget-guard に渡したのと同一の task-id）を必ず含める —
   `swarm-fable-gate.sh` が grant を task 束縛で照合するため、マーカー無し・不一致はブロックされる。

1. **入力**は「仕様＋現在のコード状態＋直近の失敗証拠（エラー・矛盾する判定の**生出力**）」のみ。
   Maker/Fixer の弁明や失敗履歴の羅列は渡さない（Fixer と同じクリーンコンテキスト原則）。
2. **診断は読み取り専用**。診断書（下記フォーマット）を
   `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/proposals/<日付>-spot-<題名>.md` に Write し、
   同じ内容を呼び出し元へ構造化して返す。
3. **Fable Maker への昇格判断**: 診断書の「実装介入の要否」が「必要」で、かつ高難易度ゲート
   （タスク複雑度 `complex`、または Fixer 失敗後ルートでの発火）を満たす場合のみ、呼び出し元の
   `swarm-implement` が Maker を `model: 'fable'` で起動してよい（同一スポット消費の継続、追加消費なし）。
   実装は本 skill の外で行われ、本 skill 自身は診断書提示で終了する（コード編集禁止は不変）。
   Fable Maker の成果物も通常の判定集約（Checker(opus)・並行レビュー・決定論的検証）を通す。
4. **矛盾診断（トリガー 4）の制約**: Checker と決定論的検証の矛盾に対し「どちらが正しいか」の裁定・
   判定の上書きはしない。hook 優先の SWARM.md §2 原則は不変であり、出力は矛盾原因の診断と
   Checker 再判定への提示材料のみ。

### 診断書フォーマット（スポット診断モード）

```markdown
# Spot Diagnosis: <題名>

## トリガー（発動 4 条件のどれか＋根拠となる生の証拠）

## 根本原因分析（1 段落）

## 推奨アクション（優先順位つき、swarm-implement / swarm-loop が実行可能な粒度）

## 実装介入の要否（不要 / 必要 — 必要なら: 最小差分の範囲と高難易度ゲート判定の根拠）

## 人間へのエスカレーション要否（/swarm-architect フル設計モード招集を要すか）
```

## 手順（フル設計モード、人間招集限定）

1. **入力の確認** — 以下が揃っているか確認し、無ければ人間に要求する:
   - 秘書レポート（swarm-explore の出力）または問題の一次情報
   - 難局突破の場合: `@fix_plan.md` の失敗軌跡（5 試行分のエラーと試した対処）
2. **調査は読み取り専用** — `graphify query` / Read / Grep のみ。`Bash` は読み取り系コマンドに限る。
3. **提案書の出力** — `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/proposals/<日付>-<題名>.md` に Write し、
   同じ内容を会話内で人間に直接提示する。リポジトリ内には書かない（採択後に人間が移す）。会話内で提示済みの
   ため、このファイル自体をセッションを跨いで参照する必要はない。

## 提案書フォーマット

```markdown
# Proposal: <題名>

## 背景と問題定義（1 段落）

## 制約（Vald Law / Makefile 構造 / .hadolint.yaml 等のドメイン憲法との整合）

## 設計案（推奨案を先頭に。各案: 概要・トレードオフ・影響範囲）

## 実装計画（swarm-implement に渡せる粒度のタスク分割・依存順・検証方法）

## 難局突破の場合: 失敗軌跡の根本原因分析と、次の 5 試行で試すべき仮説の優先順位
```

## 禁止事項

- Edit / 状態変更 Bash（ビルド・インストール・git 書き込み）
- 実装作業への直接着手（提案書を出して終了する）
- 提案書なしの口頭回答のみで終わること

## Memory Protocol（Skill 自己メンテナンス）

手順 1（入力の確認）の一環として、`~/.claude/skill-memory/swarm-architect/MEMORY.md` が存在すれば読み、
過去に類似ドメイン（VStream パーティショニング等）で提示した設計判断・その後採否が分かっていればそれも
踏まえる。存在しなければ気にせず進めてよい。

提案書提示後、今回の提案固有の詳細ではなく今後の設計判断一般に通用する知見（繰り返し効く制約、過去に
却下された方向性とその理由等）が得られた場合のみ、`~/.claude/skill-memory/swarm-architect/`
（無ければ作成）の `MEMORY.md` に簡潔に追記する。個々の提案書全文はここに転記しない（`/tmp/.../swarm/
proposals/` が原本、本 Memory は再利用可能な設計知見の要約のみ）。一般化可能な学びが無ければ何も
書かずに終える。
