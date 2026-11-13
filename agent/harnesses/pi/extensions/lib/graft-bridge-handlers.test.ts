/**
 * Handler-level tests for graft-bridge.ts's `export default function (pi)` registrations.
 *
 * No other extension's test file in this directory constructs a fake ExtensionAPI/ctx and
 * exercises registered `pi.on(...)` handlers directly (confirmed by grepping
 * agent/harnesses/pi/extensions/lib/*.test.ts for `pi.on`/`ExtensionAPI`/fake-api patterns before
 * writing this file — no hits); `plan-mode.test.ts`/`graft-bridge.test.ts`/
 * `status-line.test.ts` only test pure functions exported alongside each default export. This
 * file designs a minimal harness for that purpose, in the absence of any existing precedent:
 *   - a fake ExtensionAPI (`createFakePi`) that records registered handlers by event name and
 *     any `pi.sendMessage(...)` calls made through it;
 *   - a fake ExtensionContext (`fakeCtx`) exposing just the fields graft-bridge.ts's handlers
 *     actually read (`hasUI`, `ui.notify`);
 *   - `./lib/graft-executor-bridge`'s `callGraftTool` mocked via Bun's `mock.module` (bun:test)
 *     so no real `executor`/`graft` process is ever spawned by these tests.
 *
 * IMPORTANT: `mock.module` must run before `../graft-bridge` (or anything importing it) is
 * loaded — ES module imports are hoisted and fully resolved before any of a file's own top-level
 * statements execute. This file therefore has NO static `import ... from "../graft-bridge"`
 * anywhere; it is loaded via a dynamic `await import(...)` after the mock is registered.
 * `getGraftBridgeStats`/`resetGraftBridgeStats` are destructured from that same dynamic import —
 * they now live as local module state in graft-bridge.ts itself (not a separate lib/graft-stats.ts
 * module; see graft-bridge.ts's header for why cross-extension-file module state was dropped), so
 * they must go through the same deferred, post-mock import as the default export.
 * `mock.restore()` at the end undoes the module-level mock so it cannot leak into any other
 * *.test.ts file loaded later in the same `bun test` process (mock.module's effect is
 * process-global, not scoped to this file, per Bun's own mock.module semantics).
 */
import { mock } from "bun:test";

let pass = 0;
let fail = 0;
function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

let nextGraftToolResult: string | null = "stub graft context";
const graftToolCalls: Array<{ toolName: string; args: Record<string, unknown> }> = [];

mock.module("./graft-executor-bridge", () => ({
  callGraftTool: async (toolName: string, args: Record<string, unknown>) => {
    graftToolCalls.push({ toolName, args });
    return nextGraftToolResult;
  },
}));

const { default: graftBridge, getGraftBridgeStats, resetGraftBridgeStats } = await import("../graft-bridge");

type Handler = (event: any, ctx: any) => any;

function createFakePi() {
  const handlers = new Map<string, Handler[]>();
  const sentMessages: Array<{ message: any; options?: any }> = [];
  const pi: any = {
    on(event: string, handler: Handler) {
      const arr = handlers.get(event) ?? [];
      arr.push(handler);
      handlers.set(event, arr);
    },
    sendMessage(message: any, options?: any) {
      sentMessages.push({ message, options });
    },
  };
  return { pi, handlers, sentMessages };
}

function fakeCtx(overrides: Record<string, unknown> = {}) {
  const notified: Array<{ text: string; kind: string }> = [];
  return {
    hasUI: true,
    cwd: "/tmp",
    ui: {
      notify(text: string, kind: string) {
        notified.push({ text, kind });
      },
    },
    ...overrides,
    __notified: notified,
  } as any;
}

async function withCase(fn: () => Promise<void>) {
  graftToolCalls.length = 0;
  nextGraftToolResult = "stub graft context";
  resetGraftBridgeStats();
  await fn();
}

async function main() {
  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("before_agent_start")![0];
    const result = await handler(
      { type: "before_agent_start", prompt: "  where is the parser?  ", images: undefined, systemPrompt: "", systemPromptOptions: {} },
      fakeCtx(),
    );
    check(
      "before_agent_start calls graft_find_code with the trimmed prompt as query",
      graftToolCalls[0]?.toolName === "graft_find_code" && graftToolCalls[0]?.args.query === "where is the parser?",
      JSON.stringify(graftToolCalls),
    );
    check(
      "before_agent_start returns a non-displayed graft-context message",
      result?.message?.customType === "graft-context" && result.message.content === "stub graft context" && result.message.display === false,
      JSON.stringify(result),
    );
  });

  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("before_agent_start")![0];
    const result = await handler(
      { type: "before_agent_start", prompt: "   ", images: undefined, systemPrompt: "", systemPromptOptions: {} },
      fakeCtx(),
    );
    check("before_agent_start is a no-op on an empty/whitespace-only prompt", graftToolCalls.length === 0 && result === undefined);
  });

  await withCase(async () => {
    nextGraftToolResult = null;
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("before_agent_start")![0];
    const result = await handler(
      { type: "before_agent_start", prompt: "hello", images: undefined, systemPrompt: "", systemPromptOptions: {} },
      fakeCtx(),
    );
    check("before_agent_start is a no-op when graft/executor is unavailable (null)", result === undefined);
  });

  // docs-comment-adversarial-reviewer HIGH finding: every other before_agent_start/event-consuming
  // file in this codebase (e.g. skill-state.ts: `typeof event?.systemPrompt === "string" ? ... :
  // ""`) accesses event fields defensively; this handler must not throw if `event.prompt` is ever
  // absent/not a string, regardless of BeforeAgentStartEvent's documented type.
  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("before_agent_start")![0];
    let threw = false;
    let result: unknown;
    try {
      result = await handler({ type: "before_agent_start", prompt: undefined as any, images: undefined, systemPrompt: "", systemPromptOptions: {} }, fakeCtx());
    } catch {
      threw = true;
    }
    check("before_agent_start does not throw when event.prompt is undefined", !threw);
    check("before_agent_start is a no-op when event.prompt is undefined", result === undefined && graftToolCalls.length === 0);
  });

  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("before_agent_start")![0];
    let threw = false;
    try {
      await handler({ type: "before_agent_start", prompt: 123 as any, images: undefined, systemPrompt: "", systemPromptOptions: {} }, fakeCtx());
    } catch {
      threw = true;
    }
    check("before_agent_start does not throw when event.prompt is not a string", !threw);
    check("before_agent_start is a no-op when event.prompt is not a string", graftToolCalls.length === 0);
  });

  // This is the regression test for the Checker-caught bug: session_start's ExtensionHandler
  // has no Result type (types.d.ts:923, `ExtensionHandler<SessionStartEvent>` with no second type
  // argument) and ExtensionRunner.emit() only keeps a handler's return value when
  // `isSessionBeforeEvent(event)` is true (runner.js) — session_start is not in that set, so any
  // `{message: ...}` this handler returns is silently discarded at runtime. The fix must use
  // `pi.sendMessage(...)` (the verified API for this — types.d.ts:971, part of ExtensionAPI, NOT
  // ExtensionContext) instead of a return value.
  await withCase(async () => {
    const { pi, handlers, sentMessages } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("session_start")![0];
    const result = await handler({ type: "session_start", reason: "new" }, fakeCtx());
    check("session_start calls graft_repo_map", graftToolCalls[0]?.toolName === "graft_repo_map", JSON.stringify(graftToolCalls));
    check(
      "session_start's return value is not relied upon (it would be silently discarded)",
      result === undefined,
      `got: ${JSON.stringify(result)}`,
    );
    check(
      "session_start delivers the repo-map context via pi.sendMessage, not a return value",
      sentMessages[0]?.message?.customType === "graft-repo-map-context" &&
        sentMessages[0].message.content === "stub graft context" &&
        sentMessages[0].message.display === false,
      JSON.stringify(sentMessages),
    );
  });

  await withCase(async () => {
    nextGraftToolResult = null;
    const { pi, handlers, sentMessages } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("session_start")![0];
    await handler({ type: "session_start", reason: "new" }, fakeCtx());
    check("session_start sends nothing when graft/executor is unavailable (null)", sentMessages.length === 0);
  });

  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    const handler = handlers.get("tool_result")![0];
    await handler({ type: "tool_result", toolName: "read", isError: false }, fakeCtx());
    await handler({ type: "tool_result", toolName: "grep", isError: false }, fakeCtx());
    await handler({ type: "tool_result", toolName: "find", isError: true }, fakeCtx()); // errored -> not counted
    await handler({ type: "tool_result", toolName: "bash", isError: false }, fakeCtx()); // not a search tool
    await handler({ type: "tool_result", toolName: "ls", isError: false }, fakeCtx());
    const stats = getGraftBridgeStats();
    check("tool_result counts only successful read/grep/find/ls calls", stats.rawSearchToolCalls === 3, `got ${stats.rawSearchToolCalls}`);
  });

  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    await handlers.get("before_agent_start")![0](
      { type: "before_agent_start", prompt: "x", images: undefined, systemPrompt: "", systemPromptOptions: {} },
      fakeCtx(),
    );
    const ctx = fakeCtx();
    await handlers.get("session_shutdown")![0]({ type: "session_shutdown", reason: "quit" }, ctx);
    check("session_shutdown notifies a summary when there was graft-bridge activity", ctx.__notified.length === 1, JSON.stringify(ctx.__notified));
  });

  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    const ctx = fakeCtx();
    await handlers.get("session_shutdown")![0]({ type: "session_shutdown", reason: "quit" }, ctx);
    check("session_shutdown stays silent when there was no activity", ctx.__notified.length === 0);
  });

  await withCase(async () => {
    const { pi, handlers } = createFakePi();
    graftBridge(pi);
    await handlers.get("before_agent_start")![0](
      { type: "before_agent_start", prompt: "x", images: undefined, systemPrompt: "", systemPromptOptions: {} },
      fakeCtx(),
    );
    const ctx = fakeCtx({ hasUI: false });
    await handlers.get("session_shutdown")![0]({ type: "session_shutdown", reason: "quit" }, ctx);
    check("session_shutdown stays silent without UI even with activity", ctx.__notified.length === 0);
  });

  mock.restore();

  console.log(`\ngraft-bridge-handlers: ${pass} passed, ${fail} failed`);
  if (fail > 0) process.exit(1);
}

await main();
