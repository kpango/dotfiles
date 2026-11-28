/**
 * LangChain Middleware Guardrails Extension for Pi 1.7.0 (pi-agent-improvement.pdf #6)
 *
 * Zero registered tools (zero Harness Tax) and zero systemPrompt mutations
 * (preserves Prefix KV-Cache). Runs only lightweight lifecycle hooks:
 * - Read-Guard (tool_call + tool_result): tracks read/created files; warns or blocks
 *   (when PI_READ_GUARD_STRICT=1) edits on unread existing files.
 * - Doom-Loop Detection (tool_result): flags >=5 edits to the same file without
 *   verification pass, or >=3 consecutive identical failing tool invocations.
 * - Turn-Budget Steering (turn_end): advises switching to verification near PI_TURN_BUDGET.
 * - /env-context & /loop-guard commands: on-demand local context & state inspection.
 */

import * as fs from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  LoopGuardTracker,
  buildLocalContextSummary,
  normalizeTargetPath,
} from "./lib/loop-guard-core";

export * from "./lib/loop-guard-core";

export default function (pi: ExtensionAPI) {
  const parsedBudget = Number.parseInt(process.env.PI_TURN_BUDGET || "40", 10);
  const tracker = new LoopGuardTracker({
    turnBudget: Number.isFinite(parsedBudget) ? parsedBudget : 40,
  });
  let turns = 0;

  pi.on("session_start", async () => {
    tracker.reset();
    turns = 0;
  });

  pi.on("tool_call", async (event, ctx) => {
    if (!event) return;
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    const rawPath = (event.input as { path?: unknown } | undefined)?.path;
    if (typeof rawPath !== "string" || !rawPath) return;

    const abs = normalizeTargetPath(rawPath, ctx.cwd || process.cwd());
    if (!abs) return;

    if (event.toolName === "write" && !fs.existsSync(abs)) {
      tracker.recordCreated(abs);
      return;
    }

    const blindWarning = tracker.checkBlindEdit(abs, fs.existsSync(abs));
    if (blindWarning && process.env.PI_READ_GUARD_STRICT === "1") {
      return { block: true, reason: blindWarning };
    }
  });

  pi.on("tool_result", async (event, ctx) => {
    if (!event) return;
    const cwd = ctx?.cwd || process.cwd();
    const input = (event.input || {}) as { path?: unknown; command?: unknown };
    const rawPath = typeof input.path === "string" ? input.path : "";
    const abs = rawPath ? normalizeTargetPath(rawPath, cwd) : "";
    const cmd = typeof input.command === "string" ? input.command : undefined;

    const advisories: string[] = [];

    if (!event.isError && event.toolName === "read" && abs) {
      tracker.recordRead(abs);
    }

    if (!event.isError && (event.toolName === "edit" || event.toolName === "write") && abs) {
      const blindNote = tracker.checkBlindEdit(abs, fs.existsSync(abs));
      if (blindNote) {
        advisories.push(blindNote);
        tracker.recordRead(abs); // warn at most once per file
      }
      const loopNote = tracker.recordEdit(abs);
      if (loopNote) advisories.push(loopNote);
    }

    const failNote = tracker.recordToolOutcome(
      { toolName: event.toolName, path: abs || undefined, command: cmd },
      Boolean(event.isError),
    );
    if (failNote) advisories.push(failNote);

    if (advisories.length === 0) return;
    return {
      content: [...event.content, { type: "text" as const, text: `\n${advisories.join("\n")}` }],
    };
  });

  pi.on("turn_end", async (_event, ctx) => {
    turns++;
    const note = tracker.checkTurnBudget(turns);
    if (note) {
      ctx?.ui?.notify?.(note, "warning");
    }
  });

  pi.registerCommand("env-context", {
    description: "Inspect workspace git branch, dirty count, and installed toolchains",
    handler: async (_args, ctx) => {
      ctx.ui.notify(buildLocalContextSummary(ctx.cwd || process.cwd()), "info");
    },
  });

  pi.registerCommand("loop-guard", {
    description: "Show loop-guard Read-Guard, Doom-Loop, and Turn-Budget state",
    handler: async (_args, ctx) => {
      const snap = tracker.snapshot();
      ctx.ui.notify(
        `Loop Guard (turns=${turns}/${tracker.turnBudget}): read=${snap.readCount}, unverifiedEdits=${snap.hasUnverifiedEdits}, trackedFiles=${Object.keys(snap.editedFiles).length}`,
        "info",
      );
    },
  });
}
