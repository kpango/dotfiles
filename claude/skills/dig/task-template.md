# Evidence-Driven Task Template

Use this template for implementation tasks. Remove optional sections that do not apply. Do not leave `TBD`, `TODO`, or invented file paths.

---

## Task N: <observable outcome>

### Contract trace

- Acceptance criterion: `AC-N`
- Non-goals:
- Dependencies:
- Unlocks:

### Ownership and risk

- Create:
- Modify:
- Read-only context:
- Generated files: `none` or source-of-truth and generator command
- Risk: `low | medium | high`
- Rollback point: `<base SHA or reversible state>`

### Model routing

- Requested model: `haiku | claude-sonnet-5 | opus`
- Effective model: `<resolved model | unknown>`
- Effort: `inherit for haiku | medium/high/xhigh for Sonnet 5 | high/xhigh for Opus`
- Resolution evidence: `<version, env override, allowlist/fallback notice>`
- Reason: `<capability/risk justification, not task size alone>`

### Execution form

- Form: `main session | subagent | agent team`
- Isolation: `none | worktree`
- File owner:
- State writer: `orchestrator only`
- Reason: `<why coordination/context isolation justifies overhead>`

### Graph context

- Available index: `CodeGraph | Graphify | both | none`
- Freshness evidence: `<status/check-update output or unavailable reason>`
- Query budget: `<response token/character cap>`
- Routes used: `<explore/query/path/explain/impact>`
- Direct reads after graph: `<only locations needed to verify decisions>`
- Fallback reason: `<none or unsupported/stale/ambiguous evidence>`

### Observe

State the current behavior and run the cheapest command that proves the gap.

```bash
<reproducer, parser, compile, dry-run, or inspection command>
# Expected before change: <observable failure or mismatch>
```

Baseline evidence:

- Command:
- Exit status:
- Relevant output:
- Existing unrelated failures:

### Hypothesis

- Root-cause hypothesis:
- Evidence supporting it:
- Smallest observation or change that can falsify it:

### Act

Describe the smallest diff that addresses this task. For behavior changes and bug fixes, add or identify the failing test first. For refactors, identify characterization coverage. For docs/config, identify parser, schema, dry-run, or generated-diff validation.

### Verify

Run checks from cheapest and narrowest to broader regression coverage.

```bash
# 1. Static/parser/compile
<command>

# 2. Targeted behavior
<command>

# 3. Affected-module regression
<command>

# 4. Integration/E2E/benchmark only when required by AC-N
<command>
```

Expected evidence:

- Every command has an expected exit status or measurable threshold.
- Coverage follows the repository gate. If no gate exists, success, failure, and boundary behavior touched by the change are directly tested.
- Performance claims include baseline, environment, sample count, and comparison method.

### Review policy

- Review range: `<task_base_sha>..<task_head_sha>`
- Standard: one independent Sonnet 5 review for spec and code quality.
- High risk: separate Opus reviews for spec and quality/security/performance.
- Every finding must include location, failure scenario, severity, and evidence.

### Completion evidence

```json
{
  "task_id": "N",
  "criterion": "AC-N",
  "status": "PASS | PROGRESS | BLOCKED",
  "requested_model": "claude-sonnet-5",
  "effective_model": "claude-sonnet-5",
  "effort": "high",
  "fallback_reason": null,
  "base_sha": "<sha>",
  "head_sha": "<sha-or-working-tree>",
  "files_changed": [],
  "checks": [
    {"command": "<exact command>", "exit_status": 0, "result": "PASS"}
  ],
  "review": {"model": "claude-sonnet-5", "result": "PASS", "findings": []},
  "failure_signature": null,
  "next": "<next criterion, hypothesis, or user decision>"
}
```

For `BLOCKED`, add the missing decision or capability, attempted hypotheses, and the evidence that further retries would repeat a dead end.

### Post-task improvement signal

- Normalized friction: `<none or stable signature>`
- Independent run count: `<n>`
- Deterministic spec mismatch: `<none or evidence>`
- `dig-improve` action: `not eligible | proposal requested | user decision required`

---

## Dependency map

List file ownership and validation resources, not only logical dependencies.

| Task | Depends on | Owned files | Shared resource | Parallel-safe |
| --- | --- | --- | --- | --- |
| 1 | none | `path/a` | none | yes |
| 2 | 1 | `path/b` | test DB | no |

Dispatch only ready tasks whose owned files and validation resources do not conflict.
