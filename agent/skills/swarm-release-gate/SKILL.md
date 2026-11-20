---
name: swarm-release-gate
description: マージ・デプロイ・破壊的変更の最終ゲート。トリガー `/swarm-release-gate`・Phase 5/G5起動・「マージして」。verify.sh全パス＋人間最終承認まで実行禁止。
allowed-tools: [Read, Write, Bash, Grep, Glob]
user-invocable: true
disable-model-invocation: false
---

# swarm-release-gate — 強制検証つき最終ゲート

開始前に `~/.claude/skills/_swarm-common/load.sh core --once` を実行して共通要約を読む（SWARM.md 全文 63KB は読まない。
§N の詳細が必要なときだけ、CORE.md の節インデックスの行範囲を `offset`/`limit` 付きで Read する）。
同一コンテキストで既読なら本文の代わりにスタブが返る。コンテキスト圧縮後は `--force`。

## 手順

1. **検証の実行** — 対象リポジトリのルートで:

   ```bash
   ~/.claude/skills/swarm-release-gate/scripts/verify.sh
   ```

   - vald: `make test/pkg` 等の既存 make ターゲットを実行（Makefile 構造には触れない）
   - dotfiles: 全 JSON validity・全 Dockerfile hadolint（`.hadolint.yaml` 準拠）・zsh 構文検査・
     swarm 回帰テスト 8 本（`agent/skills`）・`trail check`（Trail 未導入時は SKIP）・Harness²
     オフライン検証（`agent/scripts/test-harness2-offline.sh`）
   - 詳細ログはスクリプトが `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/` に書き、コンテキストへは要約と
     失敗末尾のみ返る

2. **判定**:
   - `ALL CHECKS PASSED` 以外 → マージ禁止。失敗ログを添えて swarm-implement の修正ループへ差し戻す。
   - 全パス → 変更内容の要約（diff stat・影響範囲・検証結果）を提示し、**人間の最終承認を待つ**。
     **注意**: 自動検証は既知の回帰を防ぐことには強いが、新規の失敗モードを事前に予見する力は乏しいという
     実運用知見がある（監査の事前予防率は低く、事後の再発防止率が高いという非対称性。`SWARM_REFERENCES.md`）。
     したがって `ALL CHECKS PASSED` を「安全性の証明」として扱わず、diff の中でも初見のロジック変更・
     新しい依存関係・既存パターンから外れる箇所を明示的に指摘し、人間が重点的にパターンマッチできるようにする。

3. **承認後のみ**: gh CLI で PR 作成、または人間が指定した統合操作を実行する。
   force-push・protected branch への直接 push は security-gate が遮断する（回避を試みない）。

## 禁止事項

- 検証スキップ・検証失敗状態でのマージ / push / PR マージ
- 人間の承認なしの統合操作
- verify.sh を経由しない「手元では通った」形式の判断

## Handoff Contract

形式・規則・stats 記録: `~/.claude/skills/_swarm-common/load.sh handoff`（HANDOFF.md、正典）。`from: swarm-release-gate`。
完了条件（`status: done` の定義）: verify.sh 全パス。人間最終承認は既存仕様のまま本契約で変更しない

## Memory Protocol

共通手順: `~/.claude/skills/_swarm-common/load.sh memory`（MEMORY_PROTOCOL.md）。対象: `~/.claude/skill-memory/swarm-release-gate/MEMORY.md`。
本 skill 固有の観点: 頻出する `verify.sh` 失敗パターンと原因（診断を速める参考情報）。**この Memory は検証結果のキャッシュ・代替ではない**（`verify.sh` の実行省略は「境界条件」「禁止事項」に反する）。
