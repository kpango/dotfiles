# EXPERIENCE.md — Harness² C3 Experience Library

Canonical store of distilled, structured insights (Harness² component C3, arXiv:2610.14224).
Written by `agent/scripts/evolve/harness2-offline.py` (Stage 5, append only, SHA-256 dedup).
Existing entries are never rewritten; to retire one, add a superseding entry and a human edit.

## Schema

Each entry is a level-3 heading holding its id, followed by `- key: value` lines (single line each):

- id (heading `### <id>`): first 16 hex chars of SHA-256 over `pattern + "\n" + target + "\n" + scope`
  (UTF-8; evidence and created are NOT part of the hash, so re-observing a pattern deduplicates)
- pattern: normalized root-cause signature or invariant statement (lowercase, whitespace collapsed)
- evidence: where it was observed / why it holds (occurrence counts or file references)
- target: repo-relative path of the component the insight applies to (C1-C8 mapping)
- scope: `INV` (task-invariant, recurs across tasks) or `DOM` (domain specific)
- created: ISO date (YYYY-MM-DD)

## Entries

### 7819752e04ac1dee

- pattern: rtk rewrite must only receive whitelisted commands; never pass cat/head/tail/read/grep/ls/echo to rtk, and keep claude and omp whitelist decisions identical
- evidence: RTK whitelist, Issue #582; agent/hooks/omp/rtk-optimizer.ts isWhitelistedForRtk mirrors agent/hooks/claude/rtk-rewrite.sh (raw-string prefix match, case-sensitive); parity enforced by rtk-optimizer.test.ts
- target: agent/hooks/omp/rtk-optimizer.ts
- scope: INV
- created: 2026-11-20

### 6e32d970adbbbc0a

- pattern: action fusion: run the file-type verifier (build/test/lint/syntax check) immediately after each edit, before the next edit; do not stack unverified edits
- evidence: SoL-Pi arXiv:2609.20519 Action Fusion; CLAUDE.md 'Working in This Repo' (Action Fusion bullet); agent/harnesses/omp/sol-pi.json actionFusion flag
- target: CLAUDE.md
- scope: INV
- created: 2026-11-20

### 39698e2dd9974a5c

- pattern: pricing cliff: advisory warning at 85% and a compaction recommendation at 100% of the model cliff (Haiku 5.5 90,000 tokens, GPT-6.2 250,000 tokens, default 180,000); crossing it multiplies input cost
- evidence: Pricing Cliff boundaries, fix-plan.md Work Area 5; agent/models/schema.json compaction_threshold description; advisory text only in context-economy.ts nextStepGuidance (no automatic compaction or failover is triggered)
- target: agent/harnesses/omp/extensions/context-economy.ts
- scope: INV
- created: 2026-11-20

### 89ec83ca05fbbee1

- pattern: net token budget: a change to an always-loaded layer (C1 SYSTEM.md, C2 rules, C4 AGENTS.md/CLAUDE.md, C6 SKILL.md) must satisfy candidate_tokens - baseline_tokens <= 0; SKILL.md <= 500 lines and description <= 160 chars
- evidence: Net Token Budget conservation law (Harness²); tokens = ceil(UTF-8 bytes/4); enforced by harness2-offline.py Stage 3 (test-harness2-offline.sh)
- target: agent/skills/swarm-evolve/SKILL.md
- scope: INV
- created: 2026-11-20
