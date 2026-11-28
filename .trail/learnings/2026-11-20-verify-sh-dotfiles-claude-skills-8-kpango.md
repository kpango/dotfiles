---
title: verify.sh の dotfiles 分岐が廃止済み claude/skills を指し 8 テストが常時スキップだった
author: Kpango
date: 2026-11-20
branch: main
id: l-79ec16a4
scope: repo
status: active
src: agent
touches:
  - agent/AGENTS.md
  - agent/harnesses/agy/AGENTS.md
  - agent/harnesses/omp/AGENTS.md
  - agent/scripts/test-harness2-offline.sh
  - agent/skills/swarm-release-gate/SKILL.md
  - agent/skills/swarm-release-gate/scripts/verify.sh
---

## Decided

- 2026-11-21: swarm-release-gate の verify.sh dotfiles 分岐に `trail check`（Trail 未導入なら明示 SKIP）と
  `agent/scripts/test-harness2-offline.sh` を追加した。同時にテストパスを `$root/claude/skills/...` から
  正典の `$root/agent/skills/...` へ修正した。SSoT 集約 (2026-09-03) 以降 `claude/skills` は存在せず、
  `[ -f "$t" ] || continue` のため swarm 回帰テスト 8 本が無言でスキップされていた。

## Watch out

- ゲートにテストを足すとき、`[ -f ] || continue` のスキップを PASS と誤認しない。存在しないパスでも
  ALL CHECKS PASSED になる。
- `trail check` は origin の default branch との diff を基準に .trail/learnings との衝突だけを見る
  （graph 鮮度は見ない）。鮮度は `trail build --check` だが fresh clone には .trail/cache が無いため、
  ゲートへ入れるなら cache 存在ガードが必要。
- harness2 のテストは sandbox 不可環境で rc=2 を返すのが仕様で、テスト内で fail-closed 経路を検証して PASS する。
