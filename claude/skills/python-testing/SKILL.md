---
name: python-testing
description: Python testing strategies using pytest, TDD methodology, fixtures, mocking, parametrization, and coverage requirements.
origin: ECC
---

# Python Testing Patterns

Comprehensive testing strategies for Python applications using pytest, TDD methodology, and best practices.

Full code examples for every pattern below live in `reference.md` (same directory, one level deep).
This file covers when to use each pattern and the core decision criteria; `reference.md` is the catalog.

## When to Activate

- Writing new Python code (follow TDD: red, green, refactor)
- Designing test suites for Python projects
- Reviewing Python test coverage
- Setting up testing infrastructure

## Core Testing Philosophy

### Test-Driven Development (TDD)

Always follow the TDD cycle:

1. **RED**: Write a failing test for the desired behavior
2. **GREEN**: Write minimal code to make the test pass
3. **REFACTOR**: Improve code while keeping tests green

```python
# Step 1: Write failing test (RED)
def test_add_numbers():
    result = add(2, 3)
    assert result == 5

# Step 2: Write minimal implementation (GREEN)
def add(a, b):
    return a + b

# Step 3: Refactor if needed (REFACTOR)
```

### Coverage Requirements

- **Target**: 80%+ code coverage
- **Critical paths**: 100% coverage required
- Use `pytest --cov` to measure coverage

```bash
pytest --cov=mypackage --cov-report=term-missing --cov-report=html
```

## pytest Fundamentals

Basic test structure (plain `assert` statements) and the full assertion vocabulary
(equality, truthiness, membership, type checks, `pytest.raises` for exceptions) —
see **"pytest Fundamentals"** in `reference.md`.

## Fixtures

Use fixtures to eliminate setup/teardown duplication. Prefer the narrowest scope that
still avoids repeated work: function scope by default, `module`/`session` scope only for
expensive shared resources, `autouse=True` sparingly (only for cross-cutting setup like
config reset), and `conftest.py` for fixtures shared across multiple test files.

See **"Fixtures"** in `reference.md` for: basic usage, setup/teardown with `yield`,
scopes (function/module/session), parameterized fixtures, using multiple fixtures,
autouse fixtures, and `conftest.py` examples.

## Parametrization

Use `@pytest.mark.parametrize` instead of looping inside a test or duplicating near-identical
test functions — one assertion path, many input rows. Add `ids=` when the input values
themselves aren't self-descriptive in test output.

See **"Parametrization"** in `reference.md` for: basic parametrization, multiple parameters,
parametrize with IDs, and parametrized fixtures (e.g. running the same test against multiple
DB backends).

## Markers and Test Selection

Use custom markers (`@pytest.mark.slow`, `@pytest.mark.integration`, `@pytest.mark.unit`)
to let CI and local runs select subsets via `pytest -m "..."`. Always register custom markers
in `pytest.ini`/`pyproject.toml` with `--strict-markers` so typos fail loudly instead of
silently no-op'ing.

See **"Markers and Test Selection"** in `reference.md` for marker definitions, selection
commands, and the `pytest.ini` `markers =` block.

## Mocking and Patching

Mock external dependencies (network calls, DB connections, filesystem) — never let a unit
test depend on a real external service. Prefer `autospec=True` so mocks fail if the mocked
API's signature doesn't match. Use `side_effect` to simulate exceptions, not manual
try/except scaffolding in the mock.

See **"Mocking and Patching"** in `reference.md` for: mocking functions, mocking return
values, mocking exceptions, mocking context managers (`mock_open`), autospec, mocking class
instances, and `PropertyMock`.

## Testing Async Code

Async test functions need `@pytest.mark.asyncio` (from `pytest-asyncio`) and async fixtures
need `async def` + `yield`. Assert mock calls with `assert_awaited_once()` / `assert_awaited_once_with()`,
not the sync `assert_called_once()` variants.

See **"Testing Async Code"** in `reference.md` for async tests, async fixtures, and mocking
async functions.

## Testing Exceptions

Prefer `pytest.raises(...)` as a context manager over manual try/except-and-fail scaffolding.
Use `match=` for message substrings and `exc_info.value` to assert on custom exception
attributes.

See **"Testing Exceptions"** in `reference.md` for expected-exception and exception-attribute
examples.

## Testing Side Effects

For filesystem-touching code, prefer pytest's built-in `tmp_path` (pathlib) or `tmpdir` (py.path)
fixtures over manually managed `tempfile` + `try/finally` — they're auto-cleaned and test-scoped.

See **"Testing Side Effects"** in `reference.md` for temp-file processing, `tmp_path`, and
`tmpdir` examples.

## Test Organization

Split tests into `unit/`, `integration/`, `e2e/` directories under `tests/`, with shared
fixtures in `tests/conftest.py`. Group related tests into a `TestXxx` class with an
`autouse` setup fixture when they share expensive setup.

See **"Test Organization"** in `reference.md` for the directory layout and a `TestUserService`
class example.

## Best Practices

### DO

- **Follow TDD**: Write tests before code (red-green-refactor)
- **Test one thing**: Each test should verify a single behavior
- **Use descriptive names**: `test_user_login_with_invalid_credentials_fails`
- **Use fixtures**: Eliminate duplication with fixtures
- **Mock external dependencies**: Don't depend on external services
- **Test edge cases**: Empty inputs, None values, boundary conditions
- **Aim for 80%+ coverage**: Focus on critical paths
- **Keep tests fast**: Use marks to separate slow tests

### DON'T

- **Don't test implementation**: Test behavior, not internals
- **Don't use complex conditionals in tests**: Keep tests simple
- **Don't ignore test failures**: All tests must pass
- **Don't test third-party code**: Trust libraries to work
- **Don't share state between tests**: Tests should be independent
- **Don't catch exceptions in tests**: Use `pytest.raises`
- **Don't use print statements**: Use assertions and pytest output
- **Don't write tests that are too brittle**: Avoid over-specific mocks

## Common Patterns

Ready-to-adapt patterns for testing FastAPI/Flask endpoints, database operations (with a
rollback-per-test session fixture), and class-based test suites.

See **"Common Patterns"** in `reference.md` for the full API-endpoint, database, and
class-method examples.

## pytest Configuration

Configure `testpaths`, test discovery globs, `--strict-markers`, coverage options, and marker
registration in either `pytest.ini` or `pyproject.toml` (`[tool.pytest.ini_options]`) — pick one
per project, don't split config across both.

See **"pytest Configuration"** in `reference.md` for complete `pytest.ini` and `pyproject.toml`
examples.

## Running Tests

```bash
# Run all tests
pytest

# Run specific file
pytest tests/test_utils.py

# Run specific test
pytest tests/test_utils.py::test_function

# Run with verbose output
pytest -v

# Run with coverage
pytest --cov=mypackage --cov-report=html

# Run only fast tests
pytest -m "not slow"

# Run until first failure
pytest -x

# Run and stop on N failures
pytest --maxfail=3

# Run last failed tests
pytest --lf

# Run tests with pattern
pytest -k "test_user"

# Run with debugger on failure
pytest --pdb
```

## Quick Reference

| Pattern                      | Usage                          |
| ---------------------------- | ------------------------------ |
| `pytest.raises()`            | Test expected exceptions       |
| `@pytest.fixture()`          | Create reusable test fixtures  |
| `@pytest.mark.parametrize()` | Run tests with multiple inputs |
| `@pytest.mark.slow`          | Mark slow tests                |
| `pytest -m "not slow"`       | Skip slow tests                |
| `@patch()`                   | Mock functions and classes     |
| `tmp_path` fixture           | Automatic temp directory       |
| `pytest --cov`               | Generate coverage report       |
| `assert`                     | Simple and readable assertions |

**Remember**: Tests are code too. Keep them clean, readable, and maintainable. Good tests catch bugs; great tests prevent them.
