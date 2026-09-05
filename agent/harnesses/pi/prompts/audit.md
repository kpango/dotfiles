---
name: audit
description: Run security audit and vulnerability assessment across the codebase.
---

# Security & Vulnerability Audit

Perform security review on:
{{input}}

## Steps:

1. Scan for leaked secrets, credentials, API keys, and sensitive paths.
2. Delegate to `security-audit` subagent for OWASP Top 10 and supply-chain inspection.
3. Check permission policies and sandbox boundaries.
4. If applicable, run `govulncheck ./...` or `cargo audit`.
5. Output structured vulnerability report with exploitability assessment.
