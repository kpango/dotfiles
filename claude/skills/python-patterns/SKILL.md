---
name: python-patterns
description: Pythonic idioms, PEP 8 standards, type hints, and best practices for building robust, efficient, and maintainable Python applications.
origin: ECC
---

# Python Development Patterns

Idiomatic Python patterns and best practices for building robust, efficient, and maintainable applications.

## When to Activate

- Writing new Python code
- Reviewing Python code
- Refactoring existing Python code
- Designing Python packages/modules

## Core Principles

### 1. Readability Counts

Python prioritizes readability. Code should be obvious and easy to understand.

```python
# Good: Clear and readable
def get_active_users(users: list[User]) -> list[User]:
    """Return only active users from the provided list."""
    return [user for user in users if user.is_active]


# Bad: Clever but confusing
def get_active_users(u):
    return [x for x in u if x.a]
```

### 2. Explicit is Better Than Implicit

Avoid magic; be clear about what your code does.

```python
# Good: Explicit configuration
import logging

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

# Bad: Hidden side effects
import some_module
some_module.setup()  # What does this do?
```

### 3. EAFP - Easier to Ask Forgiveness Than Permission

Python prefers exception handling over checking conditions.

```python
# Good: EAFP style
def get_value(dictionary: dict, key: str) -> Any:
    try:
        return dictionary[key]
    except KeyError:
        return default_value

# Bad: LBYL (Look Before You Leap) style
def get_value(dictionary: dict, key: str) -> Any:
    if key in dictionary:
        return dictionary[key]
    else:
        return default_value
```

## Detailed Pattern Catalog

The following pattern categories have full code examples (good vs. bad) in
`reference.md`. Consult it whenever you need the concrete implementation, not just
the principle:

- **Type Hints** — basic annotations, Python 3.9+ built-in generics, type aliases/TypeVar, Protocol-based duck typing
- **Error Handling Patterns** — specific exception handling, exception chaining, custom exception hierarchies
- **Context Managers** — resource management with `with`, custom `@contextmanager` functions, context manager classes
- **Comprehensions and Generators** — list comprehensions, generator expressions, generator functions
- **Data Classes and Named Tuples** — `@dataclass`, validation via `__post_init__`, `NamedTuple`
- **Decorators** — function decorators, parameterized decorators, class-based decorators
- **Concurrency Patterns** — threading for I/O-bound work, multiprocessing for CPU-bound work, async/await
- **Package Organization** — standard project layout, import conventions, `__init__.py` exports
- **Memory and Performance** — `__slots__`, generators for large data, avoiding string concatenation in loops
- **Python Tooling Integration** — essential commands (black/ruff/mypy/pytest/bandit), `pyproject.toml` configuration

## Quick Reference: Python Idioms

| Idiom               | Description                                     |
| ------------------- | ----------------------------------------------- |
| EAFP                | Easier to Ask Forgiveness than Permission       |
| Context managers    | Use `with` for resource management              |
| List comprehensions | For simple transformations                      |
| Generators          | For lazy evaluation and large datasets          |
| Type hints          | Annotate function signatures                    |
| Dataclasses         | For data containers with auto-generated methods |
| `__slots__`         | For memory optimization                         |
| f-strings           | For string formatting (Python 3.6+)             |
| `pathlib.Path`      | For path operations (Python 3.4+)               |
| `enumerate`         | For index-element pairs in loops                |

## Anti-Patterns to Avoid

```python
# Bad: Mutable default arguments
def append_to(item, items=[]):
    items.append(item)
    return items

# Good: Use None and create new list
def append_to(item, items=None):
    if items is None:
        items = []
    items.append(item)
    return items

# Bad: Checking type with type()
if type(obj) == list:
    process(obj)

# Good: Use isinstance
if isinstance(obj, list):
    process(obj)

# Bad: Comparing to None with ==
if value == None:
    process()

# Good: Use is
if value is None:
    process()

# Bad: from module import *
from os.path import *

# Good: Explicit imports
from os.path import join, exists

# Bad: Bare except
try:
    risky_operation()
except:
    pass

# Good: Specific exception
try:
    risky_operation()
except SpecificError as e:
    logger.error(f"Operation failed: {e}")
```

**Remember**: Python code should be readable, explicit, and follow the principle of least surprise. When in doubt, prioritize clarity over cleverness.
