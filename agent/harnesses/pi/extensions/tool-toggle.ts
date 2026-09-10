/**
 * Dynamic Tool Toggle & Read-Only Mode Extension for Pi Coding Agent
 *
 * Allows interactive enabling and disabling of tools during a session:
 * - /tools [tool] [on|off]: Toggle specific tools (e.g. bash, write, edit).
 * - /readonly [on|off]: Shortcut to disable write & edit tools for safe exploration.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const disabledTools = new Set<string>();

export function isToolEnabled(disabledSet: Set<string>, toolName: string): boolean {
  return !disabledSet.has(toolName.toLowerCase());
}

export function setToolState(disabledSet: Set<string>, toolName: string, enable: boolean): void {
  const norm = toolName.toLowerCase();
  if (enable) {
    disabledSet.delete(norm);
  } else {
    disabledSet.add(norm);
  }
}

export function setReadOnlyMode(disabledSet: Set<string>, readOnly: boolean): void {
  const mutationTools = ["write", "edit"];
  for (const t of mutationTools) {
    setToolState(disabledSet, t, !readOnly);
  }
}

export default function (pi: ExtensionAPI) {
  // Hook: intercept tool execution
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolEnabled(disabledTools, event.toolName)) {
      const msg = `🚫 Tool '${event.toolName}' is currently disabled in this session. Run \`/tools ${event.toolName} on\` to re-enable.`;
      ctx.ui.notify(msg, "warning");
      throw new Error(msg);
    }
  });

  // Command: /tools
  pi.registerCommand("tools", {
    description: "Manage tool availability (/tools [toolName] [on|off])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const toolName = parts[0]?.toLowerCase();
      const state = parts[1]?.toLowerCase();

      if (!toolName) {
        const disabledList = Array.from(disabledTools);
        const status = disabledList.length > 0 ? `Disabled tools: ${disabledList.join(", ")}` : "All tools are active.";
        ctx.ui.notify(`Tool Status:\n${status}\n\nUsage: /tools <toolName> <on|off>`, "info");
        return;
      }

      if (state === "off") {
        setToolState(disabledTools, toolName, false);
        ctx.ui.notify(`Tool '${toolName}' disabled.`, "info");
      } else if (state === "on") {
        setToolState(disabledTools, toolName, true);
        ctx.ui.notify(`Tool '${toolName}' enabled.`, "info");
      } else {
        const currentlyEnabled = isToolEnabled(disabledTools, toolName);
        setToolState(disabledTools, toolName, !currentlyEnabled);
        ctx.ui.notify(`Tool '${toolName}' is now ${!currentlyEnabled ? "enabled" : "disabled"}.`, "info");
      }
    },
  });

  // Command: /readonly
  pi.registerCommand("readonly", {
    description: "Toggle read-only safety mode (/readonly [on|off])",
    handler: async (args, ctx) => {
      const state = (args || "").trim().toLowerCase();
      if (state === "off") {
        setReadOnlyMode(disabledTools, false);
        ctx.ui.notify("Read-only mode deactivated. Write & Edit tools enabled.", "info");
      } else {
        setReadOnlyMode(disabledTools, true);
        ctx.ui.notify("Read-only mode activated. Write & Edit tools disabled.", "info");
      }
    },
  });
}
