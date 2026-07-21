---
name: cpp-patterns
description: C++ coding standards based on the C++ Core Guidelines (isocpp.github.io). Use when writing, reviewing, or refactoring C++ code to enforce modern, safe, and idiomatic practices.
origin: ECC
---

# C++ Coding Standards (C++ Core Guidelines)

Comprehensive coding standards for modern C++ (C++17/20/23) derived from the [C++ Core Guidelines](https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines). Enforces type safety, resource safety, immutability, and clarity.

Detailed code examples, pattern catalogs, and anti-pattern walkthroughs for every section below live in [reference.md](reference.md) — this file holds the rules and decision criteria; reference.md holds the "how".

## When to Use

- Writing new C++ code (classes, functions, templates)
- Reviewing or refactoring existing C++ code
- Making architectural decisions in C++ projects
- Enforcing consistent style across a C++ codebase
- Choosing between language features (e.g., `enum` vs `enum class`, raw pointer vs smart pointer)

### When NOT to Use

- Non-C++ projects
- Legacy C codebases that cannot adopt modern C++ features
- Embedded/bare-metal contexts where specific guidelines conflict with hardware constraints (adapt selectively)

## Cross-Cutting Principles

These themes recur across the entire guidelines and form the foundation:

1. **RAII everywhere** (P.8, R.1, E.6, CP.20): Bind resource lifetime to object lifetime
2. **Immutability by default** (P.10, Con.1-5, ES.25): Start with `const`/`constexpr`; mutability is the exception
3. **Type safety** (P.4, I.4, ES.46-49, Enum.3): Use the type system to prevent errors at compile time
4. **Express intent** (P.3, F.1, NL.1-2, T.10): Names, types, and concepts should communicate purpose
5. **Minimize complexity** (F.2-3, ES.5, Per.4-5): Simple code is correct code
6. **Value semantics over pointer semantics** (C.10, R.3-5, F.20, CP.31): Prefer returning by value and scoped objects

## SOLID Principles in Modern C++

| SOLID                       | C++ Implementation                                                              | Related Guideline |
| --------------------------- | ------------------------------------------------------------------------------- | ----------------- |
| **S** Single Responsibility | 1 class = 1 reason to change; members belong to the same responsibility         | F.2               |
| **O** Open/Closed           | Extend via `virtual`/`override` + templates/concepts; don't modify base classes | C.128, T.1        |
| **L** Liskov Substitution   | Derived classes must not strengthen preconditions or weaken postconditions      | C.35, C.128       |
| **I** Interface Segregation | Separate thin interface classes with only pure virtual functions                | C.9, I.1          |
| **D** Dependency Inversion  | Depend on abstract classes/concepts, not concrete types                         | T.10, I.4         |

See reference.md → "SOLID Principles in Modern C++" for SRP/OCP/LSP/ISP+DIP code examples.

## Philosophy & Interfaces (P._, I._)

### Key Rules

| Rule     | Summary                                                |
| -------- | ------------------------------------------------------ |
| **P.1**  | Express ideas directly in code                         |
| **P.3**  | Express intent                                         |
| **P.4**  | Ideally, a program should be statically type safe      |
| **P.5**  | Prefer compile-time checking to run-time checking      |
| **P.8**  | Don't leak any resources                               |
| **P.10** | Prefer immutable data to mutable data                  |
| **I.1**  | Make interfaces explicit                               |
| **I.2**  | Avoid non-const global variables                       |
| **I.4**  | Make interfaces precisely and strongly typed           |
| **I.11** | Never transfer ownership by a raw pointer or reference |
| **I.23** | Keep the number of function arguments low              |

See reference.md → "Philosophy & Interfaces" for DO/DON'T examples.

## Functions (F.\*)

### Key Rules

| Rule     | Summary                                                                        |
| -------- | ------------------------------------------------------------------------------ |
| **F.1**  | Package meaningful operations as carefully named functions                     |
| **F.2**  | A function should perform a single logical operation                           |
| **F.3**  | Keep functions short and simple                                                |
| **F.4**  | If a function might be evaluated at compile time, declare it `constexpr`       |
| **F.6**  | If your function must not throw, declare it `noexcept`                         |
| **F.8**  | Prefer pure functions                                                          |
| **F.16** | For "in" parameters, pass cheaply-copied types by value and others by `const&` |
| **F.20** | For "out" values, prefer return values to output parameters                    |
| **F.21** | To return multiple "out" values, prefer returning a struct                     |
| **F.43** | Never return a pointer or reference to a local object                          |

### Anti-Patterns

- Returning `T&&` from functions (F.45)
- Using `va_arg` / C-style variadics (F.55)
- Capturing by reference in lambdas passed to other threads (F.53)
- Returning `const T` which inhibits move semantics (F.49)

See reference.md → "Functions" for parameter-passing and constexpr/pure-function examples.

## Classes & Class Hierarchies (C.\*)

### Key Rules

| Rule      | Summary                                                                             |
| --------- | ----------------------------------------------------------------------------------- |
| **C.2**   | Use `class` if invariant exists; `struct` if data members vary independently        |
| **C.9**   | Minimize exposure of members                                                        |
| **C.20**  | If you can avoid defining default operations, do (Rule of Zero)                     |
| **C.21**  | If you define or `=delete` any copy/move/destructor, handle them all (Rule of Five) |
| **C.35**  | Base class destructor: public virtual or protected non-virtual                      |
| **C.41**  | A constructor should create a fully initialized object                              |
| **C.46**  | Declare single-argument constructors `explicit`                                     |
| **C.67**  | A polymorphic class should suppress public copy/move                                |
| **C.128** | Virtual functions: specify exactly one of `virtual`, `override`, or `final`         |

### Anti-Patterns

- Calling virtual functions in constructors/destructors (C.82)
- Using `memset`/`memcpy` on non-trivial types (C.90)
- Providing different default arguments for virtual function and overrider (C.140)
- Making data members `const` or references, which suppresses move/copy (C.12)

See reference.md → "Classes & Class Hierarchies" for Rule of Zero/Five and class hierarchy examples.

## Resource Management (R.\*)

### Key Rules

| Rule     | Summary                                                        |
| -------- | -------------------------------------------------------------- |
| **R.1**  | Manage resources automatically using RAII                      |
| **R.3**  | A raw pointer (`T*`) is non-owning                             |
| **R.5**  | Prefer scoped objects; don't heap-allocate unnecessarily       |
| **R.10** | Avoid `malloc()`/`free()`                                      |
| **R.11** | Avoid calling `new` and `delete` explicitly                    |
| **R.20** | Use `unique_ptr` or `shared_ptr` to represent ownership        |
| **R.21** | Prefer `unique_ptr` over `shared_ptr` unless sharing ownership |
| **R.22** | Use `make_shared()` to make `shared_ptr`s                      |

### Anti-Patterns

- Naked `new`/`delete` (R.11)
- `malloc()`/`free()` in C++ code (R.10)
- Multiple resource allocations in a single expression (R.13 -- exception safety hazard)
- `shared_ptr` where `unique_ptr` suffices (R.21)

See reference.md → "Resource Management" for smart-pointer usage and the RAII `FileHandle` pattern.

## Expressions & Statements (ES.\*)

### Key Rules

| Rule      | Summary                                                                |
| --------- | ---------------------------------------------------------------------- |
| **ES.5**  | Keep scopes small                                                      |
| **ES.20** | Always initialize an object                                            |
| **ES.23** | Prefer `{}` initializer syntax                                         |
| **ES.25** | Declare objects `const` or `constexpr` unless modification is intended |
| **ES.28** | Use lambdas for complex initialization of `const` variables            |
| **ES.45** | Avoid magic constants; use symbolic constants                          |
| **ES.46** | Avoid narrowing/lossy arithmetic conversions                           |
| **ES.47** | Use `nullptr` rather than `0` or `NULL`                                |
| **ES.48** | Avoid casts                                                            |
| **ES.50** | Don't cast away `const`                                                |

### Anti-Patterns

- Uninitialized variables (ES.20)
- Using `0` or `NULL` as pointer (ES.47 -- use `nullptr`)
- C-style casts (ES.48 -- use `static_cast`, `const_cast`, etc.)
- Casting away `const` (ES.50)
- Magic numbers without named constants (ES.45)
- Mixing signed and unsigned arithmetic (ES.100)
- Reusing names in nested scopes (ES.12)

See reference.md → "Expressions & Statements" for the initialization example.

## Error Handling (E.\*)

### Key Rules

| Rule     | Summary                                                                      |
| -------- | ---------------------------------------------------------------------------- |
| **E.1**  | Develop an error-handling strategy early in a design                         |
| **E.2**  | Throw an exception to signal that a function can't perform its assigned task |
| **E.6**  | Use RAII to prevent leaks                                                    |
| **E.12** | Use `noexcept` when throwing is impossible or unacceptable                   |
| **E.14** | Use purpose-designed user-defined types as exceptions                        |
| **E.15** | Throw by value, catch by reference                                           |
| **E.16** | Destructors, deallocation, and swap must never fail                          |
| **E.17** | Don't try to catch every exception in every function                         |

### Anti-Patterns

- Throwing built-in types like `int` or string literals (E.14)
- Catching by value (slicing risk) (E.15)
- Empty catch blocks that silently swallow errors
- Using exceptions for flow control (E.3)
- Error handling based on global state like `errno` (E.28)

See reference.md → "Error Handling" for the exception hierarchy example.

## Constants & Immutability (Con.\*)

### All Rules

| Rule      | Summary                                                     |
| --------- | ----------------------------------------------------------- |
| **Con.1** | By default, make objects immutable                          |
| **Con.2** | By default, make member functions `const`                   |
| **Con.3** | By default, pass pointers and references to `const`         |
| **Con.4** | Use `const` for values that don't change after construction |
| **Con.5** | Use `constexpr` for values computable at compile time       |

See reference.md → "Constants & Immutability" for the full `Sensor` example.

## Concurrency & Parallelism (CP.\*)

### Key Rules

| Rule       | Summary                                                       |
| ---------- | ------------------------------------------------------------- |
| **CP.2**   | Avoid data races                                              |
| **CP.3**   | Minimize explicit sharing of writable data                    |
| **CP.4**   | Think in terms of tasks, rather than threads                  |
| **CP.8**   | Don't use `volatile` for synchronization                      |
| **CP.20**  | Use RAII, never plain `lock()`/`unlock()`                     |
| **CP.21**  | Use `std::scoped_lock` to acquire multiple mutexes            |
| **CP.22**  | Never call unknown code while holding a lock                  |
| **CP.42**  | Don't wait without a condition                                |
| **CP.44**  | Remember to name your `lock_guard`s and `unique_lock`s        |
| **CP.100** | Don't use lock-free programming unless you absolutely have to |

### Anti-Patterns

- `volatile` for synchronization (CP.8 -- it's for hardware I/O only)
- Detaching threads (CP.26 -- lifetime management becomes nearly impossible)
- Unnamed lock guards: `std::lock_guard<std::mutex>(m);` destroys immediately (CP.44)
- Holding locks while calling callbacks (CP.22 -- deadlock risk)
- Lock-free programming without deep expertise (CP.100)

See reference.md → "Concurrency & Parallelism" for the `ThreadSafeQueue` and multi-mutex `transfer` examples.

## Templates & Generic Programming (T.\*)

### Key Rules

| Rule      | Summary                                                     |
| --------- | ----------------------------------------------------------- |
| **T.1**   | Use templates to raise the level of abstraction             |
| **T.2**   | Use templates to express algorithms for many argument types |
| **T.10**  | Specify concepts for all template arguments                 |
| **T.11**  | Use standard concepts whenever possible                     |
| **T.13**  | Prefer shorthand notation for simple concepts               |
| **T.43**  | Prefer `using` over `typedef`                               |
| **T.120** | Use template metaprogramming only when you really need to   |
| **T.144** | Don't specialize function templates (overload instead)      |

### Anti-Patterns

- Unconstrained templates in visible namespaces (T.47)
- Specializing function templates instead of overloading (T.144)
- Template metaprogramming where `constexpr` suffices (T.120)
- `typedef` instead of `using` (T.43)

See reference.md → "Templates & Generic Programming" for C++20 concepts examples.

## Standard Library (SL.\*)

### Key Rules

| Rule         | Summary                                                |
| ------------ | ------------------------------------------------------ |
| **SL.1**     | Use libraries wherever possible                        |
| **SL.2**     | Prefer the standard library to other libraries         |
| **SL.con.1** | Prefer `std::array` or `std::vector` over C arrays     |
| **SL.con.2** | Prefer `std::vector` by default                        |
| **SL.str.1** | Use `std::string` to own character sequences           |
| **SL.str.2** | Use `std::string_view` to refer to character sequences |
| **SL.io.50** | Avoid `endl` (use `'\n'` -- `endl` forces a flush)     |

See reference.md → "Standard Library" for the vector/array/string_view example.

## Enumerations (Enum.\*)

### Key Rules

| Rule       | Summary                               |
| ---------- | ------------------------------------- |
| **Enum.1** | Prefer enumerations over macros       |
| **Enum.3** | Prefer `enum class` over plain `enum` |
| **Enum.5** | Don't use ALL_CAPS for enumerators    |
| **Enum.6** | Avoid unnamed enumerations            |

See reference.md → "Enumerations" for the scoped-enum example.

## Source Files & Naming (SF._, NL._)

### Key Rules

| Rule      | Summary                                                          |
| --------- | ---------------------------------------------------------------- |
| **SF.1**  | Use `.cpp` for code files and `.h` for interface files           |
| **SF.7**  | Don't write `using namespace` at global scope in a header        |
| **SF.8**  | Use `#include` guards for all `.h` files                         |
| **SF.11** | Header files should be self-contained                            |
| **NL.5**  | Avoid encoding type information in names (no Hungarian notation) |
| **NL.8**  | Use a consistent naming style                                    |
| **NL.9**  | Use ALL_CAPS for macro names only                                |
| **NL.10** | Prefer `underscore_style` names                                  |

### Anti-Patterns

- `using namespace std;` in a header at global scope (SF.7)
- Headers that depend on inclusion order (SF.10, SF.11)
- Hungarian notation like `strName`, `iCount` (NL.5)
- ALL_CAPS for anything other than macros (NL.9)

See reference.md → "Source Files & Naming" for header-guard and naming-convention examples.

## Performance (Per.\*)

### Key Rules

| Rule       | Summary                                                  |
| ---------- | -------------------------------------------------------- |
| **Per.1**  | Don't optimize without reason                            |
| **Per.2**  | Don't optimize prematurely                               |
| **Per.6**  | Don't make claims about performance without measurements |
| **Per.7**  | Design to enable optimization                            |
| **Per.10** | Rely on the static type system                           |
| **Per.11** | Move computation from run time to compile time           |
| **Per.19** | Access memory predictably                                |

### Anti-Patterns

- Optimizing without profiling data (Per.1, Per.6)
- Choosing "clever" low-level code over clear abstractions (Per.4, Per.5)
- Ignoring data layout and cache behavior (Per.19)

See reference.md → "Performance" for the compile-time lookup table and contiguous-data examples.

## Quick Reference Checklist

Before marking C++ work complete:

- [ ] No raw `new`/`delete` -- use smart pointers or RAII (R.11)
- [ ] Objects initialized at declaration (ES.20)
- [ ] Variables are `const`/`constexpr` by default (Con.1, ES.25)
- [ ] Member functions are `const` where possible (Con.2)
- [ ] `enum class` instead of plain `enum` (Enum.3)
- [ ] `nullptr` instead of `0`/`NULL` (ES.47)
- [ ] No narrowing conversions (ES.46)
- [ ] No C-style casts (ES.48)
- [ ] Single-argument constructors are `explicit` (C.46)
- [ ] Rule of Zero or Rule of Five applied (C.20, C.21)
- [ ] Base class destructors are public virtual or protected non-virtual (C.35)
- [ ] Templates are constrained with concepts (T.10)
- [ ] No `using namespace` in headers at global scope (SF.7)
- [ ] Headers have include guards and are self-contained (SF.8, SF.11)
- [ ] Locks use RAII (`scoped_lock`/`lock_guard`) (CP.20)
- [ ] Exceptions are custom types, thrown by value, caught by reference (E.14, E.15)
- [ ] `'\n'` instead of `std::endl` (SL.io.50)
- [ ] No magic numbers (ES.45)
