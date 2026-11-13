/**
 * DeepSeekHarness-Style Reasoning Token Preservation Extension for Pi Coding Agent
 *
 * Preserves model reasoning/thinking tokens (<think> blocks) across multi-turn tool loops,
 * preventing reasoning amnesia, managing token budget via <think-summary> compaction,
 * and halting circular overthinking loops.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  ReasoningPreserverRingBuffer,
  extractThinkingBlocks,
  LOOP_BREAKER_DIRECTIVE,
  DEFAULT_REASONING_CONFIG,
} from "./lib/reasoning-preserver-core";

export default function (pi: ExtensionAPI) {
  const preserver = new ReasoningPreserverRingBuffer(DEFAULT_REASONING_CONFIG);
  let currentTurnHadToolCall = false;

  // Track turn start
  pi.on("turn_start", async (_event, _ctx) => {
    currentTurnHadToolCall = false;
  });

  // Track tool invocations during this turn
  pi.on("tool_call", async (_event, _ctx) => {
    currentTurnHadToolCall = true;
    preserver.markToolCallOnCurrentTurn();
  });

  // Track turn end: extract reasoning tokens from assistant message
  pi.on("turn_end", async (event, _ctx) => {
    const message = (event as any)?.message;
    let contentText = "";

    if (typeof message === "string") {
      contentText = message;
    } else if (message && typeof message.content === "string") {
      contentText = message.content;
    } else if (message && Array.isArray(message.content)) {
      for (const part of message.content) {
        if (typeof part === "string") {
          contentText += part + "\n";
        } else if (part && typeof part.text === "string") {
          contentText += part.text + "\n";
        } else if (part && typeof (part as any).thinking === "string") {
          contentText += `<think>${(part as any).thinking}</think>\n`;
        }
      }
    }

    if (contentText) {
      preserver.recordTurn(contentText, currentTurnHadToolCall);
    }
  });

  // Inject preserved reasoning context before next model generation
  pi.on("before_agent_start", async () => {
    if (!preserver.hasPreservedContext()) {
      return;
    }

    const contextContent = preserver.formatContextForPrompt();
    if (!contextContent) {
      return;
    }

    return {
      message: {
        customType: "preserved-reasoning-context",
        content: contextContent,
        display: false,
      },
    };
  });

  // Slash command: /reasoning
  pi.registerCommand("reasoning", {
    description: "Inspect or manage preserved reasoning token context (/reasoning [status|clear])",
    handler: async (args, ctx) => {
      const action = (args || "").trim().toLowerCase();

      if (action === "clear") {
        preserver.clear();
        ctx.ui?.notify("Preserved reasoning context cleared.", "info");
        return;
      }

      const turns = preserver.getTurns();
      const totalTokens = preserver.getTotalTokens();
      const isLoop = preserver.isLoopActive();

      const lines = [
        `Preserved Reasoning Context:`,
        `• Tracked Turns: ${turns.length}`,
        `• Total Estimated Tokens: ${totalTokens}`,
        `• Overthinking Loop Detected: ${isLoop ? "YES (Loop Breaker Active)" : "No"}`,
      ];

      if (turns.length > 0) {
        lines.push(`\nRecent Turns:`);
        turns.slice(-3).forEach((t, i) => {
          const preview = t.preservedText.slice(0, 80).replace(/\n/g, " ");
          lines.push(`  [${i + 1}] (${t.tokenEstimate} tok, ${t.isCompressed ? "compressed" : "full"}): ${preview}...`);
        });
      }

      ctx.ui?.notify(lines.join("\n"), isLoop ? "warning" : "info");
    },
  });
}
