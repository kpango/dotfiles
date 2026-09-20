/**
 * graft parity bridge for Pi Coding Agent ("Pi Coding Agent parity for graft").
 *
 * graft has no official Pi target (see lib/graft-executor-bridge.ts's header for the verified
 * detail), so this extension reaches it indirectly through the `executor` MCP gateway
 * (lib/graft-executor-bridge.ts's `callGraftTool`), mirroring — not porting — graft's own
 * Claude-Code-only behavior:
 *   - `before_agent_start` → one `graft_find_code` lookup seeded from the pending user prompt,
 *     injected as a non-displayed context message (mirrors graft's Claude Code UserPromptSubmit
 *     hook's observed `[graft] starting points for this task: ...` injections).
 *   - `session_start` → one `graft_repo_map` orientation call per session start, same shape.
 *   - `tool_result` → counts raw read/grep/find/ls tool calls (Pi's own built-in tool-name
 *     literals, confirmed via @earendil-works/pi-coding-agent's types.d.ts; Pi has no "glob" tool,
 *     unlike Claude Code) as an independent, approximate "what graft calls might have saved"
 *     estimate — this is NOT a port of graft's own internal token-savings accounting, which lives
 *     in graft's Claude-Code-only, non-portable source. Counted on tool_result (not tool_call),
 *     matching this codebase's own established convention in post-edit-lint.ts/stop-verify.ts of
 *     filtering by outcome rather than by call attempt.
 *   - `session_shutdown` → prints the same approximate summary, mirroring graft's Stop hook's
 *     role (visibility at session end), not its computation.
 *   - Counters are local module state in this file (NOT a shared `lib/graft-stats.ts` module, as
 *     an earlier version had it): Pi's real extension loader gives each top-level extension file
 *     its own `jiti` instance with `moduleCache: false` (confirmed by reading the shipped
 *     `dist/bundle/chunks/chunk-OMWWHBTG.js`'s `createJiti(import.meta.url, {moduleCache:!1, ...`
 *     for every loader option branch), so `graft-bridge.ts` and `status-line.ts` — two separate
 *     top-level extension files — never share a module instance in the real runtime, only in a
 *     single `bun test` process where plain ESM imports happen to share a cache. A prior design
 *     relied on that test-only sharing and had status-line.ts read this file's counters; that
 *     badge was dead code in production (always saw zero) and has been removed — see
 *     status-line.ts's git history for the reverted addition.
 *
 * `before_agent_start`'s BeforeAgentStartEvent DOES carry the pending prompt text (`event.prompt:
 * string`, "The raw user prompt text (after expansion)" — confirmed by reading
 * @earendil-works/pi-coding-agent's dist/core/extensions/types.d.ts directly), so this uses it
 * rather than approximating from some other signal.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { callGraftTool } from "./lib/graft-executor-bridge";

const RAW_SEARCH_TOOL_NAMES = new Set(["read", "grep", "find", "ls"]);

// Session counters, local to this file. Deliberately NOT a shared lib/ module — see this file's
// header for why cross-extension-file module state doesn't work under Pi's real loader.
let graftBridgeCalls = 0;
let rawSearchToolCalls = 0;

export interface GraftBridgeStats {
  graftBridgeCalls: number;
  rawSearchToolCalls: number;
}

export function getGraftBridgeStats(): GraftBridgeStats {
  return { graftBridgeCalls, rawSearchToolCalls };
}

/** テスト専用: カウンタをリセットする(bun test はプロセス内でモジュールが使い回されるため)。 */
export function resetGraftBridgeStats(): void {
  graftBridgeCalls = 0;
  rawSearchToolCalls = 0;
}

/** Pi's own built-in read-like tool names (see this file's header for the source). */
export function isRawSearchToolName(toolName: string): boolean {
  return RAW_SEARCH_TOOL_NAMES.has(toolName);
}

/**
 * Cap the text sent to graft_find_code as a query so a very long user prompt never becomes an
 * oversized single argv element to `executor call`. Truncates on a code-point boundary (not a
 * UTF-16 code unit) so it never splits a surrogate pair, and appends "…" only when truncation
 * actually happened.
 */
export function truncateForGraftQuery(text: string, maxLen = 400): string {
  const chars = Array.from(text);
  if (chars.length <= maxLen) return text;
  return chars.slice(0, Math.max(0, maxLen - 1)).join("") + "…";
}

export default function (pi: ExtensionAPI) {
  pi.on("before_agent_start", async (event) => {
    // Defensive guard, matching this codebase's established pattern for event-field access
    // (e.g. skill-state.ts's `typeof event?.systemPrompt === "string" ? event.systemPrompt : ""`)
    // rather than trusting BeforeAgentStartEvent's documented `prompt: string` unconditionally —
    // consistent with this same file's "never throw" ethos for callGraftTool. No-op, not a
    // throw, if `event.prompt` is ever absent or not a string on some future/edge-case event.
    const prompt = typeof event?.prompt === "string" ? event.prompt : null;
    if (prompt === null) return;

    const query = truncateForGraftQuery(prompt.trim());
    if (!query) return;

    const text = await callGraftTool("graft_find_code", { query });
    if (!text) return; // executor/graft unavailable — silent no-op (intentional)
    graftBridgeCalls++;

    return {
      message: {
        customType: "graft-context",
        content: text,
        display: false,
      },
    };
  });

  pi.on("session_start", async () => {
    const text = await callGraftTool("graft_repo_map", {});
    if (!text) return;
    // recorded regardless of delivery outcome: the executor call itself happened and cost the
    // same either way, and this counter tracks graft calls made, not context successfully
    // surfaced to the model (see this file's header for what it approximates).
    graftBridgeCalls++;

    // session_start's ExtensionHandler has no Result type (types.d.ts:923's
    // `ExtensionHandler<SessionStartEvent>`, no second type argument, unlike
    // `before_agent_start`'s `ExtensionHandler<BeforeAgentStartEvent, BeforeAgentStartEventResult>`)
    // — confirmed at runtime too: ExtensionRunner.emit() (runner.js) only keeps a handler's
    // return value when isSessionBeforeEvent(event) is true, which session_start is not, so a
    // `return {message: ...}` here would be silently discarded. `pi.sendMessage(...)` (on
    // ExtensionAPI, NOT ExtensionContext — types.d.ts:971) is the verified way to actually
    // deliver a message from a handler whose return value is discarded.
    pi.sendMessage({
      customType: "graft-repo-map-context",
      content: text,
      display: false,
    });
  });

  // Approximate tool-savings tracking (see this file's header for the disclaimer this covers).
  pi.on("tool_result", async (event) => {
    if ((event as { isError?: boolean }).isError) return;
    if (isRawSearchToolName(event.toolName)) {
      rawSearchToolCalls++;
    }
  });

  pi.on("session_shutdown", async (_event, ctx) => {
    const stats = getGraftBridgeStats();
    if (stats.graftBridgeCalls === 0 && stats.rawSearchToolCalls === 0) return;
    if (!ctx.hasUI) return;
    ctx.ui.notify(
      `graft-bridge (approximate, Pi-side estimate — not graft's own accounting): ` +
        `${stats.graftBridgeCalls} graft call(s) via executor, ${stats.rawSearchToolCalls} raw read/grep/find/ls tool call(s) this session.`,
      "info",
    );
  });
}
