---
name: review
description: Run proactive multi-agent adversarial code review on recent changes or a target branch.
---

# Multi-Perspective Code Review

Review recent changes:
{{input}}

## Steps:

1. Inspect git status and diff (`git diff HEAD~1` or uncommitted changes).
2. Invoke `code-reviewer` subagent to audit style, security, invariants, and error handling.
3. If Go code, check goroutine safety, table-driven tests, and Vald Law compliance (if in vald).
4. If Rust code, check ownership, lifetimes, unsafe blocks, and memory safety.
5. Provide actionable, concise feedback sorted by severity (Critical > Warning > Suggestion).
