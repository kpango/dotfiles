---
name: golang-testing
description: Go testing patterns including table-driven tests, subtests, benchmarks, fuzzing, and test coverage. Follows TDD methodology with idiomatic Go practices.
origin: ECC
---

# Go Testing Patterns

Comprehensive Go testing patterns for writing reliable, maintainable tests following TDD methodology.

Full code examples for every pattern below live in `reference.md` (same directory) — this file
covers when/why and the core decision criteria; `reference.md` has the copy-pasteable "how".

## When to Activate

- Writing new Go functions or methods
- Adding test coverage to existing code
- Creating benchmarks for performance-critical code
- Implementing fuzz tests for input validation
- Following TDD workflow in Go projects

## TDD Workflow for Go

### The RED-GREEN-REFACTOR Cycle

```
RED     → Write a failing test first
GREEN   → Write minimal code to pass the test
REFACTOR → Improve code while keeping tests green
REPEAT  → Continue with next requirement
```

Full step-by-step example (interface stub → failing test → minimal implementation → refactor):
see `reference.md#tdd-step-by-step-example`.

## Pattern Catalog

Each pattern below has full code in `reference.md`. Use this list to decide which pattern fits,
then jump to the matching section.

- **Table-Driven Tests** (`reference.md#table-driven-tests`) — the standard pattern for Go tests;
  a `[]struct{...}` of cases run through `t.Run`. Use for comprehensive input/output coverage,
  including error-case variants (`wantErr bool`).
- **Subtests and Sub-benchmarks** (`reference.md#subtests-and-sub-benchmarks`) — group related
  tests under one parent (e.g. CRUD operations sharing setup) via `t.Run`; use `t.Parallel()` for
  independent subtests (remember to capture the range variable).
- **Test Helpers** (`reference.md#test-helpers`) — extract setup/assertion logic into functions
  marked with `t.Helper()`; use `t.TempDir()` for auto-cleaned temp files/dirs and `t.Cleanup()`
  for teardown.
- **Golden Files** (`reference.md#golden-files`) — compare output against files in `testdata/`,
  with a `-update` flag to regenerate them.
- **Mocking with Interfaces** (`reference.md#mocking-with-interfaces`) — define a small interface
  for the dependency, mock it with a struct of `Func` fields; prefer this over heavier mocking
  frameworks.
- **Benchmarks** (`reference.md#benchmarks`) — `func BenchmarkX(b *testing.B)`, `b.ResetTimer()`
  after setup, `b.Run` for size/variant sweeps, and allocation-comparison benchmarks.
- **Fuzzing (Go 1.18+)** (`reference.md#fuzzing-go-118`) — `func FuzzX(f *testing.F)` with seed
  corpus via `f.Add`, property assertions inside `f.Fuzz`.
- **HTTP Handler Testing** (`reference.md#http-handler-testing`) — `httptest.NewRequest` /
  `httptest.NewRecorder`, table-driven for multiple routes/methods/status codes.

## Test Coverage

```bash
# Basic coverage
go test -cover ./...

# Generate coverage profile
go test -coverprofile=coverage.out ./...

# View coverage in browser
go tool cover -html=coverage.out

# View coverage by function
go tool cover -func=coverage.out

# Coverage with race detection
go test -race -coverprofile=coverage.out ./...
```

### Coverage Targets

| Code Type               | Target  |
| ----------------------- | ------- |
| Critical business logic | 100%    |
| Public APIs             | 90%+    |
| General code            | 80%+    |
| Generated code          | Exclude |

Excluding generated code from coverage: see `reference.md#excluding-generated-code-from-coverage`.

## Testing Commands

```bash
# Run all tests
go test ./...

# Run tests with verbose output
go test -v ./...

# Run specific test
go test -run TestAdd ./...

# Run tests matching pattern
go test -run "TestUser/Create" ./...

# Run tests with race detector
go test -race ./...

# Run tests with coverage
go test -cover -coverprofile=coverage.out ./...

# Run short tests only
go test -short ./...

# Run tests with timeout
go test -timeout 30s ./...

# Run benchmarks
go test -bench=. -benchmem ./...

# Run fuzzing
go test -fuzz=FuzzParse -fuzztime=30s ./...

# Count test runs (for flaky test detection)
go test -count=10 ./...
```

## Best Practices

**DO:**

- Write tests FIRST (TDD)
- Use table-driven tests for comprehensive coverage
- Test behavior, not implementation
- Use `t.Helper()` in helper functions
- Use `t.Parallel()` for independent tests
- Clean up resources with `t.Cleanup()`
- Use meaningful test names that describe the scenario

**DON'T:**

- Test private functions directly (test through public API)
- Use `time.Sleep()` in tests (use channels or conditions)
- Ignore flaky tests (fix or remove them)
- Mock everything (prefer integration tests when possible)
- Skip error path testing

## Integration with CI/CD

GitHub Actions example (checkout → setup-go → `go test -race -coverprofile` → coverage-threshold
check): see `reference.md#integration-with-cicd`.

**Remember**: Tests are documentation. They show how your code is meant to be used. Write them clearly and keep them up to date.
