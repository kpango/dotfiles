---
name: swarm-release-gate
description: >-
  マージ・デプロイ・破壊的変更の直前に必ず通す最終ゲート。トリガー: 人間による /swarm-release-gate の
  明示招集のみ (自律的なマージ・デプロイを防ぐため自動発火は無効化)。「マージして」「PR を出して本流に入れて」
  「リリースして」という依頼も本 skill 経由で処理する。
  境界条件: scripts/verify.sh (既存 make ターゲット経由の強制検証) が全パスするまでマージ・push を絶対に行わない。
  検証はスクリプトの実行結果 (標準出力) のみを根拠とし、自己申告・記憶を根拠にしない。
  本番 namespace への kubectl/helm 操作は扱わない (security-gate hook が別途ブロックする)。
allowed-tools: [Read, Write, Bash, Grep, Glob]
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
   - 詳細ログはスクリプトが `/tmp/${CLAUDE_CODE_SESSION_ID:-manual}/swarm/` に書き、コンテキストへは要約と
     失敗末尾のみ返る

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

## Memory Protocol（Skill 自己メンテナンス — 検証結果の代替ではない）

`~/.claude/skill-memory/swarm-release-gate/MEMORY.md` が存在すれば手順 1 の前に読み、過去に頻出した
`verify.sh` 失敗パターンとその原因（診断を速めるための参考情報）を踏まえてよい。**ただしこの Memory は
検証結果のキャッシュ・代替では絶対にない** — 「過去に通っていたはず」を根拠に `verify.sh` の実行を省略
することは上記「境界条件」「禁止事項」に反する。存在しなければ気にせず進めてよい。

完了時、今回の検証固有の詳細ではなく今後の検証一般に通用する知見（vald/dotfiles で繰り返し観測される
`verify.sh` 失敗カテゴリ等）が得られた場合のみ、`~/.claude/skill-memory/swarm-release-gate/`
（無ければ作成）の `MEMORY.md` に簡潔に追記する。一般化可能な学びが無ければ何も書かずに終える。
