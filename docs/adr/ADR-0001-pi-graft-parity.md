# ADR-0001: Pi Coding Agent parity for graft

## Status
Accepted (human-approved via Grilling design interview, 2026-09-13, codegraph-tooling-refinement
mission, task T5).

## Context
T4 of this mission adopted `@nanonets/graft` for Claude Code, Gemini CLI, and OpenCode
(`--no-global`, this repo only). `graft init` itself has no Pi Coding Agent target at all — its
own `HOSTS` registry (`dist/hosts/registry.js`) and MCP target switch
(`dist/hosts/mcp-config.js`) contain no `pi`/`primeagent` case, confirmed by reading the
installed source directly (`@fix_plan.md` T4 row: "pi/primeagentは公式非対応(graft init
--list-agentsで確認)のためOut of Scope"). The user asked, after that GATE, to bring the same
functionality to Pi anyway.

## Decisions

1. **Routing: via `executor`, not a direct `pi/mcp.json` entry.**
   `executor` (T1, MCP gateway, already registered for both Pi and Claude Code) exposes
   `executor.mcp.addServer` for registering an arbitrary stdio MCP server as a catalog
   integration, plus `executor.coreTools.connections.create` (template "none" for no-auth) to
   produce callable tools from it. Registered here (human-approved, both calls required
   executor's own approval gate):
   - integration slug: `graft-dotfiles`
   - `{transport: "stdio", command: "graft", args: ["mcp"], cwd: "/home/kpango/go/src/github.com/kpango/dotfiles"}`
   - connection: owner `user`, name `graft-dotfiles` → address `graft-dotfiles.user.graftDotfiles`
   - Tools now live at `graft-dotfiles.user.graftDotfiles.{graft_find_code,graft_trace_calls,
     graft_find_all,graft_file_api,graft_repo_map,graft_check_freshness}`, callable via
     `executor call <path> '<json args>'` (verified end-to-end, 2026-09-13).

   **Known limitation, accepted deliberately**: `graft mcp [dir]` binds to ONE repo per process
   (cwd at spawn time); `executor.mcp.addServer`'s `cwd` is fixed at registration, with no
   per-call repo override anywhere in graft's exposed tools or executor's connection schema. So
   this registration only serves the dotfiles repo — it does NOT generalize the way graft's
   direct per-repo `.mcp.json`/`.gemini/settings.json` entries do (those launch a fresh
   `graft mcp` with the correct cwd automatically, per repo). Wiring graft-via-executor for
   another repo means repeating this registration there with that repo's path. This was
   presented to and accepted by the human explicitly (AskUserQuestion, "dotfilesリポ専用で
   executor登録する").

2. **Pi extensions shell out to `executor call`, reusing the existing `runCliBridge` helper**
   (`agent/harnesses/pi/extensions/lib/cli-bridge.ts`) rather than embedding a new MCP client or
   duplicating graft's own (Claude-Code-only, inaccessible-from-Pi) internal hook implementation.
   graft's actual `.claude/helpers/graft-hooks.cjs`/`graft-resolve.cjs` logic directly `import()`s
   graft's own installed JS modules — that path does not exist for Pi (different runtime, and
   graft has no public API for it beyond its CLI/MCP surface), so this is a new, independent
   implementation modeled on graft's *observed* behavior, not a port of its source.

3. **Replication scope** (human-approved, all four): a new
   `agent/harnesses/pi/extensions/graft-bridge.ts` (separate file from the existing
   `graphify-bridge.ts`, which is graphify's own tool-registration bridge and unrelated to graft)
   registers:
   - `before_agent_start` → calls `graft_find_code` with the pending task text (read defensively:
     `typeof event?.prompt === "string"`, not trusted unconditionally, matching this codebase's
     existing pattern for event-field access — see `skill-state.ts`'s `event?.systemPrompt`
     guard), and returns a `plan-mode.ts`-style non-displayed context message analogous to graft's
     Claude Code UserPromptSubmit hook (whose real output this session has directly observed
     multiple times via its own `[graft] starting points for this task: ...` injections — used as
     the concrete behavioral reference, not graft's source, since the source isn't portable).
     `before_agent_start`'s handler return value IS the delivery mechanism here — confirmed via
     `ExtensionHandler<BeforeAgentStartEvent, BeforeAgentStartEventResult>`'s Result type
     parameter (unlike `session_start`, next bullet).
   - `session_start` → one-shot `graft_repo_map` orientation, delivered via `pi.sendMessage(...)`
     (`ExtensionAPI`, not a handler return value) — `session_start`'s own `ExtensionHandler` type
     carries no Result parameter, and a return value there is silently discarded at runtime
     (`ExtensionRunner.emit()` only keeps a handler's return for
     `isSessionBeforeEvent(event)`-true events). An initial implementation wrongly returned
     `{message: ...}` here, mirroring `before_agent_start`'s shape without checking whether
     `session_start` supports the same contract — caught by this task's Checker (a real `tsc
     --noEmit --strict` compile error, not just a runtime discard) and fixed; see this task's
     trajectory/commit history, not restated here.
   - `tool_result` tracking → an approximate, independently-designed tool-savings counter (NOT a
     port of graft's internal accounting, which lives in graft's own Claude-Code-only hook code
     and is not observable or reusable from Pi) that counts calls through this bridge vs. raw
     Pi tool calls during the session, using Pi's own lowercase tool-name vocabulary (`read`,
     `grep`, `find`, `ls` — Pi has no `glob` tool, unlike Claude Code's Read/Grep/Glob naming).
     No `tool_call` handler is registered (`tool_result` alone is sufficient and is the same
     event `post-edit-lint.ts`/`stop-verify.ts` already use for this kind of outcome-filtered
     tracking).
   - `session_shutdown` → prints the same approximate savings summary, mirroring graft's Stop
     hook's role, not its computation.

   **Dropped after human-approved re-scoping (Checker finding, 2026-09-13)**: an earlier revision
   of this decision also had `status-line.ts` (existing file, extended) read these counters via a
   shared `lib/graft-stats.ts` module to show a graft-calls-this-session status badge. This relied
   on `graft-bridge.ts` and `status-line.ts` — two separate top-level Pi extension files — sharing
   one module instance. Pi's real extension loader gives each top-level extension file its own
   `jiti` instance with `moduleCache: false` (confirmed by reading the shipped
   `dist/bundle/chunks/chunk-OMWWHBTG.js`'s `createJiti(import.meta.url, {moduleCache:!1, ...` for
   every loader option branch), so the two files never actually share that state at runtime — only
   `bun test`'s single-process ESM cache made it look like they did. The badge was therefore dead
   code (always read zero) on the real runtime. Fix: the counters became local module state inside
   `graft-bridge.ts` itself (same-file state sharing between its own `pi.on(...)` handlers still
   works, since that never crossed a file boundary), `lib/graft-stats.ts` was removed, and the
   `status-line.ts` badge was reverted rather than reimplemented via a cross-file workaround (e.g.
   `globalThis`) — restoring it was judged not worth the added complexity for a nice-to-have
   addition beyond this decision's four core behaviors above.

## Consequences
- Pi users get graft's query/trace/orientation tools without any Pi-side support from graft
  itself, at the cost of a second moving part (`executor` must be running) and a repo-bound
  registration that needs repeating per additional repo.
- The tool-savings/session-summary numbers are Pi-side estimates for behavioral parity, not
  graft's actual algorithm — code comments must say so explicitly to avoid a verify-before-assert
  violation (this mission's dominant recurring failure mode in T1/T4 — see @fix_plan.md).
