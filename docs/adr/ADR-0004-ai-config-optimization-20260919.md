# ADR-0004: 2026-09-19 DeepResearch起点のClaude/Pi設定最適化

## Status
Accepted (human-approved via Grilling design interview, 2026-09-20, `ai-config-optimization`
mission, dotfiles repo).

## Context

`/swarm-meta`経由で「2026-09-19時点最新のAI関連情報をDeepResearchし、Claude/Pi設定を最適化せよ」という
ミッションを実施した。Phase 1 EXPLOREで4件の並列調査（Claude Code設定棚卸し・Pi Coding Agent設定棚卸し・
Claude Code最新動向DeepResearch・マルチエージェントオーケストレーション研究DeepResearch）を実施し、
`@fix_plan.md`の`## Secretary Report`にPriority Queue（9項目、MAST分類・確度付き）として整理した。

このミッションは過去4件の内部監査ミッション（skill-effectiveness-audit / claude-orchestration-{audit,
org-scale,determinism}）と`CLAUDE.md,settings.json,hooks,agents-content,skills-content`語彙で重複判定
（OVERLAP、self-improve-check.sh）されたが、外部DeepResearch起点である点で差別化されるため続行した
（`@fix_plan.md`の`## Out of Scope`差別化角度を参照）。impact-C（既存hook/skill文書の変更）に該当するため、
EXECUTE着手前に`grill-interview.md`準拠のGrilling設計面談を実施し、以下4点を決定した。

## Decisions

### 1. EXECUTE範囲（Architecture & Boundaries）

Priority Queue 9項目のうち、実際のコード/設定変更を伴う候補は3件（項目1・4・5）+ 無条件実施の1件
（項目2、事実更新）。人間承認により**実行系・文書系すべて着手**を選択した:

- 項目1（Checker独立性記述の見直し）: 文書のみ、`agent/SWARM.md` §2への追記
- 項目2（issue引用の事実更新）: 文書のみ、`agent/skills/swarm-meta/SKILL.md`、無条件実施（些末な事実修正）
- 項目3（TaskOutput関連）: **見送り**。外部DeepResearchが「2.1.277で削除」と主張したが、本ミッション自身の
  セッションで`TaskOutput`を実際に呼び出し正常動作を確認しており矛盾する。`verify-before-assert.md`の
  「AI要約のみで断定しない」原則により、実際に動いているものを外部レポートのみを根拠に変更しない。
- 項目4（ConfigChangeフック新規追加）: 実行系、`.claude/settings.json`へのhook配線追加
- 項目5（mcp-ecosystem-audit skill更新 + `"type":"sdk"`エントリgrep + `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
  現在値確認）: 文書更新 + 検証。発見があれば同一ミッション内で修正する（決定4参照）

理由: いずれも影響範囲が小さく（項目4のみが新規hook配線という実行系変更）、deterministic検証
（JSON validity / bun build等）で安全に検証できるため、予算(mission_max=20)にも十分余裕がある。

### 2. ConfigChangeフックのアーキテクチャ境界（Architecture & Boundaries）

新規`ConfigChange`hookイベント（Claude Code 2.1.x系で追加、`code.claude.com/docs/en/hooks`で存在確認済み）
を、既存の`.claude/helpers/graft-integrity-check.cjs`（graftテンプレート上書きの検知・自動復旧、現状
`SessionStart`+`Stop`の2段構え）に**三段目として追加配線**する。新規スクリプトは作らず、既存ロジックを
そのまま共用する:

- matcher: `project_settings`のみ（`.claude/settings.json`自体の変更を検知対象とする）。当初`skills`
  matcherも併用する案を検討したが、`graft-integrity-check.cjs`が実際に検知・修復する対象は
  `.claude/helpers/*.cjs`と`.claude/settings.json`の`permissions.allow`のみであり、`skills`配下の
  変更を検知しても呼び出すロジックがそれに対応しないため常にno-opになる（architecture-adversarial-
  reviewer、Phase 4.5で指摘・修正）。実際に効果のあるmatcherのみを配線する。
- 対象は`.claude`プロジェクトスコープのみ（`agent/harnesses/claude/settings.json`という**グローバル**
  設定へは拡張しない）。理由: graft自体がこのリポジトリで`--no-global`（プロジェクトローカル限定）で
  初期化されている設計（CLAUDE.mdの「Graft — repo context graph」節）と整合させるため。

### 3. 自己書き換えによるフックループへの対処（Behavior & Edge Cases）

`graft-integrity-check.cjs`は修復時に`.claude/settings.json`の`permissions.allow`を書き換える。この
自己書き換えが`project_settings`にマッチする新規`ConfigChange`フックを再度発火させうるが、**新規の
デバウンス機構は追加しない**。既存スクリプトが持つ冪等性（修復済みなら2回目の呼び出しは異常なしとして
即座にno-opで終了する設計）に委ねる。最悪ケースでも1セッションあたり「検知→修復→再検知(no-op)」の
3回呼び出しで収束し、無限ループにはならない。EXECUTE時にこの冪等性を実コードRead で確認してから
配線する。

### 4. 検証作業での発見への対処（Implementation & Tests）

項目5の検証作業（`agent/harnesses/*/mcp_config.json`等への`"type":"sdk"`エントリのgrep、
`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`現在値の確認）で実際の問題が見つかった場合、**別ミッションへ先送りせず
本ミッション内でそのまま修正する**。理由: いずれも事実確認・影響範囲が小さく、deterministic検証
（JSON validity）で安全性を確認できるため。

## Consequences

- `agent/SWARM.md` §2にCheckerの cross-family 独立性についての最新知見（arXiv:2605.29800等、単一
  プレプリント・確度中）を追記する。既存の「intra-family < cross-family」という記述は維持しつつ、
  「cross-familyというだけでは十分な独立性は保証されない」という新しい nuance を追加する
  （既存記述の矛盾修正ではなく追記）。
- `agent/skills/swarm-meta/SKILL.md`のissue引用（#26251/#43875）に、同型バグが`#95469`等で2026-09-18
  時点も継続している旨を追記する。
- `.claude/settings.json`に`ConfigChange`hookエントリを追加する（matcher: `project_settings`のみ）。
- `agent/skills/mcp-ecosystem-audit/SKILL.md`にMCP v2 client/negotiationが2.1.274で全install typeの
  既定になった旨を反映する。
- `agent/harnesses/*/mcp_config.json`等の`"type":"sdk"`エントリ有無、`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
  現在値を検証し、問題があれば修正する。
- `TaskOutput`関連には一切触れない。
- 詳細な調査結果全文は`.claude/worktrees/mission-ai-config-optimization-20260919-125131/@fix_plan.md`の
  `## Secretary Report`に記録されている（worktree回収後は軌跡ログへ転記）。
