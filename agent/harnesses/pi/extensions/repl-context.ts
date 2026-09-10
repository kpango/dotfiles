/**
 * RLM Context Filtering Extension for Pi Coding Agent
 *
 * Eliminates Context Rot by intercepting massive command/tool outputs (>100KB),
 * storing them in-memory, and providing surgical slice, grep, head, and tail
 * querying capabilities via the `repl_filter` tool and `/repl-context` command.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  globalReplStore,
  REPL_THRESHOLD_BYTES,
  type ReplQueryResult,
} from "./lib/repl-context-core";

export default function (pi: ExtensionAPI) {
  // --------------------------------------------------------------------------
  // Hook: tool_result
  // Intercept outputs > 100KB to protect LLM context window
  // --------------------------------------------------------------------------
  pi.on("tool_result", async (event: any, _ctx: any) => {
    if (!event) return;
    const toolName = event.toolName || event.tool || "tool";

    // 1. Direct string result
    if (typeof event.result === "string") {
      const res = globalReplStore.store(event.result, toolName);
      if (res.intercepted && res.summary) {
        event.result = res.summary;
      }
    } else if (event.result && typeof event.result === "object") {
      // 2. Structured content inside event.result
      if (Array.isArray(event.result.content)) {
        for (const item of event.result.content) {
          if (item && item.type === "text" && typeof item.text === "string") {
            const res = globalReplStore.store(item.text, toolName);
            if (res.intercepted && res.summary) {
              item.text = res.summary;
            }
          }
        }
      }
      if (typeof event.result.text === "string") {
        const res = globalReplStore.store(event.result.text, toolName);
        if (res.intercepted && res.summary) {
          event.result.text = res.summary;
        }
      }
    }

    // 3. Top-level event.content array
    if (Array.isArray(event.content)) {
      for (const item of event.content) {
        if (item && item.type === "text" && typeof item.text === "string") {
          const res = globalReplStore.store(item.text, toolName);
          if (res.intercepted && res.summary) {
            item.text = res.summary;
          }
        }
      }
    }
  });

  // --------------------------------------------------------------------------
  // Tool: repl_filter
  // --------------------------------------------------------------------------
  const executeQuery = async (args: any) => {
    const qType = (args.queryType || "").toLowerCase();
    const id = args.bufferId;

    if (!id) {
      return {
        content: [
          {
            type: "text",
            text: "Error: Missing required parameter 'bufferId'",
          },
        ],
      };
    }

    // Slicing Mode
    if (qType === "slice" || (args.startLine !== undefined && !args.pattern)) {
      const res = globalReplStore.slice({
        bufferId: id,
        startLine: args.startLine,
        endLine: args.endLine,
      });
      if (res.error) {
        return { content: [{ type: "text", text: `Error: ${res.error}` }] };
      }
      return {
        content: [
          {
            type: "text",
            text: `Buffer: ${res.bufferId} (${res.matchedLines}/${res.totalLines} lines):\n${res.content}`,
          },
        ],
      };
    }

    // Filter / Grep Mode
    if (qType === "filter" || args.pattern) {
      const res = globalReplStore.filter({
        bufferId: id,
        pattern: args.pattern || "",
        isRegex: Boolean(args.isRegex),
        contextLines: args.contextLines,
      });
      if (res.error) {
        return { content: [{ type: "text", text: `Error: ${res.error}` }] };
      }
      return {
        content: [
          {
            type: "text",
            text: `Buffer: ${res.bufferId} (Found ${res.matchedLines} matching lines):\n${
              res.content || "[No matching lines found]"
            }`,
          },
        ],
      };
    }

    // Head Mode
    if (qType === "head") {
      const res = globalReplStore.head(id, args.count || 20);
      if (res.error) {
        return { content: [{ type: "text", text: `Error: ${res.error}` }] };
      }
      return {
        content: [
          {
            type: "text",
            text: `Buffer: ${res.bufferId} (Head ${res.matchedLines} lines):\n${res.content}`,
          },
        ],
      };
    }

    // Tail Mode
    if (qType === "tail") {
      const res = globalReplStore.tail(id, args.count || 20);
      if (res.error) {
        return { content: [{ type: "text", text: `Error: ${res.error}` }] };
      }
      return {
        content: [
          {
            type: "text",
            text: `Buffer: ${res.bufferId} (Tail ${res.matchedLines} lines):\n${res.content}`,
          },
        ],
      };
    }

    // Summary Mode
    if (qType === "summary") {
      const sum = globalReplStore.summarize(id);
      if (!sum) {
        return { content: [{ type: "text", text: `Error: Buffer '${id}' not found` }] };
      }
      return {
        content: [
          {
            type: "text",
            text: [
              `Buffer Summary: ${sum.handle}`,
              `Source Tool: ${sum.sourceTool}`,
              `Size: ${sum.byteLength.toLocaleString()} bytes (${(sum.byteLength / 1024).toFixed(1)} KB)`,
              `Lines: ${sum.lineCount}`,
              `Created: ${new Date(sum.createdAt).toISOString()}`,
              `Preview:`,
              sum.preview,
            ].join("\n"),
          },
        ],
      };
    }

    // Default inspection
    const sum = globalReplStore.summarize(id);
    if (!sum) {
      return {
        content: [{ type: "text", text: `Error: Buffer '${id}' not found or expired` }],
      };
    }
    return {
      content: [
        {
          type: "text",
          text: `Buffer ${sum.handle}: ${sum.lineCount} lines, ${(sum.byteLength / 1024).toFixed(1)} KB. Specify queryType: 'slice' or 'filter' to extract data.`,
        },
      ],
    };
  };

  pi.registerTool({
    name: "repl_filter",
    label: "RLM REPL Buffer Filter",
    description:
      "Query, slice, or grep large intercepted tool outputs stored in memory without loading the full payload into the prompt context.",
    parameters: Type.Object({
      bufferId: Type.String({
        description: "Buffer handle or ID (e.g. '#repl_buf_abc123' or 'repl_buf_abc123')",
      }),
      queryType: Type.Optional(
        Type.String({
          description: "Query mode: 'slice', 'filter', 'head', 'tail', or 'summary'",
        })
      ),
      pattern: Type.Optional(
        Type.String({
          description: "Search pattern or substring (used for 'filter' mode)",
        })
      ),
      startLine: Type.Optional(
        Type.Integer({
          description: "1-indexed starting line number (used for 'slice' mode)",
        })
      ),
      endLine: Type.Optional(
        Type.Integer({
          description: "1-indexed ending line number (used for 'slice' mode)",
        })
      ),
      isRegex: Type.Optional(
        Type.Boolean({
          description: "Whether the pattern should be evaluated as a regular expression",
        })
      ),
      contextLines: Type.Optional(
        Type.Integer({
          description: "Number of surrounding context lines to include in filter matches",
        })
      ),
      count: Type.Optional(
        Type.Integer({
          description: "Number of lines to return for head/tail queries (default 20)",
        })
      ),
    }),
    handler: async (args: any, _ctx: any) => {
      return executeQuery(args);
    },
    execute: async (_toolCallId: string, params: any, _signal: any, _onUpdate: any, _ctx: any) => {
      return executeQuery(params);
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /repl-context
  // --------------------------------------------------------------------------
  pi.registerCommand("repl-context", {
    description: "Manage in-memory RLM REPL buffers (/repl-context [list | inspect <id> | clear])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const subcmd = parts[0]?.toLowerCase() || "list";

      if (subcmd === "list") {
        const buffers = globalReplStore.list();
        if (buffers.length === 0) {
          ctx.ui.notify("No active RLM REPL buffers in memory.", "info");
          return;
        }
        let out = `Active RLM REPL Buffers (${buffers.length} total, ${(
          globalReplStore.getTotalBytes() / 1024
        ).toFixed(1)} KB):\n\n`;
        for (const b of buffers) {
          out += `• ${b.handle} [${b.sourceTool}] - ${(b.byteLength / 1024).toFixed(1)} KB, ${
            b.lineCount
          } lines\n`;
        }
        ctx.ui.notify(out.trim(), "info");
        return;
      }

      if (subcmd === "inspect") {
        const targetId = parts[1];
        if (!targetId) {
          ctx.ui.notify("Usage: /repl-context inspect <bufferId>", "warning");
          return;
        }
        const sum = globalReplStore.summarize(targetId);
        if (!sum) {
          ctx.ui.notify(`Buffer '${targetId}' not found.`, "warning");
          return;
        }
        const text = [
          `Buffer Details: ${sum.handle}`,
          `• Source Tool: ${sum.sourceTool}`,
          `• Size: ${(sum.byteLength / 1024).toFixed(2)} KB (${sum.byteLength.toLocaleString()} bytes)`,
          `• Lines: ${sum.lineCount}`,
          `• Created: ${new Date(sum.createdAt).toLocaleTimeString()}`,
          `• Last Accessed: ${new Date(sum.lastAccessedAt).toLocaleTimeString()}`,
          `--- Preview ---`,
          sum.preview,
        ].join("\n");
        ctx.ui.notify(text, "info");
        return;
      }

      if (subcmd === "clear") {
        const count = globalReplStore.getBufferCount();
        globalReplStore.clear();
        ctx.ui.notify(`Cleared ${count} RLM REPL buffer(s) from memory.`, "info");
        return;
      }

      ctx.ui.notify("Usage: /repl-context [list | inspect <id> | clear]", "warning");
    },
  });
}
