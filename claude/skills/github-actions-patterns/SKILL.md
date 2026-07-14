---
name: github-actions-patterns
description: GitHub Actions workflow design, matrix builds, secrets management, caching, and CI/CD patterns for Go/Rust/Protobuf projects with make-based build systems.
trigger: /github-actions-patterns
---

# GitHub Actions Patterns

## Core Principles

- Use `make` targets — never call `go build`, `cargo build`, or `kubectl apply` directly in workflows
- Pin action versions with full SHA for supply-chain security
- Fail fast on linting; run expensive tests only after lint passes
- Cache aggressively: Go modules, Rust target, Docker layers

## Workflow File Layout

```yaml
# .github/workflows/ci.yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true # cancel stale PR runs

permissions:
  contents: read # principle of least privilege

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
      - run: make lint

  test:
    needs: lint # only run after lint passes
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
      - run: make test
```

## Matrix Builds

```yaml
jobs:
  test:
    strategy:
      fail-fast: false # don't cancel other matrix jobs on failure
      matrix:
        os: [ubuntu-latest, macos-latest]
        go: ["1.22", "1.23"]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-go@v5
        with:
          go-version: ${{ matrix.go }}
      - run: make test

  # Include/exclude combinations
  strategy:
    matrix:
      include:
        - os: ubuntu-latest
          go: "1.23"
          race: true
      exclude:
        - os: macos-latest
          go: "1.22"
```

## Caching

```yaml
# Go module cache (actions/setup-go@v5 handles automatically with cache: true)
- uses: actions/setup-go@v5
  with:
    go-version-file: go.mod
    cache: true
    cache-dependency-path: go.sum

# Rust target cache
- uses: actions/cache@v4
  with:
    path: |
      ~/.cargo/registry
      ~/.cargo/git
      target/
    key: ${{ runner.os }}-cargo-${{ hashFiles('**/Cargo.lock') }}
    restore-keys: ${{ runner.os }}-cargo-

# Docker layer cache (for buildx)
- uses: actions/cache@v4
  with:
    path: /tmp/.buildx-cache
    key: ${{ runner.os }}-buildx-${{ github.sha }}
    restore-keys: ${{ runner.os }}-buildx-
```

## Secrets and Variables

```yaml
env:
  REGISTRY: ghcr.io
  IMAGE: ${{ github.repository }}

steps:
  - name: Login to GHCR
    uses: docker/login-action@v3
    with:
      registry: ghcr.io
      username: ${{ github.actor }}
      password: ${{ secrets.GITHUB_TOKEN }} # auto-provisioned, no setup needed

  - name: Custom secret
    env:
      API_KEY: ${{ secrets.MY_API_KEY }} # never put secrets in run: directly
    run: make deploy API_KEY="$API_KEY"
```

## Go/Rust/Proto CI (vald-style)

```yaml
jobs:
  proto:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: bufbuild/buf-setup-action@v1
        with:
          version: latest
      - run: buf lint
      - run: buf breaking --against '.git#branch=main'

  go:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version-file: go.mod
          cache: true
      - run: make format
      - run: git diff --exit-code # fail if format changed files
      - run: make lint
      - run: make test # includes -race flag

  rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
      - uses: actions/cache@v4
        with:
          path: |
            ~/.cargo/registry
            target/
          key: ${{ runner.os }}-cargo-${{ hashFiles('Cargo.lock') }}
      - run: make test/rust
```

## Container Build and Push

```yaml
jobs:
  docker:
    needs: [go, rust]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Docker meta
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,prefix=git-
            type=semver,pattern={{version}}
            type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

      - uses: docker/build-push-action@v5
        with:
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          cache-from: type=local,src=/tmp/.buildx-cache
          cache-to: type=local,dest=/tmp/.buildx-cache-new,mode=max

      - run: |
          rm -rf /tmp/.buildx-cache
          mv /tmp/.buildx-cache-new /tmp/.buildx-cache
```

## Reusable Workflows

```yaml
# .github/workflows/reusable-test.yaml
on:
  workflow_call:
    inputs:
      go-version:
        type: string
        default: "1.23"
    secrets:
      token:
        required: true

# Caller:
jobs:
  call-test:
    uses: ./.github/workflows/reusable-test.yaml
    with:
      go-version: "1.23"
    secrets:
      token: ${{ secrets.GITHUB_TOKEN }}
```

## Permissions Hardening

```yaml
# Top-level default: read-only
permissions:
  contents: read

jobs:
  deploy:
    permissions:
      contents: read
      packages: write # GHCR push
      id-token: write # OIDC for cloud auth (no long-lived secrets)
```

## Anti-Patterns

- Don't `run: go build` / `cargo build` / `kubectl apply` — use `make` targets
- Don't use `actions/checkout@main` — pin to a version tag or SHA
- Don't echo secrets in `run:` steps — use `env:` block
- Don't use `continue-on-error: true` on security-sensitive steps
- Don't skip `concurrency` on PR workflows — stale runs waste runner minutes
