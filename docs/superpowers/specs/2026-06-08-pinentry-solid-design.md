# Pinentry SOLID Refactoring Design

## Overview

The `pinentry-tmux` Go implementation currently resides entirely within a procedural `main.go` file. To improve maintainability and adherence to SOLID principles, we will refactor the codebase into a flat file structure within the `main` package, separating concerns and relying on interfaces.

## Architecture

We will adopt a flat structure (all files in the `main` package) but strongly separate the domain concepts:

1. **`assuan.go`** (Assuan Protocol Helpers)
   - Contains the URL encoding/decoding utilities (`assuanEncode`, `assuanDecode`).

2. **`prompter.go`** (UI Interfaces & Fallback)
   - Defines the core dependency interface:
     ```go
     type Prompter interface {
         GetPin(ctx context.Context) bool
         Confirm(ctx context.Context) bool
         SetContext(desc, prompt, errMsg, title string)
     }
     ```
   - Handles the fallback execution logic to `pinentry-tty` if tmux is unavailable.

3. **`tmux.go`** (Tmux Integration & Concrete Prompter)
   - Contains `findSock()` and `checkTmuxVersion()`.
   - Implements the `Prompter` interface via a `tmuxPrompter` struct.
   - Encapsulates temp file creation, subprocess context handling, and the secure stack-allocated `runtime/secret` operations for the Tmux popup.

4. **`server.go`** (Assuan Server)
   - Contains the `AssuanServer` struct which receives a `Prompter` dependency (Dependency Inversion).
   - Responsible for the standard input scanning loop, command routing (`SETDESC`, `GETPIN`, etc.), and standard output flushing.

5. **`main.go`** (Application Entrypoint)
   - Initializes the context and signals.
   - Detects the environment (Tmux vs Fallback).
   - Instantiates the `tmuxPrompter` and injects it into the `AssuanServer`.
   - Starts the server loop.

## Design Highlights

- **Single Responsibility (SRP):** Protocol parsing, UI rendering, and the main lifecycle are isolated into their respective files.
- **Open/Closed (OCP) & Dependency Inversion (DIP):** The `AssuanServer` depends on the `Prompter` interface. If we ever want to add a different UI (e.g., Wayland popup), we can write a new prompter without modifying the server logic.
- **Security Maintained:** The `runtime/secret` and stack allocation mechanisms recently introduced will be carefully preserved inside the `tmuxPrompter` implementation.

## Spec Self-Review

- **Placeholders:** None.
- **Consistency:** The architecture matches the user's request for a flat structure.
- **Scope:** Perfectly scoped for a single refactoring implementation plan.
