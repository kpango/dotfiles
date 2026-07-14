---
name: rust-testing
description: Rust testing patterns including unit tests, integration tests, async testing, property-based testing, mocking, and coverage. Follows TDD methodology.
origin: ECC
---

# Rust Testing Patterns

Comprehensive Rust testing patterns for writing reliable, maintainable tests following TDD methodology.

Full code examples for every pattern below live in `reference.md` (same directory) — this file
covers when/why and the core decision criteria; `reference.md` has the copy-pasteable "how".

## When to Use

- Writing new Rust functions, methods, or traits
- Adding test coverage to existing code
- Creating benchmarks for performance-critical code
- Implementing property-based tests for input validation
- Following TDD workflow in Rust projects

## How It Works

1. **Identify target code** — Find the function, trait, or module to test
2. **Write a test** — Use `#[test]` in a `#[cfg(test)]` module, rstest for parameterized tests, or proptest for property-based tests
3. **Mock dependencies** — Use mockall to isolate the unit under test
4. **Run tests (RED)** — Verify the test fails with the expected error
5. **Implement (GREEN)** — Write minimal code to pass
6. **Refactor** — Improve while keeping tests green
7. **Check coverage** — Use cargo-llvm-cov, target 80%+

## TDD Workflow for Rust

### The RED-GREEN-REFACTOR Cycle

```
RED     → Write a failing test first
GREEN   → Write minimal code to pass the test
REFACTOR → Improve code while keeping tests green
REPEAT  → Continue with next requirement
```

Full step-by-step example (`todo!()` placeholder → failing test → minimal implementation): see
`reference.md#step-by-step-tdd-in-rust`.

## Pattern Catalog

Each pattern below has full code in `reference.md`. Use this list to decide which pattern fits,
then jump to the matching section.

- **Module-Level Test Organization** (`reference.md#module-level-test-organization`) — put unit
  tests in a `#[cfg(test)] mod tests` block alongside the code they exercise; use `super::*`.
- **Assertion Macros** (`reference.md#assertion-macros`) — `assert_eq!`/`assert_ne!`/`assert!`
  with custom messages, plus epsilon comparison for floats.
- **Testing `Result` Returns** (`reference.md#testing-result-returns`) — assert on
  `matches!(err, Variant(_))` for the error path, and write tests returning
  `Result<(), Box<dyn Error>>` with `?` for the success path.
- **Testing Panics** (`reference.md#testing-panics`) — `#[should_panic]` (optionally with
  `expected = "..."`); prefer `Result::is_err()` assertions when the code returns a `Result`.
- **Integration Tests** (`reference.md#file-structure`, `reference.md#writing-integration-tests`)
  — one file per test binary under `tests/`, with shared helpers in `tests/common/mod.rs`.
- **Async Tests with Tokio** (`reference.md#with-tokio`) — `#[tokio::test]`; use
  `tokio::time::timeout` to assert on timeout behavior instead of relying on real delays.
- **Parameterized Tests with `rstest`** (`reference.md#parameterized-tests-with-rstest`) —
  `#[case(...)]` for table-driven inputs, `#[fixture]` for shared setup.
- **Test Helpers** (`reference.md#test-helpers`) — factory functions (e.g. `make_user`) inside the
  `tests` module to remove setup duplication.
- **Property-Based Testing with `proptest`** (`reference.md#basic-property-tests`,
  `reference.md#custom-strategies`) — `proptest! { #[test] fn(...) }` for roundtrip/invariant
  checks over generated inputs; custom `Strategy` impls for domain-shaped data (e.g. emails).
- **Mocking with `mockall`** (`reference.md#trait-based-mocking`) — `#[automock]` on a small
  trait, then `MockX::new()` with `.expect_*().with(...).returning(...)` in the test.
- **Doc Tests** (`reference.md#executable-documentation`) — executable examples in `///` doc
  comments; use `no_run` for examples that shouldn't actually execute in CI.
- **Benchmarking with Criterion** (`reference.md#benchmarking-with-criterion`) — `[[bench]]` in
  `Cargo.toml` with `harness = false`, `criterion_group!`/`criterion_main!`, `black_box` to
  prevent constant-folding.

## Test Coverage

### Running Coverage

```bash
# Install: cargo install cargo-llvm-cov (or use taiki-e/install-action in CI)
cargo llvm-cov                    # Summary
cargo llvm-cov --html             # HTML report
cargo llvm-cov --lcov > lcov.info # LCOV format for CI
cargo llvm-cov --fail-under-lines 80  # Fail if below threshold
```

### Coverage Targets

| Code Type                | Target  |
| ------------------------ | ------- |
| Critical business logic  | 100%    |
| Public API               | 90%+    |
| General code             | 80%+    |
| Generated / FFI bindings | Exclude |

## Testing Commands

```bash
cargo test                        # Run all tests
cargo test -- --nocapture         # Show println output
cargo test test_name              # Run tests matching pattern
cargo test --lib                  # Unit tests only
cargo test --test api_test        # Integration tests only
cargo test --doc                  # Doc tests only
cargo test --no-fail-fast         # Don't stop on first failure
cargo test -- --ignored           # Run ignored tests
```

## Best Practices

**DO:**

- Write tests FIRST (TDD)
- Use `#[cfg(test)]` modules for unit tests
- Test behavior, not implementation
- Use descriptive test names that explain the scenario
- Prefer `assert_eq!` over `assert!` for better error messages
- Use `?` in tests that return `Result` for cleaner error output
- Keep tests independent — no shared mutable state

**DON'T:**

- Use `#[should_panic]` when you can test `Result::is_err()` instead
- Mock everything — prefer integration tests when feasible
- Ignore flaky tests — fix or quarantine them
- Use `sleep()` in tests — use channels, barriers, or `tokio::time::pause()`
- Skip error path testing

## CI Integration

GitHub Actions example (checkout → stable toolchain with clippy+rustfmt → `cargo fmt --check` →
`cargo clippy -- -D warnings` → `cargo test` → cargo-llvm-cov coverage threshold): see
`reference.md#ci-integration`.

**Remember**: Tests are documentation. They show how your code is meant to be used. Write them clearly and keep them up to date.
