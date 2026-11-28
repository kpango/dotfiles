---
title: OMP の起動時 warn は拡張コマンド衝突と未使用プロバイダ probe
author: Kpango
date: 2026-11-22
branch: main
id: l-661122c7
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/omp/config.yml
  - agent/skills/swarm-meta/harness-registry.tsv
  - agent/skills/trail/SKILL.md
---

## Decided

- OMP は拡張 slash command が組み込みと同名だと "conflicts with built-in commands. Skipping." をログに出して**登録ごと捨てる**。拡張のコマンドは組み込み名を避け、機能名+接頭辞/接尾辞を付ける (`/plan-mode`, `/memory-edit`, `/handoff-export`, `/interval-loop`, `/until-loop`, `/cp-rewind`, `/agent-list`, `/tool-toggle`)。
- 未使用の組み込みローカルプロバイダ (`lm-studio`, `llama.cpp`, `vllm`) は毎起動 discovery probe して ECONNREFUSED を warn にするので、`config.yml` の `disabledProviders` に列挙して止める。OMP 自身の YAML rewrite は未知のトップレベルキーを保持するので runtime 正規化と共存できる。

## Tried and ruled out

- 競合コマンドを「削除」して解消する案: 拡張側の read-only ガードや todo 追跡など組み込みに無い機能を失うため却下。リネームで維持。
- 起動時 warn を TUI 側で隠す案: `getCommandDiagnostics()` の消費者が cli.js に存在せず、警告はログにしか出ない。ログを正とする。

## Watch out

- `/plan` の拡張フラグは組み込み `--plan=<model>` と衝突して `getFlag("plan")` が常に undefined だった。フラグ名も `plan-mode` に揃える。`--help` には拡張フラグが出ないので、動作確認は `--plan-mode` 付きの print 実行 (write がブロックされるか) で行う。
- `ui.loop-blocked` の主犯は `refreshVerifiedModels` の同期 `execFileSync` (session_start ごと)。6h キャッシュで消える。journal 側は JSONL 全件再パースをやめ、追記分のみ読む増分インデックスにする (書き換え検出のため追記行の parse 失敗で全再読込)。
