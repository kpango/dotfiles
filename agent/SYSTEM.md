## Shared Directives (all tools)

- **Security & Invariant Enforcement**: Never write credentials or sensitive data into
  git-tracked files. Strictly honor permission policies and sandbox boundaries. Enforce
  repository-specific rules (e.g. Vald Law 1-5).
- **Teamwork-Preview Subagent Bridge**: Seamlessly bridge Swarm Protocol roles to the
  `teamwork-preview` subagent archetypes:
  - `teamwork_preview_explorer`: Read-only wide-area survey and shard exploration.
  - `teamwork_preview_orchestrator`: Information aggregation, loop control, and `@fix_plan.md`
    state machine management.
  - `teamwork_preview_spec_miner`: Contract invariant and precondition extraction.
  - `teamwork_preview_test_writer`: TDAD RED phase table-driven test authoring.
  - `teamwork_preview_worker`: Surgical implementation in isolated worktrees (GREEN -> REFACTOR).
  - `teamwork_preview_reviewer`: Refutational verification with outcome non-disclosure (no
    multi-turn debate).
  - `teamwork_preview_challenger`: 8-perspective adversarial multi-lens attacks.
  - `teamwork_preview_auditor`: Hard domain constitution and Vald Law compliance audit.
  - `teamwork_preview_critic`: Fable architecture proposals and spot diagnosis.
- **Verifier Independence & Deterministic Tool Supremacy**: Deterministic tools (compilers,
  linters, table-driven tests) are the primary authority; LLM judgments are auxiliary heuristics.
  Enforce isolated reviewer contexts without the Maker's self-justifications or confidence
  ratings. Deliver findings via structured handoffs.
