---
title: SWARM の人間入口を /swarm 1 本に統合 (OMP)
author: Kpango
date: 2026-11-22
branch: main
id: l-af71d56f
scope: repo
status: active
src: agent
touches:
  - agent/harnesses/omp/config.yml
  - agent/skills/swarm-meta/harness-registry.tsv
  - agent/skills/trail/SKILL.md
  - agent/skills/swarm/SKILL.md
---

## Decided

- 人間の招集入口は `agent/skills/swarm/SKILL.md` の `/swarm` 1 本。`--auto`(swarm-meta) / `--loop` / `--graph` /
  `--architect` / `--evolve` / `--gate` / `--memory` / `--relay` に委譲し、`--every` / `--until` / `--stop` は
  swarm-orchestrator から loop-controller の export 済み handler へ流す（タイマー実装は 1 つだけ）。
- OMP の prompt テンプレート `/swarm-loop` `/swarm-graph` `/swarm-meta` は削除（`agent/harnesses/omp/prompts/`）。
  OMP では skill が slash command にならないため prompt が唯一の入口だったが、`/swarm` に一本化して不要化。
  Claude/AGY では skill が `/swarm` として直接招集でき、protocol skill 側の `/swarm-loop` 等も残る。

## Watch out

- OMP の builtin `/loop` `/goal` `/plan` `/tools` `/rewind` `/memory` `/handoff` `/subagents` はランタイム予約名で
  拡張から奪えない。競合した extension コマンドはログの "conflicts with built-in" に出るので、SWARM の入口は
  builtin と衝突しない `/swarm` に置く（`/loop` `/goal` を入口として案内しない）。
- `/swarm --every` は iteration 上限を持たない（`--stop` まで）。`--until` は goal loop で上限 10・連続 5 失敗で停止。
- `disable-model-invocation: true` の skill（swarm / swarm-loop / swarm-graph / swarm-meta）はモデル一覧に出ないが、
  明示 Read すれば使える。dispatch 文は `~/.omp/agent/skills/<name>/SKILL.md` を Read させる。
