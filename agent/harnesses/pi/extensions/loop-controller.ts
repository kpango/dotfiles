/**
 * Loop Controller Extension for Pi Coding Agent
 *
 * Implements periodic task execution (/loop <interval> <prompt>),
 * goal-driven iterative execution (/goal <condition> <prompt>),
 * deterministic condition evaluation, and execution bounds enforcement
 * (10-iteration hard cap, 5 consecutive failure abort).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  parseInterval,
  parseIntervalMs,
  parseGoalCondition,
  evaluateGoalPredicate,
  evaluateGoalCondition,
  LoopController,
  LoopControllerRegistry,
  type LoopState,
  type GoalAttemptResult,
} from "./lib/loop-controller-core";

export * from "./lib/loop-controller-core";

export const globalLoopRegistry = new LoopControllerRegistry();

export default function (pi: ExtensionAPI) {
  const intervalTimers = new Map<string, any>();
  let turnToolOutputs: string[] = [];
  let turnLastExitCode: number | undefined = undefined;

  // Track tool results within a turn
  pi.on("tool_result", async (event: any, ctx: any) => {
    const result = event?.result;
    let text = "";
    if (typeof result === "string") {
      text = result;
    } else if (result?.content && Array.isArray(result.content)) {
      text = result.content.map((c: any) => c?.text || "").join("\n");
    } else if (result?.text) {
      text = result.text;
    }
    if (result?.exitCode !== undefined) {
      turnLastExitCode = Number(result.exitCode);
    } else if (event?.isError) {
      turnLastExitCode = 1;
    } else if (event?.toolName === "bash" || event?.tool === "bash") {
      turnLastExitCode = event?.isError ? 1 : 0;
    }
    if (text) {
      turnToolOutputs.push(text);
    }
  });

  // Evaluate goal loops at turn end
  pi.on("turn_end", async (event: any, ctx: any) => {
    const activeGoalLoops = globalLoopRegistry
      .getActiveLoops()
      .filter((l) => l.type === "goal");

    if (activeGoalLoops.length === 0) {
      turnToolOutputs = [];
      turnLastExitCode = undefined;
      return;
    }

    const msg = event?.message;
    let assistantText = "";
    if (typeof msg === "string") {
      assistantText = msg;
    } else if (typeof msg?.content === "string") {
      assistantText = msg.content;
    } else if (Array.isArray(msg?.content)) {
      for (const part of msg.content) {
        if (typeof part === "string") assistantText += part + "\n";
        else if (part?.text) assistantText += part.text + "\n";
      }
    }

    const combinedOutput = [...turnToolOutputs, assistantText].filter(Boolean).join("\n");
    const exitCode = turnLastExitCode ?? (event?.isError ? 1 : 0);

    for (const controller of activeGoalLoops) {
      const res = controller.recordGoalAttempt({
        stdout: combinedOutput,
        exitCode,
        cwd: ctx?.cwd,
      });

      if (res.satisfied) {
        ctx.ui?.notify?.(
          `🏁 Goal SATISFIED at iteration ${res.iteration}!\nCondition: "${controller.condition}"\nOutput matched expectation.`,
          "info"
        );
      } else if (!res.continueLoop) {
        ctx.ui?.notify?.(
          `🚫 Goal loop HALTED: ${res.reason || controller.status}\nIterations: ${controller.iteration}/10 | Failures: ${controller.consecutiveFailures}/5`,
          "warning"
        );
      } else {
        ctx.ui?.notify?.(
          `🔄 Goal iteration ${res.iteration}/10 not satisfied (failures: ${controller.consecutiveFailures}/5). Retrying prompt...`,
          "info"
        );
        if (typeof (pi as any).sendUserMessage === "function") {
          (pi as any).sendUserMessage(controller.prompt, { deliverAs: "followUp" });
        } else if (typeof (ctx as any)?.sendUserMessage === "function") {
          (ctx as any).sendUserMessage(controller.prompt);
        }
      }
    }

    turnToolOutputs = [];
    turnLastExitCode = undefined;
  });

  // --------------------------------------------------------------------------
  // Slash Command: /loop
  // --------------------------------------------------------------------------
  pi.registerCommand("loop", {
    description: "Periodic execution controller (/loop <interval> <prompt> | /loop stop | /loop status)",
    handler: async (args, ctx) => {
      const raw = (args || "").trim();
      const parts = raw.split(/\s+/).filter(Boolean);
      const sub = parts[0]?.toLowerCase();

      if (sub === "stop") {
        for (const timer of intervalTimers.values()) {
          clearInterval(timer);
        }
        intervalTimers.clear();
        for (const ctrl of globalLoopRegistry.getActiveLoops()) {
          if (ctrl.type === "interval") {
            ctrl.stop("Stopped by /loop stop");
          }
        }
        ctx.ui?.notify?.("All active interval loops stopped.", "info");
        return;
      }

      if (sub === "status") {
        const intervalLoops = Array.from(globalLoopRegistry.getAllLoops().values()).filter(
          (l) => l.type === "interval"
        );
        if (intervalLoops.length === 0) {
          ctx.ui?.notify?.("No interval loops registered.", "info");
          return;
        }
        const summary = intervalLoops
          .map(
            (l) =>
              `• [${l.status}] id=${l.id} interval=${l.intervalMs}ms iterations=${l.iteration} prompt="${l.prompt}"`
          )
          .join("\n");
        ctx.ui?.notify?.(`Interval Loops:\n\n${summary}`, "info");
        return;
      }

      if (parts.length < 2) {
        ctx.ui?.notify?.(
          "Usage: /loop <interval> <prompt>\nExamples:\n  /loop 10s run git status\n  /loop 1m check build\n  /loop stop\n  /loop status",
          "warning"
        );
        return;
      }

      const intervalToken = parts[0];
      const intervalMs = parseInterval(intervalToken);
      if (!intervalMs || intervalMs <= 0) {
        ctx.ui?.notify?.(
          `Invalid interval "${intervalToken}". Use formats like 10s, 1m, 500ms.`,
          "error"
        );
        return;
      }

      const prompt = raw.slice(intervalToken.length).trim();
      if (!prompt) {
        ctx.ui?.notify?.("Prompt cannot be empty.", "warning");
        return;
      }

      const controller = new LoopController({
        type: "interval",
        intervalMs,
        prompt,
      });
      globalLoopRegistry.register(controller);

      const timer = setInterval(() => {
        if (controller.status !== "RUNNING") {
          clearInterval(timer);
          intervalTimers.delete(controller.id);
          return;
        }
        controller.iteration++;
        if (typeof (pi as any).sendUserMessage === "function") {
          (pi as any).sendUserMessage(prompt, { deliverAs: "followUp" });
        } else if (typeof (ctx as any)?.sendUserMessage === "function") {
          (ctx as any).sendUserMessage(prompt);
        }
      }, intervalMs);

      intervalTimers.set(controller.id, timer);

      ctx.ui?.notify?.(
        `Interval loop started: every ${intervalToken} (${intervalMs}ms)\nPrompt: "${prompt}"`,
        "info"
      );

      // Trigger first execution
      if (typeof (pi as any).sendUserMessage === "function") {
        (pi as any).sendUserMessage(prompt, { deliverAs: "followUp" });
      } else if (typeof (ctx as any)?.sendUserMessage === "function") {
        (ctx as any).sendUserMessage(prompt);
      }
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /goal
  // --------------------------------------------------------------------------
  pi.registerCommand("goal", {
    description: "Goal-driven iterative loop controller (/goal <condition> <prompt> | /goal abort | /goal status)",
    handler: async (args, ctx) => {
      const raw = (args || "").trim();
      const parts = raw.split(/\s+/).filter(Boolean);
      const sub = parts[0]?.toLowerCase();

      if (sub === "abort" || sub === "stop") {
        let count = 0;
        for (const ctrl of globalLoopRegistry.getActiveLoops()) {
          if (ctrl.type === "goal") {
            ctrl.stop("Aborted by /goal abort");
            count++;
          }
        }
        ctx.ui?.notify?.(`Aborted ${count} active goal loop(s).`, "info");
        return;
      }

      if (sub === "status") {
        const goalLoops = Array.from(globalLoopRegistry.getAllLoops().values()).filter(
          (l) => l.type === "goal"
        );
        if (goalLoops.length === 0) {
          ctx.ui?.notify?.("No goal loops registered.", "info");
          return;
        }
        const summary = goalLoops
          .map(
            (l) =>
              `• [${l.status}] id=${l.id} condition="${l.condition}" iter=${l.iteration}/10 failures=${l.consecutiveFailures}/5 prompt="${l.prompt}"`
          )
          .join("\n");
        ctx.ui?.notify?.(`Goal Loops:\n\n${summary}`, "info");
        return;
      }

      if (parts.length < 2) {
        ctx.ui?.notify?.(
          "Usage: /goal <condition> <prompt>\nExamples:\n  /goal exit:0 cargo test\n  /goal contains:PASSED pytest\n  /goal regex:ok:\\s+\\d+ bun test\n  /goal abort\n  /goal status",
          "warning"
        );
        return;
      }

      const conditionToken = parts[0];
      try {
        parseGoalCondition(conditionToken);
      } catch (e: any) {
        ctx.ui?.notify?.(`Invalid goal condition "${conditionToken}": ${e.message}`, "error");
        return;
      }

      const prompt = raw.slice(conditionToken.length).trim();
      if (!prompt) {
        ctx.ui?.notify?.("Prompt cannot be empty.", "warning");
        return;
      }

      const controller = new LoopController({
        type: "goal",
        condition: conditionToken,
        prompt,
        maxIterations: 10,
        maxConsecutiveFailures: 5,
      });
      globalLoopRegistry.register(controller);

      ctx.ui?.notify?.(
        `Goal loop started (id=${controller.id}):\n• Condition: "${conditionToken}"\n• Prompt: "${prompt}"\n• Bounds: max 10 iterations, 5 consecutive failure abort`,
        "info"
      );

      // Trigger initial attempt
      if (typeof (pi as any).sendUserMessage === "function") {
        (pi as any).sendUserMessage(prompt, { deliverAs: "followUp" });
      } else if (typeof (ctx as any)?.sendUserMessage === "function") {
        (ctx as any).sendUserMessage(prompt);
      }
    },
  });

  // --------------------------------------------------------------------------
  // Tool: goal_loop
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "goal_loop",
    description: "Register and initiate a goal-driven iterative loop evaluated after each agent turn.",
    parameters: Type.Object({
      condition: Type.String({
        description: "Goal predicate (e.g. \"exit:0\", \"contains:success\", \"regex:ok:\\\\s+\\\\d+\")",
      }),
      prompt: Type.String({ description: "Prompt to execute iteratively toward the goal" }),
      maxIterations: Type.Optional(
        Type.Integer({ description: "Maximum iteration cap (clamped to at most 10)" })
      ),
    }),
    handler: async (args, ctx) => {
      try {
        parseGoalCondition(args.condition);
      } catch (e: any) {
        return {
          content: [{ type: "text", text: `Invalid goal condition: ${e.message}` }],
        };
      }

      const controller = new LoopController({
        type: "goal",
        condition: args.condition,
        prompt: args.prompt,
        maxIterations: args.maxIterations ?? 10,
        maxConsecutiveFailures: 5,
      });
      globalLoopRegistry.register(controller);

      if (typeof (pi as any).sendUserMessage === "function") {
        (pi as any).sendUserMessage(args.prompt, { deliverAs: "followUp" });
      } else if (typeof (ctx as any)?.sendUserMessage === "function") {
        (ctx as any).sendUserMessage(args.prompt);
      }

      return {
        content: [
          {
            type: "text",
            text: `Registered goal loop id=${controller.id} condition="${args.condition}" (max iterations: ${controller.maxIterations}, abort at 5 consecutive failures).`,
          },
        ],
      };
    },
  });

  // --------------------------------------------------------------------------
  // Tool: cancel_goal_loop
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "cancel_goal_loop",
    description: "Cancel active goal loops by id or cancel all active goal loops.",
    parameters: Type.Object({
      loopId: Type.Optional(Type.String({ description: "Optional specific loop ID to cancel" })),
      reason: Type.Optional(Type.String({ description: "Reason for cancellation" })),
    }),
    handler: async (args) => {
      if (args.loopId) {
        const stopped = globalLoopRegistry.stop(args.loopId, args.reason || "Cancelled by tool");
        return {
          content: [
            {
              type: "text",
              text: stopped
                ? `Successfully stopped goal loop ${args.loopId}.`
                : `Loop ${args.loopId} was not found or already stopped.`,
            },
          ],
        };
      }
      let count = 0;
      for (const ctrl of globalLoopRegistry.getActiveLoops()) {
        if (ctrl.type === "goal") {
          ctrl.stop(args.reason || "Cancelled by tool");
          count++;
        }
      }
      return {
        content: [{ type: "text", text: `Cancelled ${count} active goal loop(s).` }],
      };
    },
  });
}
