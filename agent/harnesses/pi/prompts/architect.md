---
name: architect
description: Run SWARM Architect design screening and architectural diagnosis for complex refactors and deadlock resolution.
---

# SWARM Architecture Assessment

Perform architectural diagnosis on:
{{input}}

## Steps:

1. Inspect high-level architectural invariants, data flow, concurrency models, and module boundaries.
2. Formulate alternative design proposals with trade-off analysis.
3. Check against Vald Law (if in vald) or system-level performance requirements.
4. Output structured design proposal without directly modifying code.
