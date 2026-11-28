/**
 * LCM Lossless Context Management & Subtask Stack Machine Extension (Pi 1.7.0)
 *
 * Implements arXiv:2605.04050 (Immutable Append-Only Store + Escalating Convergence)
 * and arXiv:2611.12122 (Subtask Stack Machine).
 *
 * Harness Tax & Prefix Cache safety:
 * - Zero direct tools (`subtask_frame` & `lcm_recall` declare `exposure: "deferred"`).
 * - Zero `before_agent_start` / `systemPrompt` mutations.
 * - `context` hook only mutates messages once finalized subtask frames have been popped.
 */

import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  ImmutableLcmStore,
  SubtaskStackMachine,
  utf8SafeTruncate,
} from "./lib/lcm-core";

export * from "./lib/lcm-core";

export default function (pi: ExtensionAPI) {
  const sessionId = `pi-${process.pid}-${Date.now().toString(36)}`;
  const store = new ImmutableLcmStore(sessionId, path.join(os.homedir(), ".pi", "agent", "lcm"));
  const stack = new SubtaskStackMachine(store);
  let lastMessageCount = 0;

  pi.on("session_start", async () => {
    stack.reset();
    lastMessageCount = 0;
  });

  pi.on("context", async (event) => {
    if (!event || !Array.isArray(event.messages)) return;
    lastMessageCount = event.messages.length;
    if (stack.getCollapsedSpans().length === 0) return;

    const collapsed = stack.applyCollapsedSpans(event.messages, (span) => ({
      role: "user",
      content: [{ type: "text", text: span.collapsedText }],
      timestamp: Date.now(),
    }) as any);

    if (collapsed !== event.messages) {
      return { messages: collapsed };
    }
  });

  pi.on("session_before_compact", async (event: any) => {
    if (!event?.preparation) return;
    try {
      const payload = JSON.stringify(
        {
          reason: event.reason,
          customInstructions: event.customInstructions,
          preparation: event.preparation,
        },
        null,
        2,
      );
      store.append(`pre-compact:${event.reason || "manual"}`, payload);
    } catch {
      // Never block Pi's native compaction on archival failures.
    }
  });

  pi.registerTool({
    name: "subtask_frame",
    exposure: "deferred",
    label: "Subtask Stack Frame",
    description:
      "Push or pop a Subtask Stack Machine frame so completed exploratory subtasks collapse to an immutable LCM pointer summary.",
    parameters: Type.Object({
      action: Type.Union([Type.Literal("push"), Type.Literal("pop"), Type.Literal("status")]),
      name: Type.Optional(Type.String({ description: "Subtask name (for push)" })),
      summary: Type.Optional(Type.String({ description: "Concise verified result summary (for pop)" })),
      rawTranscript: Type.Optional(Type.String({ description: "Optional full notes archived into ImmutableLcmStore" })),
    }),
    async execute(_toolCallId, params) {
      if (params.action === "push") {
        const frame = stack.push(params.name || "subtask", lastMessageCount);
        return {
          content: [{ type: "text", text: `Pushed subtask '${frame.name}' (${frame.id}) at message index ${frame.startIndex}.` }],
        };
      }
      if (params.action === "pop") {
        const span = stack.pop(lastMessageCount, params.summary || "(completed)", params.rawTranscript);
        if (!span) {
          return { content: [{ type: "text", text: "No active subtask frame to pop." }], isError: true };
        }
        return {
          content: [
            {
              type: "text",
              text: `Popped subtask '${span.name}' [${span.startIndex}..${span.endIndex}] -> pointer ${span.pointerId}.`,
            },
          ],
        };
      }
      const active = stack.getActiveFrames();
      const collapsed = stack.getCollapsedSpans();
      return {
        content: [
          {
            type: "text",
            text: `Subtask stack: active=${active.length} (${active.map((f) => f.name).join(", ") || "none"}), collapsed=${collapsed.length}`,
          },
        ],
      };
    },
  });

  pi.registerTool({
    name: "lcm_recall",
    exposure: "deferred",
    label: "LCM Lossless Recall",
    description: "Retrieve or search verbatim records archived in ImmutableLcmStore by `lcm-<hex>` pointer ID or query.",
    parameters: Type.Object({
      id: Type.Optional(Type.String({ description: "Pointer ID like lcm-a1b2c3d4e5" })),
      query: Type.Optional(Type.String({ description: "Case-insensitive literal search query" })),
      maxBytes: Type.Optional(Type.Integer({ description: "Maximum UTF-8 bytes returned (default 8192)", minimum: 256 })),
    }),
    async execute(_toolCallId, params) {
      const cap = params.maxBytes ?? 8192;
      if (params.id) {
        const rec = store.getById(params.id);
        if (!rec) {
          return { content: [{ type: "text", text: `LCM record not found: ${params.id}` }], isError: true };
        }
        return {
          content: [
            {
              type: "text",
              text: `[${rec.id}] ${rec.label} (${rec.bytes}B)\n${utf8SafeTruncate(rec.content, cap)}`,
            },
          ],
        };
      }
      if (params.query) {
        const hits = store.search(params.query, 10);
        if (hits.length === 0) {
          return { content: [{ type: "text", text: `No LCM hits for '${params.query}'.` }] };
        }
        const out = hits.map((h) => `• ${h.id} [${h.label}] (${h.bytes}B): ${h.snippet}`).join("\n");
        return { content: [{ type: "text", text: out }] };
      }
      return { content: [{ type: "text", text: "Provide either 'id' or 'query'." }], isError: true };
    },
  });

  pi.registerCommand("subtask", {
    description: "Manage Subtask Stack Machine (/subtask [push <name>|pop <summary>|status])",
    handler: async (args, ctx) => {
      const raw = (args || "").trim();
      const [sub, ...rest] = raw.split(/\s+/);
      const payload = rest.join(" ");
      if (sub === "push") {
        const frame = stack.push(payload || "subtask", lastMessageCount);
        ctx.ui.notify(`Pushed '${frame.name}' (${frame.id}) at index ${frame.startIndex}`, "info");
        return;
      }
      if (sub === "pop") {
        const span = stack.pop(lastMessageCount, payload || "(completed)");
        ctx.ui.notify(
          span
            ? `Popped '${span.name}' [${span.startIndex}..${span.endIndex}] -> ${span.pointerId}`
            : "No active subtask frame to pop.",
          span ? "info" : "warning",
        );
        return;
      }
      ctx.ui.notify(
        `Subtask Stack: active=${stack.getActiveFrames().length}, collapsed=${stack.getCollapsedSpans().length}`,
        "info",
      );
    },
  });

  pi.registerCommand("lcm", {
    description: "Inspect or query ImmutableLcmStore (/lcm [status|recall <id>|search <query>])",
    handler: async (args, ctx) => {
      const raw = (args || "").trim();
      const [sub, ...rest] = raw.split(/\s+/);
      const q = rest.join(" ");
      if (sub === "recall" && q) {
        const rec = store.getById(q);
        ctx.ui.notify(
          rec ? `[${rec.id}] ${rec.label} (${rec.bytes}B)\n${utf8SafeTruncate(rec.content, 2000)}` : `Not found: ${q}`,
          rec ? "info" : "warning",
        );
        return;
      }
      if (sub === "search" && q) {
        const hits = store.search(q, 5);
        ctx.ui.notify(
          hits.length ? hits.map((h) => `${h.id} [${h.label}]: ${h.snippet}`).join("\n") : `No hits for '${q}'.`,
          "info",
        );
        return;
      }
      const all = store.readAll();
      ctx.ui.notify(`LCM Store (${store.storeFile}): ${all.length} archived record(s).`, "info");
    },
  });
}
