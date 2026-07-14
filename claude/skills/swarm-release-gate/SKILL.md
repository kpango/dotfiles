---
name: swarm-release-gate
description: >-
  マージ・デプロイ・破壊的変更の直前に必ず通す最終ゲート。トリガー: 人間による /swarm-release-gate の
  明示招集のみ (自律的なマージ・デプロイを防ぐため自動発火は無効化)。「マージして」「PR を出して本流に入れて」
  「リリースして」という依頼も本 skill 経由で処理する。
  境界条件: scripts/verify.sh (既存 make ターゲット経由の強制検証) が全パスするまでマージ・push を絶対に行わない。
  検証はスクリプトの実行結果 (標準出力) のみを根拠とし、自己申告・記憶を根拠にしない。
  本番 namespace への kubectl/helm 操作は扱わない (security-gate hook が別途ブロックする)。
allowed-tools: [Read, Bash, Grep, Glob]
user-invocable: true
disable-model-invocation: true
---

# swarm-release-gate — 強制検証つき最終ゲート

## 手順

1. **検証の実行** — 対象リポジトリのルートで:

   ```bash
   ~/.claude/skills/swarm-release-gate/scripts/verify.sh
   ```

   - vald: `make test/pkg` 等の既存 make ターゲットを実行（Makefile 構造には触れない）
   - dotfiles: 全 JSON validity・全 Dockerfile hadolint（`.hadolint.yaml` 準拠）・zsh 構文検査
   - 詳細ログはスクリプトが /tmp に書き、コンテキストへは要約と失敗末尾のみ返る

2. **判定**:
   - `ALL CHECKS PASSED` 以外 → マージ禁止。失敗ログを添えて swarm-implement の修正ループへ差し戻す。
   - 全パス → 変更内容の要約（diff stat・影響範囲・検証結果）を提示し、**人間の最終承認を待つ**。
     **注意**: 自動検証は既知の回帰を防ぐことには強いが、新規の失敗モードを事前に予見する力は乏しいという
     実運用知見がある（監査の事前予防率は低く、事後の再発防止率が高いという非対称性。SWARM.md §8）。
     したがって `ALL CHECKS PASSED` を「安全性の証明」として扱わず、diff の中でも初見のロジック変更・
     新しい依存関係・既存パターンから外れる箇所を明示的に指摘し、人間が重点的にパターンマッチできるようにする。

3. **承認後のみ**: gh CLI で PR 作成、または人間が指定した統合操作を実行する。
   force-push・protected branch への直接 push は security-gate が遮断する（回避を試みない）。

## 禁止事項

- 検証スキップ・検証失敗状態でのマージ / push / PR マージ
- 人間の承認なしの統合操作
- verify.sh を経由しない「手元では通った」形式の判断
