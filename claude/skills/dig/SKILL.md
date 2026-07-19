---
name: dig
description: >-
  非推奨・後方互換用リダイレクト。旧 dig（コードベース深掘り分析→設計インタビュー→実装計画→自律実行）は
  swarm-loop に完全統合された。/dig と入力された場合は本ファイルの指示に従い、そのまま swarm-loop skill を
  同じ目標・同じ引数で起動すること。dig 独自のロジックはここには存在しない。
trigger: /dig
allowed-tools: [Skill]
user-invocable: true
disable-model-invocation: false
---

# dig（廃止 — swarm-loop へ統合済み）

`dig` の Quick/Research/Full モード判定・対話的設計インタビュー・TDAD Iron Law・複雑度ガード・
Circuit Breaker は、すべて `swarm-loop` skill に統合されている（詳細は `claude/SWARM.md` §0、
`swarm-loop/SKILL.md`、`swarm-implement/SKILL.md` を参照）。

**このメッセージが `/dig <目標>` または `/dig` として呼ばれた場合、以下をそのまま実行する:**

```
Skill(swarm-loop, args=<受け取った目標。未指定なら空文字>)
```

ユーザーへの追加確認は不要。`swarm-loop` の Phase -1（SCALE 判定）が旧 dig の Quick/Interactive/Mission
判定を引き継いで自動的に規模を決める。
