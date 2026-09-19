# ADR-0002: Trim graft's per-turn hooks; retire graphify

## Status
Accepted (human-approved via Grilling design interview, 2026-09-18, codegraph-tooling-consolidation
mission).

## Context
The user asked whether supermemory/graft/executor(codegraph)/graphify are all necessary, wanting
lower token consumption and faster generation. A read-only survey (Explore agent) plus live
measurement in this worktree established the actual cost profile:

| Hook | Event | Measured latency | Notes |
|---|---|---|---|
| graft `prompt` | UserPromptSubmit, every prompt | 425ms | injects ~90 tokens of context every turn regardless of relevance |
| graft `post-edit` | PostToolUse, every Write/Edit/MultiEdit | **3040ms** | `handlePostEdit` (`@nanonets/graft`'s own `dist/claude/hooks.js:193-204`) calls `readWiring(dir)`, parsing the *entire* wiring graph from disk on every single edit, just to emit a "blast radius" hint |
| graft `tool-savings` | PostToolUse, on Bash/Read/Grep/Glob/mcp__graft__ | 113ms | telemetry only, typically empty output |
| graft `session-start` | SessionStart, once/session | 1109ms | calls `runUpkeep()` -> `reconcileWiring()`; **live-reproduced during this mission's own measurement**: this exact invocation re-triggered the previously-documented silent-revert bug in this fresh worktree (see CLAUDE.md's "Reverted-file detection and auto-repair" section from the prior codegraph-tooling-refinement mission) |
| graft `stop` | Stop, once/session | 121ms | |
| graphify hint | PreToolUse:Bash, on Bash calls | 60ms | one-line suggestion only |
| executor (cold daemon spawn) | on-demand, first call after idle | 7.5s | one-time tax; not measured warm |
| supermemory `sm_inject` | SessionStart, once/session | ~0ms | server not running in this environment (never enabled via systemd) — currently free because currently inert |

A typical turn with a couple of edits pays roughly 425ms (prompt) + 2×3040ms (post-edit) ≈ 6.5s of
graft hook latency alone, before any actual model/tool work.

## Decisions

1. **Remove graft's `post-edit` (PostToolUse) hook entry** from `.claude/settings.json`. Its sole
   purpose is the blast-radius hint; at 3.0s per edit this is the single largest cost identified.
   graft's MCP tools (`graft_find_code`/`graft_trace_calls`/etc., already exposed via `.mcp.json`)
   remain available for the same information on request.
2. **Remove graft's `prompt` (UserPromptSubmit) hook entry**. Stops the unconditional
   ~90-token/425ms injection on every single turn; the agent can still call `graft ask`/the MCP
   tools when a turn actually needs code context, per CLAUDE.md's existing "Graft — repo context
   graph" usage guidance (kept, since manual usage is unaffected).
3. **Remove graft's `tool-savings` (PostToolUse) hook entry**. Telemetry-only, fires on nearly
   every tool call; no functional loss from removing it.
4. **Remove graft's `session-start` hook entry** (the `graft-hooks.cjs session-start` one, NOT the
   `graft-integrity-check.cjs` entry in the same SessionStart array — that one is kept, see below).
   This removes both the 1.1s per-session cost AND the Claude-Code-hook-side trigger for the
   documented silent-wiring-revert bug (`runUpkeep()`/`reconcileWiring()` is only known to run from
   "Claude Code's session-start hook" and "the MCP server's own boot path" per graft's own source
   comments — removing this hook eliminates the first trigger; the second (`graft mcp` server boot,
   e.g. when `.mcp.json` causes Claude Code to spawn it) is NOT within this repo's control and may
   still independently re-trigger the same upkeep, so this is a reduction in exposure, not a proven
   elimination).
5. **Keep `graft-integrity-check.cjs`'s wiring on both SessionStart and Stop.** It is cheap (25ms),
   and remains the only defense against the revert happening via the MCP-server-boot path noted
   above, which this mission does not (and cannot, without patching graft's own vendor code) close.
6. **Keep graft's `stop` hook** (121ms, low cost, provides the end-of-session summary) and **keep
   the `.mcp.json` MCP server registration** (on-demand, zero cost when not called).
7. **Retire graphify entirely.** Rationale: graphify and graft serve the same "code understanding
   via a prebuilt graph" purpose (CLAUDE.md's own prior text called them "complementary, not a
   migration" with "no house rule yet" on which to prefer — an unclear split the user chose to
   resolve by consolidating on one tool, graft, rather than maintaining two.) graphify's own
   runtime cost was already low (60ms hint, free AST updates), so this step's benefit is
   scope/maintenance simplification and CLAUDE.md/AGENTS.md token reduction, not primarily a
   latency win. When asked how deep the removal sweep should go, the user chose the maximum of 3
   tiers offered; the executed scope, in full:
   - **Tier 1 (functional wiring)**: git merge driver (`.gitattributes` + `.git/config`'s
     `merge.graphify.driver`) and post-commit/post-checkout git hooks deregistered. Note: the
     `.git/config`/`.git/hooks` deregistration is local, untracked machine state — it is not part
     of this diff and cannot be verified by reviewing the diff/PR alone; it was done directly in
     this worktree's common git dir during EXECUTE, the same way the MCP-server-boot revert trigger
     noted in decision 4 is also outside what this diff can prove. Committed graph
     artifacts (`.claude/graph/graphify/`, 3.3MB/95k lines) removed; per-harness Claude Code
     `PreToolUse:Bash`/`PreCompact` hook entries, the Pi MCP-tool bridge
     (`graphify-bridge.ts`/its test), the AGY `hooks.json` `graphify-assistant` block, and all
     associated hint-config/test files removed across all 3 harnesses;
     `validate-harness.sh`/`test-all-harnesses.sh` checks for graphify removed from all 3 harnesses.
     Also found and removed during the exhaustive re-sweep (functional dead/broken references not
     originally enumerated when this ADR was first drafted): the `graphify()` zsh wrapper
     (`zsh/05-functions.zsh`), the `graphifyy` pip install in `dockers/tools.Dockerfile`, the
     `test-graphify-hint.sh` CI step in `.github/workflows/agent-sync-verify.yaml`, and the now-dead
     `graphify_hint` handler/dispatch entries in `agent/scripts/hooks/decide.py` +
     `eval_graphify_hint` in `agent/scripts/hooks/rule_engine.py` (the shared decide.py judgment
     engine these two hooked into is otherwise unrelated to graphify and was not otherwise touched).
   - **Tier 2 (documentation)**: the `## graphify` section and all graphify-graft comparison
     paragraphs removed from CLAUDE.md; stale graphify table rows/prose removed from
     `agent/AGENTS.md`, `agent/AGENTS-claude-supplement.md`, `agent/AGENTS-pi-supplement.md`,
     `agent/SYSTEM-pi-supplement.md`, `agent/ROUTING_CATALOG.md`, `agent/rules/impact-scope.md`,
     `agent/README.md` (current-state claims only — the file's own explicitly-marked historical
     migration-record sections, dated and captioned "意図的にそのまま残してある", were left
     untouched as accurate history, not live guidance); generated files
     (`agent/harnesses/{agy,pi}/AGENTS.md`, `agent/harnesses/pi/SYSTEM.md`) re-generated from their
     fixed source templates via the existing `gen-agents-md-for-*.sh`/`gen-system-md-for-pi.sh`
     scripts rather than hand-edited.
   - **Tier 3 (SKILL.md + Nix)**: the 3 Tier-B-protected core orchestration skill files
     (`agent/skills/{swarm-architect,swarm-explore,swarm-loop}/SKILL.md`) updated to reference
     `graft ask`/`graft` in place of `graphify query`/`graphify`; the `graphify` Nix package
     declaration removed from `nix/modules/home/packages/shared.nix`, and the
     `datamodel-code-generator`/`tree-sitter-grammars` `pythonPackagesExtensions` overrides removed
     from `nix/overlays/default.nix` (both existed solely to work around build/metadata bugs in
     graphify's own transitive Python dependencies; confirmed via repo-wide grep that no other
     package depends on either override before removing them). This is the step that actually
     uninstalls graphify system-wide on the next `home-manager switch`, not just un-wires it from
     this one repo.
   Deliberately left untouched as genuinely historical (not stale live guidance): `@fix_plan.md`
   and `agent/skills/swarm-meta/harness-registry.tsv`'s own past mission entries, `ADR-0001`'s
   historical mentions, `agent/hooks/pi/lib/shared.ts`'s past-tense provenance comments, and
   `agent/harnesses/pi/extensions/lib/graft-bridge.test.ts`'s use of the string `"graphify_query"`
   as an arbitrary example of a non-existent tool name in a negative test assertion.

## Consequences
- Faster edits and prompts: the two largest measured per-turn costs (post-edit 3.0s, prompt 425ms)
  are eliminated, along with per-tool-call telemetry (tool-savings) and per-session overhead
  (session-start 1.1s).
- Loss of automatic context: the agent no longer gets unsolicited "here's relevant code for this
  task" (prompt hook) or "here's the blast radius of this edit" (post-edit hook) injections. Both
  remain available on-demand via graft's MCP tools/CLI — this is a shift from push to pull, not a
  capability removal.
- The silent-wiring-revert bug's Claude-Code-hook-side trigger is removed, but the MCP-server-boot
  path is untouched (out of this repo's control) — `graft-integrity-check.cjs` remains necessary
  and is kept on both SessionStart and Stop for this reason.
- graphify's git-level mechanisms (merge driver, post-commit/post-checkout hooks) and committed
  graph artifacts are removed; a fresh clone/worktree no longer has a graphify graph available at
  all going forward. graft is now the sole code-graph tool for this repo.
- supermemory and executor are unchanged (already cheap/on-demand per the measured cost profile;
  out of scope for this decision).
