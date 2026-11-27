---
name: vald-law-ttsr
description: Abort mid-stream when Vald coding laws or deprecated API parameters are generated.
globs:
  - "**/*.go"
  - "agent/**"
condition:
  - "\\berrors\\.New\\s*\\("
  - "\"budget_tokens\"\\s*:"
  - "\\bpanic\\s*\\("
  - "\\blog\\.Fatal(?:f|ln)?\\s*\\("
scope: "tool:edit(*.go), tool:write(*.go), tool:edit(*.json), tool:write(*.json)"
interruptMode: "tool-only"
repeatMode: "after-gap"
---

# Vald Law & API Guardrail Reminder

1. **Vald Error Handling Law**: Do NOT use standard library `errors.New` directly inside `vdaas/vald`. Always use constructors defined in `internal/errors`.
2. **Anthropic 5.5 API Guard**: Do NOT use `"budget_tokens"`. Use `thinking: {"type": "adaptive"}` and the `effort` parameter instead.
