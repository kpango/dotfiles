/**
 * Idempotent Tool Journal Extension for Pi Coding Agent
 *
 * Intercepts tool executions, computes deterministic SHA-256 idempotency keys,
 * prevents unintended duplicate tool side-effects across retries, and persists
 * full execution history to append-only JSONL journals.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import * as os from "node:os";
import * as path from "node:path";
import {
  SessionJournal,
  computeIdempotencyKey,
} from "./lib/session-journal-core";

export default function (pi: ExtensionAPI) {
  const journals = new Map<string, SessionJournal>();

  // Read-only tools whose results depend on mutable filesystem state should
  // only replay recent results; otherwise a repeated read after an edit could
  // silently return a stale snapshot from the journal.
  const READ_TOOL_REPLAY_TTL_MS = 30_000;
  const READ_ONLY_TOOLS = new Set([
    "read",
    "grep",
    "find",
    "ls",
    "lsp_diagnostics",
    "lsp_definition",
    "lsp_symbols",
    "graphify_query",
    "graphify_explain",
  ]);

  function getSessionId(ctx: any): string {
    return ctx?.sessionManager?.getSessionId?.() || ctx?.sessionId || "default";
  }

  function getJournal(ctx: any): SessionJournal {
    const sessionId = getSessionId(ctx);
    let journal = journals.get(sessionId);
    if (!journal) {
      const home = os.homedir();
      const journalDir = path.join(home, ".pi", "agent", "journals");
      const journalFile = path.join(journalDir, `${sessionId}.jsonl`);
      journal = new SessionJournal(journalFile);
      journals.set(sessionId, journal);
    }
    return journal;
  }

  // Intercept tool calls: check for existing completed execution to replay
  pi.on("tool_call", async (event, ctx) => {
    const toolName = event.toolName;
    const params = event.input || (event as any).params;
    const cwd = ctx?.cwd || process.cwd();
    const key = computeIdempotencyKey(toolName, params, cwd);

    const journal = getJournal(ctx);
    const ttl = READ_ONLY_TOOLS.has(toolName) ? READ_TOOL_REPLAY_TTL_MS : undefined;
    const replay = journal.checkReplay(key, ttl);

    if (replay.replayed) {
      const ttlNote = ttl ? ` (read TTL ${ttl / 1000}s)` : "";
      ctx.ui?.notify(
        `[Idempotent Journal] Replaying cached result for '${toolName}' (${key.slice(0, 8)})${ttlNote}`,
        "info"
      );
      return {
        block: true,
        result: replay.result,
        replayed: true,
        reason: `Tool execution skipped: cached result replayed from journal (key: ${key.slice(0, 8)})`,
      };
    }

    journal.recordStart({
      toolName,
      params,
      cwd,
      idempotencyKey: key,
      sessionId: getSessionId(ctx),
    });
  });

  // Record tool result on completion or failure
  pi.on("tool_result", async (event, ctx) => {
    const toolName = event.toolName;
    const params = event.input || (event as any).params;
    const cwd = ctx?.cwd || process.cwd();
    const key = computeIdempotencyKey(toolName, params, cwd);

    const journal = getJournal(ctx);
    const isError = Boolean((event as any).isError || (event as any).error);

    if (isError) {
      const errorMsg = String(
        (event as any).error || (event as any).result || "Tool execution failed"
      );
      journal.recordFailure(key, errorMsg, (event as any).exitCode ?? 1);
    } else {
      const result = (event as any).result ?? (event as any).output ?? event;
      journal.recordCompletion(key, result, (event as any).exitCode ?? 0);
    }
  });

  // Slash command: /journal
  pi.registerCommand("journal", {
    description: "Inspect or clear idempotent tool execution journal (/journal [status|clear])",
    handler: async (args, ctx) => {
      const action = (args || "").trim().toLowerCase();
      const journal = getJournal(ctx);

      if (action === "clear") {
        journal.clear();
        ctx.ui?.notify("Session tool journal cleared.", "info");
        return;
      }

      const status = journal.getStatus();
      const lines = [
        `Idempotent Tool Journal Status:`,
        `• Journal File: ${journal.getFilePath()}`,
        `• Total Entries: ${status.totalEntries}`,
        `• Unique Tool Invocations: ${status.uniqueKeys}`,
        `• Completed: ${status.completed}`,
        `• Pending / In-Flight: ${status.pending}`,
        `• Failed: ${status.failed}`,
      ];

      ctx.ui?.notify(lines.join("\n"), "info");
    },
  });
}
