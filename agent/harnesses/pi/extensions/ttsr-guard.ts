/**
 * Self-hosted TTSR (Time-to-Stop-and-Remind) Guardrail Extension for Pi 1.7.0
 *
 * Reads `*-ttsr.md` rules from `~/.pi/agent/rules/` and `.pi/rules/` and injects
 * guardrail reminders when tool inputs or stream outputs match forbidden patterns.
 */

import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  createTtsrState,
  defaultTtsrRuleDirs,
  evaluateTtsrText,
  evaluateTtsrToolCall,
  loadTtsrRules,
} from "./lib/ttsr-core";

export * from "./lib/ttsr-core";

function extractWriteContent(input: Record<string, unknown> | undefined): string {
  if (!input) return "";
  const parts: string[] = [];
  for (const k of ["content", "newText", "new_string"]) {
    if (typeof input[k] === "string") parts.push(input[k] as string);
  }
  if (Array.isArray(input.edits)) {
    for (const op of input.edits) {
      if (op && typeof op === "object" && typeof (op as { content?: unknown }).content === "string") {
        parts.push((op as { content: string }).content);
      }
    }
  }
  return parts.join("\n");
}

export default function (pi: ExtensionAPI) {
  const state = createTtsrState();
  let turnIndex = 0;

  pi.on("turn_start", async () => {
    turnIndex++;
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "edit" && event.toolName !== "write") return;
    const input = event.input as Record<string, unknown> | undefined;
    const rawPath = typeof input?.path === "string" ? input.path : typeof input?.file_path === "string" ? input.file_path : "";
    if (!rawPath) return;

    const absPath = path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.cwd, rawPath);
    const content = extractWriteContent(input);
    const rules = loadTtsrRules(defaultTtsrRuleDirs(ctx.cwd));
    const hit = evaluateTtsrToolCall(rules, event.toolName, absPath, content, state, turnIndex);
    if (!hit) return;

    return {
      block: true,
      reason: `[TTSR:${hit.matched.name}] Matched ${hit.pattern}\n\n${hit.matched.body}`,
    };
  });

  pi.on("message_end", async (event, ctx) => {
    const msg = event.message as { role?: string; content?: Array<{ type?: string; text?: string }> } | undefined;
    if (msg?.role !== "assistant" || !Array.isArray(msg.content)) return;
    const text = msg.content.filter((c) => c.type === "text" && typeof c.text === "string").map((c) => c.text!).join("\n");
    const rules = loadTtsrRules(defaultTtsrRuleDirs(ctx.cwd));
    const hit = evaluateTtsrText(rules, text, state, turnIndex);
    if (!hit) return;

    pi.sendMessage({
      customType: "ttsr-reminder",
      content: `[TTSR:${hit.matched.name}]\n${hit.matched.body}`,
      display: true,
    });
  });
}
