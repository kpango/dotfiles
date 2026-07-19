---
name: golang-patterns
description: Idiomatic Go patterns, best practices, and conventions for building robust, efficient, and maintainable Go applications.
origin: ECC
---

# Go Development Patterns

Idiomatic Go patterns and best practices for building robust, efficient, and maintainable applications.

Detailed code examples for every section below live in [reference.md](reference.md) — this file holds the rules, decision criteria, and quick-reference tables; reference.md holds the full "how" (code samples, anti-pattern walkthroughs, tooling config).

## When to Activate

- Writing new Go code
- Reviewing Go code
- Refactoring existing Go code
- Designing Go packages/modules

## Core Principles

1. **Simplicity and Clarity** — Go favors simplicity over cleverness; code should be obvious and easy to read.
2. **Make the Zero Value Useful** — design types so their zero value is immediately usable without initialization (e.g. `bytes.Buffer`, a `sync.Mutex`-guarded counter).
3. **Accept Interfaces, Return Structs** — functions should accept interface parameters and return concrete types, not hide implementation behind a returned interface.

See reference.md → "Core Principles" for the Good/Bad code pairs.

## Design Principles (Go-SOLID)

| SOLID                       | Go 解釈              | ルール                                                              |
| --------------------------- | -------------------- | ------------------------------------------------------------------- |
| **S** Single Responsibility | パッケージ凝集度     | 1 package = 1 責務                                                  |
| **O** Open/Closed           | インターフェース拡張 | 既存型を変更せず interface + composition で拡張                     |
| **L** Liskov Substitution   | インターフェース契約 | 実装は interface の暗黙契約（戻り値の意味・エラー条件）を完全に守る |
| **I** Interface Segregation | 最小インターフェース | → 「Interface Design」セクション参照                                |
| **D** Dependency Inversion  | 依存性逆転           | → 「Define Interfaces Where They're Used」参照                      |

See reference.md → "Design Principles (Go-SOLID)" for SRP/OCP/LSP code examples (net/http-style package split, Middleware chaining, io.Writer contract integrity).

## Error Handling Patterns

- **Error Wrapping with Context** — wrap errors with `fmt.Errorf("...: %w", err)` so callers get a diagnosable chain.
- **Custom Error Types** — domain-specific error structs (e.g. `ValidationError`) plus sentinel errors (`ErrNotFound`, ...) for common cases.
- **Error Checking** — use `errors.Is` for sentinel comparison and `errors.As` for type extraction; never branch on `err.Error()` string content.
- **Never Ignore Errors** — always handle or explicitly document with a comment why a blank-identifier discard is safe.

See reference.md → "Error Handling Patterns" for full code.

## Concurrency Patterns

- **Worker Pool** — fixed number of goroutines draining a shared `jobs` channel, `sync.WaitGroup` for completion.
- **Context for Cancellation and Timeouts** — thread `context.Context` through I/O calls, always `defer cancel()`.
- **Graceful Shutdown** — trap `SIGINT`/`SIGTERM`, call `server.Shutdown(ctx)` with a bounded timeout.
- **errgroup for Coordinated Goroutines** — use `golang.org/x/sync/errgroup` to fan out and collect the first error.
- **Avoiding Goroutine Leaks** — buffer result channels or `select` on `ctx.Done()` so a goroutine can always exit when nobody is listening.

See reference.md → "Concurrency Patterns" for full code, including the leaky-vs-safe fetch comparison.

## Interface Design

- **Small, Focused Interfaces** — single-method interfaces (`Reader`, `Writer`, `Closer`) composed into larger ones as needed.
- **Define Interfaces Where They're Used** — declare the interface in the consumer package, not next to the concrete implementation (Dependency Inversion).
- **Optional Behavior with Type Assertions** — probe for an optional capability (e.g. `Flusher`) via a type assertion instead of forcing every implementation to support it.

See reference.md → "Interface Design" for full code.

## Package Organization

- **Standard Project Layout** — `cmd/` for entry points, `internal/` for private application code, `pkg/` for a public client, `api/` for schema definitions.
- **Package Naming** — short, lowercase, no underscores, no redundant suffixes like `Service`.
- **Avoid Package-Level State** — prefer constructor-based dependency injection over `init()`-populated globals.

See reference.md → "Package Organization" for the full directory tree and naming examples.

## Struct Design

- **Functional Options Pattern** — variadic `Option` functions to configure a struct's optional fields while keeping required fields in the constructor signature.
- **Embedding for Composition** — embed a type to promote its methods, rather than reimplementing them.

See reference.md → "Struct Design" for full code.

## Memory and Performance

- **Preallocate Slices When Size is Known** — `make([]T, 0, len(items))` instead of letting `append` grow the slice repeatedly.
- **Use sync.Pool for Frequent Allocations** — reuse short-lived buffers instead of allocating per request.
- **Avoid String Concatenation in Loops** — use `strings.Builder`, or `strings.Join` when the whole slice is available upfront.

See reference.md → "Memory and Performance" for full code.

## Go Tooling Integration

```bash
# Build and run
go build ./...
go run ./cmd/myapp

# Testing
go test ./...
go test -race ./...
go test -cover ./...

# Static analysis
go vet ./...
staticcheck ./...
golangci-lint run

# Module management
go mod tidy
go mod verify

# Formatting
gofmt -w .
goimports -w .
```

See reference.md → "Go Tooling Integration" for the recommended `.golangci.yml` linter configuration.

## Quick Reference: Go Idioms

| Idiom                                               | Description                                              |
| --------------------------------------------------- | -------------------------------------------------------- |
| Accept interfaces, return structs                   | Functions accept interface params, return concrete types |
| Errors are values                                   | Treat errors as first-class values, not exceptions       |
| Don't communicate by sharing memory                 | Use channels for coordination between goroutines         |
| Make the zero value useful                          | Types should work without explicit initialization        |
| A little copying is better than a little dependency | Avoid unnecessary external dependencies                  |
| Clear is better than clever                         | Prioritize readability over cleverness                   |
| gofmt is no one's favorite but everyone's friend    | Always format with gofmt/goimports                       |
| Return early                                        | Handle errors first, keep happy path unindented          |

## Anti-Patterns to Avoid

- Naked returns in long functions — the reader can't see what's being returned without scrolling back.
- Using `panic` for ordinary control flow — return an `error` instead.
- Passing `context.Context` inside a struct — it must be the first parameter of the function that needs it.
- Mixing value and pointer receivers on the same type — pick one receiver style and stay consistent.

See reference.md → "Anti-Patterns to Avoid" for full code.

**Remember**: Go code should be boring in the best way - predictable, consistent, and easy to understand. When in doubt, keep it simple.
