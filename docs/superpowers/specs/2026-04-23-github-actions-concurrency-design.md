# Spec: GitHub Actions Concurrency for Docker Builds

## Problem Statement
The current GitHub Actions workflow (`docker-matrix.yml`) does not cancel previous runs when new commits are pushed to the same branch or pull request. This leads to redundant builds and resource wastage.

## Goal
Improve the "Cancel" functionality so that old jobs are automatically canceled whenever a new commit is made to the same branch or PR, including the `main` branch.

## Proposed Design

### GitHub Actions Configuration
Add a `concurrency` block at the top level of `.github/workflows/docker-matrix.yml`.

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

- `group`: Combines the workflow name and the reference (branch, tag, or PR branch) to ensure runs are only canceled within the same context.
- `cancel-in-progress: true`: Specifically instructs GitHub to terminate any existing runs in the same group when a new one is triggered.

## Success Criteria
- The YAML file is syntactically correct.
- The `concurrency` group is applied globally to the workflow.
- All branches (including `main`) and PRs are covered by this cancellation logic.

## Implementation Plan
1. Edit `.github/workflows/docker-matrix.yml`.
2. Add the `concurrency` block after the `on` block.
3. Validate the YAML structure.
