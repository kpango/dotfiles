---
name: swarm-architect
description: >-
  指揮・設計層 (Fable) の高級カード。VStream の LSH 動的パーティショニング等の高度なアーキテクチャ設計、
  分散インデックスの整合性設計、および 5 試行予算を超過した難局の突破指示を「提案書」として出力する。
  トリガー: 人間による /swarm-architect の明示招集のみ (コスト上の理由から自動発火は無効化されている)。
  境界条件: コード編集・状態変更コマンドの実行は禁止。読み取り (Read/Grep/Glob/graphify) と
  提案書 Markdown の出力のみ。実装は swarm-implement、マージは swarm-release-gate へ委譲する。
allowed-tools: [Read, Grep, Glob, Bash, Write, SendUserFile]
user-invocable: true
disable-model-invocation: true
---

# swarm-architect — 指揮・設計層（人間招集限定）

## 位置づけ

このスキルはセッションモデル（Fable）をそのまま使う唯一の層。トークン単価が最も高いため、
起動は人間の明示招集に限定され（`disable-model-invocation: true`）、成果物は**提案書のみ**。

MAST 失敗分類（SWARM.md §2）では本層は主に「system design issues」カテゴリの是正を担う。検証層
（swarm-implement の Checker）を強化するだけでは仕様・設計に起因する失敗は解消しないことが実証されている
ため、`swarm-loop` の CHECKPOINT が `blocked(design)` と分類したタスクは、Checker の追加試行ではなく
本層への招集で解くべきシグナルである。

## 手順

1. **入力の確認** — 以下が揃っているか確認し、無ければ人間に要求する:
   - 秘書レポート（swarm-explore の出力）または問題の一次情報
   - 難局突破の場合: `@fix_plan.md` の失敗軌跡（5 試行分のエラーと試した対処）
2. **調査は読み取り専用** — `graphify query` / Read / Grep のみ。`Bash` は読み取り系コマンドに限る。
3. **提案書の出力** — `/tmp/claude-swarm/proposals/<日付>-<題名>.md` に Write し、SendUserFile で人間に送付する。
   リポジトリ内には書かない（採択後に人間が移す）。

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
