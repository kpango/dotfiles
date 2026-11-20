---
title: "Dependabot PRs build docker images without pushing, because they get no registry secrets"
author: Kpango
date: 2026-11-20
branch: main
cost: { minutes: 9, tokens: 80755 }
id: l-4fb55b28
scope: repo
status: active
src: agent
touches:
  - ".github/workflows/docker-reusable.yaml"
  - Makefile.d/install.mk
  - agent/skills/trail/SKILL.md
  - agent/scripts/test-catalog-health.sh
  - agent/scripts/test-harness2-offline.sh
  - AGENTS.md
  - agent/scripts/test-rlm-bounded.sh
  - ".github/workflows/agent-sync-verify.yaml"
---

## Decided

Dependabot-triggered docker builds run build-only and skip the manifest merge. Dependabot runs get no repository secrets, so the registry login fails with "Password required" and every Dependabot PR went red.
Tests that need raw non-UTF-8 bytes in argv pass them through python subprocess (run_raw), not through the coreutils `timeout` wrapper. The ubuntu-latest runner is now ubuntu-26.04, whose default coreutils is uutils, not GNU.

## Tried and ruled out

Fixing it by adding secrets to the Dependabot secret store: not needed, since a PR build has no reason to push images.

- Reproducing locally: the invalid-UTF-8 test passed here under C, POSIX, C.UTF-8 and an empty LANG, so the failure is not a locale effect. The local `timeout` is GNU 9.11.
- Running uutils `timeout` locally via nix: the nix daemon denied access, so the uutils cause is a hypothesis, not confirmed. Confirm it from the CI result of the fix.

## Watch out

- A skill description over 160 characters fails the catalog tests (the repo-wide limit). trail init regenerates a long description, so re-check the length after re-running it.
- agent/skills/*/SKILL.md is write-protected. After the user approves, issue a single-use grant with budget-guard.sh --write-scope-grant <file> and then Edit it. Do not use sed.

In the code:

- .github/workflows/docker-reusable.yaml (docker_push and the merge job's if both test github.actor)
- agent/scripts/test-catalog-health.sh, agent/scripts/test-harness2-offline.sh
- A job that stops at its first failing step hides every later step. After fixing the first failure, expect a new, unrelated red from a step that never ran.
- The failure showed only "query error message missing" with no traceback, so the test's error text came from the wrapper, not from the script under test.

- agent/scripts/test-rlm-bounded.sh (run_raw, used by the invalid UTF-8 query and non-UTF-8 --model cases)
- .github/workflows/agent-sync-verify.yaml (comment above the fix-plan job)
