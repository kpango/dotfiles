/**
 * State-of-the-Art Plan Mode Extension for Pi Coding Agent
 *
 * Implements read-only exploration and planning, automatic step extraction,
 * interactive plan execution with real-time TUI progress widget, [DONE:n] markers,
 * and session branch state restoration.
 */

import type { AgentMessage } from "@earendil-works/pi-agent-core";
import type { AssistantMessage, TextContent } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Key } from "@earendil-works/pi-tui";

export interface TodoItem {
  step: number;
  text: string;
  completed: boolean;
}

interface PlanModeState {
  enabled: boolean;
  todos?: TodoItem[];
  executing?: boolean;
  toolsBeforePlanMode?: string[];
}

const PLAN_MODE_TOOLS = ["read", "bash", "grep", "find", "ls", "questionnaire"];
const NORMAL_MODE_TOOLS = ["read", "bash", "edit", "write", "subagent", "claude_code", "antigravity", "codex"];
const PLAN_MODE_DISABLED_TOOLS = new Set<string>(["edit", "write"]);
const PLAN_MANAGED_TOOLS = new Set<string>([...PLAN_MODE_TOOLS, ...NORMAL_MODE_TOOLS]);

// Safe read-only commands allowed in plan mode
const SAFE_COMMAND_PREFIXES = [
  "git status",
  "git diff",
  "git log",
  "git branch",
  "git show",
  "git rev-parse",
  "git ls-files",
  "cargo check",
  "cargo test --no-run",
  "go vet",
  "go list",
  "ls",
  "find",
  "grep",
  "rg",
  "cat",
  "head",
  "tail",
  "wc",
  "file",
  "which",
  "whereis",
  "env",
  "rtk",
  "graphify",
];

function isSafeCommand(cmd: string): boolean {
  const trimmed = cmd.trim();
  if (!trimmed) return true;
  // Deny dangerous operators
  if (/[;&|]/.test(trimmed) && !trimmed.startsWith("rtk ")) {
    const subcmds = trimmed.split(/[;&|]/).map((s) => s.trim()).filter(Boolean);
    return subcmds.every((sc) => isSafeCommand(sc));
  }
  return SAFE_COMMAND_PREFIXES.some((safe) => trimmed.startsWith(safe) || trimmed.startsWith(`rtk ${safe}`));
}

function extractTodoItems(text: string): TodoItem[] {
  const todos: TodoItem[] = [];
  const planMatch = text.match(/Plan:\s*\n((?:\s*\d+\.\s+[^\n]+\n?)+)/i);
  if (!planMatch) return todos;

  const lines = planMatch[1].split("\n");
  for (const line of lines) {
    const itemMatch = line.match(/^\s*(\d+)\.\s+(.+)$/);
    if (itemMatch) {
      todos.push({
        step: parseInt(itemMatch[1], 10),
        text: itemMatch[2].trim(),
        completed: false,
      });
    }
  }
  return todos;
}

function markCompletedSteps(text: string, todos: TodoItem[]): number {
  let marked = 0;
  const regex = /\[DONE:(\d+)\]/gi;
  let match: RegExpExecArray | null;

  while ((match = regex.exec(text)) !== null) {
    const stepNum = parseInt(match[1], 10);
    const todo = todos.find((t) => t.step === stepNum);
    if (todo && !todo.completed) {
      todo.completed = true;
      marked++;
    }
  }
  return marked;
}

function isAssistantMessage(m: AgentMessage): m is AssistantMessage {
  return m.role === "assistant" && Array.isArray(m.content);
}

function getTextContent(message: AssistantMessage): string {
  return message.content
    .filter((block): block is TextContent => block.type === "text")
    .map((block) => block.text)
    .join("\n");
}

export default function (pi: ExtensionAPI): void {
  let planModeEnabled = false;
  let executionMode = false;
  let todoItems: TodoItem[] = [];
  let toolsBeforePlanMode: string[] | undefined;

  pi.registerFlag("plan", {
    description: "Start in plan mode (read-only exploration)",
    type: "boolean",
    default: false,
  });

  function updateStatus(ctx: ExtensionContext): void {
    if (executionMode && todoItems.length > 0) {
      const completed = todoItems.filter((t) => t.completed).length;
      ctx.ui.setStatus("plan-mode", ctx.ui.theme.fg("accent", `📋 ${completed}/${todoItems.length}`));
    } else if (planModeEnabled) {
      ctx.ui.setStatus("plan-mode", ctx.ui.theme.fg("warning", "⏸ Plan Mode"));
    } else {
      ctx.ui.setStatus("plan-mode", undefined);
    }

    if (executionMode && todoItems.length > 0) {
      const lines = todoItems.map((item) => {
        if (item.completed) {
          return ctx.ui.theme.fg("success", "✓ ") + ctx.ui.theme.fg("muted", ctx.ui.theme.strikethrough(item.text));
        }
        return `${ctx.ui.theme.fg("dim", "☐ ")}${item.text}`;
      });
      ctx.ui.setWidget("plan-todos", lines);
    } else {
      ctx.ui.setWidget("plan-todos", undefined);
    }
  }

  function getPlanModeTools(activeToolNames: string[]): string[] {
    return Array.from(new Set([...activeToolNames.filter((name) => !PLAN_MODE_DISABLED_TOOLS.has(name)), ...PLAN_MODE_TOOLS]));
  }

  function getNormalModeTools(activeToolNames: string[]): string[] {
    return Array.from(new Set([...NORMAL_MODE_TOOLS, ...activeToolNames.filter((name) => !PLAN_MANAGED_TOOLS.has(name))]));
  }

  function enablePlanModeTools(): void {
    if (toolsBeforePlanMode === undefined) {
      toolsBeforePlanMode = pi.getActiveTools();
    }
    pi.setActiveTools(getPlanModeTools(toolsBeforePlanMode));
  }

  function restoreNormalModeTools(): void {
    pi.setActiveTools(toolsBeforePlanMode ?? getNormalModeTools(pi.getActiveTools()));
    toolsBeforePlanMode = undefined;
  }

  function persistState(): void {
    pi.appendEntry("plan-mode", {
      enabled: planModeEnabled,
      todos: todoItems,
      executing: executionMode,
      toolsBeforePlanMode,
    });
  }

  function togglePlanMode(ctx: ExtensionContext): void {
    planModeEnabled = !planModeEnabled;
    executionMode = false;
    todoItems = [];

    if (planModeEnabled) {
      enablePlanModeTools();
      ctx.ui.notify("Plan mode enabled: Write/edit tools disabled. Safe exploration active.", "info");
    } else {
      restoreNormalModeTools();
      ctx.ui.notify("Plan mode disabled: Full developer access restored.", "info");
    }
    updateStatus(ctx);
    persistState();
  }

  pi.registerCommand("plan", {
    description: "Toggle plan mode (read-only exploration and structured execution)",
    handler: async (_args, ctx) => togglePlanMode(ctx),
  });

  pi.registerCommand("todos", {
    description: "Show current plan todo checklist",
    handler: async (_args, ctx) => {
      if (todoItems.length === 0) {
        ctx.ui.notify("No active plan. Create a plan first with /plan", "info");
        return;
      }
      const list = todoItems.map((item, i) => `${i + 1}. ${item.completed ? "✓" : "○"} ${item.text}`).join("\n");
      ctx.ui.notify(`Plan Progress (${todoItems.filter((t) => t.completed).length}/${todoItems.length}):\n${list}`, "info");
    },
  });

  pi.registerShortcut(Key.ctrlAlt("p"), {
    description: "Toggle plan mode",
    handler: async (ctx) => togglePlanMode(ctx),
  });

  // Block destructive shell commands in plan mode
  pi.on("tool_call", async (event) => {
    if (!planModeEnabled || event.toolName !== "bash") return;

    const command = (event.input.command as string) || "";
    if (!isSafeCommand(command)) {
      return {
        block: true,
        reason: `Plan Mode: command blocked (read-only mode active). Run /plan to disable plan mode first.\nCommand: ${command}`,
      };
    }
  });

  // Inject plan/execution context before agent starts
  pi.on("before_agent_start", async () => {
    if (planModeEnabled) {
      return {
        message: {
          customType: "plan-mode-context",
          content: `[PLAN MODE ACTIVE]
You are currently in Plan Mode — a safe, read-only exploration mode.
- Direct write and edit tools are disabled.
- Bash is restricted to safe read-only commands.
- Ask clarifying questions using the questionnaire tool if needed.

Formulate a concise, numbered plan under a "Plan:" header:

Plan:
1. First step description
2. Second step description
...

Do NOT attempt to apply modifications directly until the plan is approved.`,
          display: false,
        },
      };
    }

    if (executionMode && todoItems.length > 0) {
      const remaining = todoItems.filter((t) => !t.completed);
      const todoList = remaining.map((t) => `${t.step}. ${t.text}`).join("\n");
      return {
        message: {
          customType: "plan-execution-context",
          content: `[EXECUTING PLAN - Full tool access active]

Remaining steps:
${todoList}

Execute each step systematically.
After completing step n, include a [DONE:n] marker in your response.`,
          display: false,
        },
      };
    }
  });

  // Track progress after each turn
  pi.on("turn_end", async (event, ctx) => {
    if (!executionMode || todoItems.length === 0) return;
    if (!isAssistantMessage(event.message)) return;

    const text = getTextContent(event.message);
    if (markCompletedSteps(text, todoItems) > 0) {
      updateStatus(ctx);
    }
    persistState();
  });

  // Handle plan completion and next action prompts
  pi.on("agent_end", async (event, ctx) => {
    if (executionMode && todoItems.length > 0) {
      if (todoItems.every((t) => t.completed)) {
        const completedList = todoItems.map((t) => `~~${t.text}~~`).join("\n");
        pi.sendMessage(
          { customType: "plan-complete", content: `**Plan Execution Complete!** ✓\n\n${completedList}`, display: true },
          { triggerTurn: false }
        );
        executionMode = false;
        todoItems = [];
        updateStatus(ctx);
        persistState();
      }
      return;
    }

    if (!planModeEnabled || !ctx.hasUI) return;

    const lastAssistant = [...event.messages].reverse().find(isAssistantMessage);
    if (lastAssistant) {
      const extracted = extractTodoItems(getTextContent(lastAssistant));
      if (extracted.length > 0) {
        todoItems = extracted;
      }
    }

    if (todoItems.length === 0) return;
    persistState();

    const todoListText = todoItems.map((t, i) => `${i + 1}. ☐ ${t.text}`).join("\n");
    const planTodoListMessage = {
      customType: "plan-todo-list",
      content: `**Plan Steps (${todoItems.length}):**\n\n${todoListText}`,
      display: true,
    };

    const choice = await ctx.ui.select("Plan mode - Choose next action:", [
      "Execute the plan (track progress & enable write tools)",
      "Stay in plan mode",
      "Refine the plan",
    ]);

    if (choice?.startsWith("Execute")) {
      const firstTodoItem = todoItems[0];
      if (!firstTodoItem) return;

      planModeEnabled = false;
      executionMode = true;
      restoreNormalModeTools();
      updateStatus(ctx);
      persistState();

      const remainingList = todoItems.map((t) => `${t.step}. ${t.text}`).join("\n");
      const execMessage = `Execute the plan.

Remaining steps:
${remainingList}

Start with: ${firstTodoItem.text}
After completing step n, include a [DONE:n] tag in your response.`;
      pi.sendMessage(planTodoListMessage, { deliverAs: "followUp" });
      pi.sendMessage(
        { customType: "plan-mode-execute", content: execMessage, display: true },
        { triggerTurn: true, deliverAs: "followUp" }
      );
    } else if (choice === "Refine the plan") {
      const refinement = await ctx.ui.editor("Refine the plan:", "");
      if (refinement?.trim()) {
        pi.sendMessage(planTodoListMessage, { deliverAs: "followUp" });
        pi.sendUserMessage(refinement.trim(), { deliverAs: "followUp" });
      }
    }
  });

  // Restore state on session start
  pi.on("session_start", async (_event, ctx) => {
    if (pi.getFlag("plan") === true) {
      planModeEnabled = true;
    }

    const entries = ctx.sessionManager.getEntries();
    const planModeEntry = entries
      .filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "plan-mode")
      .pop() as { data?: PlanModeState } | undefined;

    if (planModeEntry?.data) {
      planModeEnabled = planModeEntry.data.enabled ?? planModeEnabled;
      todoItems = planModeEntry.data.todos ?? todoItems;
      executionMode = planModeEntry.data.executing ?? executionMode;
      toolsBeforePlanMode = planModeEntry.data.toolsBeforePlanMode ?? toolsBeforePlanMode;
    }

    if (planModeEnabled) {
      enablePlanModeTools();
    }
    updateStatus(ctx);
  });
}
