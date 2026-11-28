---
name: swarm
description: SWARM 唯一の人間招集入口。--auto/--loop/--graph/--architect/--evolve/--gate/--memory/--relay/--every/--until/--stop で各プロトコルへ振り分ける。
allowed-tools: [Read, Write, Edit, Bash, Grep, Glob, Agent, Skill]
user-invocable: true
disable-model-invocation: true
---

# swarm — SWARM 統合入口

開始前に `~/.claude/skills/_swarm-common/load.sh core --once` を実行し、`SWARM.md` §0 の
Tier A/B・予算・GATE 規約に従う（本 skill は再掲しない）。本 skill は **入口と振り分けだけ** を持ち、
フェーズ手順・判定表・予算上限は委譲先 SKILL が唯一の正典。

## 1. モード（先頭の 1 トークンだけを解釈する）

| 指定            | 委譲先（Read して追従）                                        | 開始点                                                                 |
| --------------- | -------------------------------------------------------------- | ---------------------------------------------------------------------- |
| なし / `--auto` | `skills/swarm-meta/SKILL.md`（各ハーネスの skills ルート配下） | M0 PROFILE 抽出から（M2 で loop/graph を選択）                         |
| `--loop`        | `skills/swarm-loop/SKILL.md`                                   | Phase -1 SCALE 判定から                                                |
| `--graph`       | `skills/swarm-graph/SKILL.md`                                  | Phase G-1（相0 Quick 判定→相1 分解→相2 FIT）。UNFIT は `--loop` へ降格 |
| `--architect`   | `skills/swarm-architect/SKILL.md`                              | スポット条件判定。フル設計モードは人間招集のみ                         |
| `--evolve`      | `skills/swarm-evolve/SKILL.md`                                 | 差分検出→提案→人間承認                                                 |
| `--gate`        | `skills/swarm-release-gate/SKILL.md`                           | `verify.sh` 全パス確認から                                             |
| `--memory`      | `skills/swarm-memory-sync/SKILL.md`                            | GATE/PLAN 時の同期                                                     |
| `--relay`       | `skills/swarm-relay/SKILL.md`                                  | Phase 0/G0 の並行ミッション調整                                        |

- モード不明・曖昧・引数なしの goal は `--auto` として扱う。
- `--mode` に該当しない残り **全部** を goal として委譲先へ渡す（goal を切り詰めない）。
- 委譲先の Phase を飛ばさない・GATE を省略しない。難局は ESCALATE（人間）で止める。
- `swarm-explore` / `swarm-secretary` / `swarm-implement` は入口ではない（ハーネス内部からのみ Read される）。

## 2. ループ系プリミティブ（skill ではなく実行機構）

SWARM のミッション状態機械（`--loop`/`--graph`）とは別に、完了条件を持たない単発反復がある。
これらはハーネスの実行機構であり、入口は `/swarm` に寄せる。

| 指定                         | Pi の実体                                                                                           | claude / agy                                       |
| ---------------------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `--every <interval> <task>`  | `swarm-orchestrator.ts` の interval タイマー（`10s`/`5m`/`1h` 形式、`--stop` まで反復）             | 反復が必要なら `--loop` の CHECKPOINT 反復へ寄せる |
| `--until <condition> <task>` | `goal_loop` ツール（`exit:N`/`contains:`/`regex:`/`eval:`/`judge:`、上限 10 回・連続 5 失敗で停止） | 同上                                               |
| `--stop [all]`               | 実行中の interval タイマーと goal loop を停止                                                       | 同上                                               |

- Pi では `/swarm --every` と `/swarm --until` を正規の招集入口として一本化する
  （低水準の `/interval-loop` `/until-loop` 互換コマンドも `swarm-orchestrator` が登録する）。
- 通常は `/swarm --every/--until` を使う。

## 3. 実行規約

- **状態**: Mission ではミッション worktree の `@fix_plan.md` が唯一の永続状態。書き込みは
  オーケストレーターのみ（single-writer）。Quick は状態ファイルを作らない。
- **Tier A/B**: 保護対象の編集には既存の書込手順を使う。ユーザーが依頼した作業内の低リスクな保守に限り、
  `agent/AGENTS.md` の常設承認を適用できる。実行中の自己改変、安全ゲートや権限の変更は対象外。
  `/swarm --evolve` の適用とリリースの承認は従来どおり。
- **予算**: タスク上限・ミッション上限・Fable スポット上限は `fable-budget.conf` と
  `SWARM.md` §3 が正典。本 skill は独自の上限を持たない。
- **後方互換**: 旧 `/swarm-loop` `/swarm-graph` `/swarm-meta` は Pi の slash 一覧から削除済み（prompt
  テンプレート廃止）。Claude/AGY では skill の直接招集も互換として残るが、案内・ドキュメントの入口は
  `/swarm --mode` のみとし、新規の手順書・トリガーに旧名を書かない。
- **進捗確認**: Pi は `/swarm status`、任意のハーネスは
  `skills/swarm-loop/scripts/loop-status.sh`、graph は `graph-status.sh`。
