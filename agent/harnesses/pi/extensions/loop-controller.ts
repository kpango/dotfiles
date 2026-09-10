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
  parseGoalCondition,
  LoopController,
  LoopControllerRegistry,
  CONSECUTIVE_FAILURES_ABORT_THRESHOLD,
  type LoopMode,
} from "./lib/loop-controller-core";

export * from "./lib/loop-controller-core";

export const globalLoopRegistry = new LoopControllerRegistry();

export default function (pi: ExtensionAPI) {
  const intervalTimers = new Map<string, any>();
  const intervalIterations = new Map<string, number>();
  let turnToolOutputs: string[] = [];
  let turnLastExitCode: number | undefined = undefined;

  // Resolve running controllers of a given mode from the registry.
  // The registry stores states; we map each back to its live controller.
  function runningControllers(mode: LoopMode): LoopController[] {
    return globalLoopRegistry
      .listLoops()
      .filter((s) => s.status === "RUNNING" && s.mode === mode)
      .map((s) => globalLoopRegistry.getController(s.id))
      .filter((c): c is LoopController => Boolean(c));
  }

  function sendPrompt(ctx: any, prompt: string): void {
    if (typeof (pi as any).sendUserMessage === "function") {
      (pi as any).sendUserMessage(prompt, { deliverAs: "followUp" });
    } else if (typeof ctx?.sendUserMessage === "function") {
      ctx.sendUserMessage(prompt);
    }
  }

  // Track tool results within a turn
  pi.on("tool_result", async (event: any, _ctx: any) => {
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
    const activeGoalLoops = runningControllers("goal");

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
      const res = controller.recordGoalAttempt({ output: combinedOutput, exitCode });
      const st = res.state;
      const conditionRaw = st.condition?.raw ?? "";

      if (res.satisfied) {
        ctx.ui?.notify?.(
          `🏁 Goal SATISFIED at iteration ${st.iteration}!\nCondition: "${conditionRaw}"\nOutput matched expectation.`,
          "info"
        );
      } else if (!res.continueLoop) {
        ctx.ui?.notify?.(
          `🚫 Goal loop HALTED: ${st.failureReason || st.status}\nIterations: ${st.iteration}/${st.maxIterations} | Failures: ${st.consecutiveFailures}/${CONSECUTIVE_FAILURES_ABORT_THRESHOLD}`,
          "warning"
        );
      } else {
        ctx.ui?.notify?.(
          `🔄 Goal iteration ${st.iteration}/${st.maxIterations} not satisfied (failures: ${st.consecutiveFailures}/${CONSECUTIVE_FAILURES_ABORT_THRESHOLD}). Retrying prompt...`,
          "info"
        );
        sendPrompt(ctx, st.prompt);
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
        intervalIterations.clear();
        for (const ctrl of runningControllers("interval")) {
          ctrl.stop();
        }
        ctx.ui?.notify?.("All active interval loops stopped.", "info");
        return;
      }

      if (sub === "status") {
        const intervalLoops = globalLoopRegistry.listLoops().filter((l) => l.mode === "interval");
        if (intervalLoops.length === 0) {
          ctx.ui?.notify?.("No interval loops registered.", "info");
          return;
        }
        const summary = intervalLoops
          .map(
            (l) =>
              `• [${l.status}] id=${l.id} interval=${l.intervalMs}ms iterations=${
                intervalIterations.get(l.id) ?? l.iteration
              } prompt="${l.prompt}"`
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

      const controller = new LoopController();
      const state = controller.startIntervalLoop({ prompt, intervalMs });
      globalLoopRegistry.registerLoop(controller);
      const id = state.id;
      intervalIterations.set(id, 0);

      const timer = setInterval(() => {
        if (controller.getState()?.status !== "RUNNING") {
          clearInterval(timer);
          intervalTimers.delete(id);
          intervalIterations.delete(id);
          return;
        }
        intervalIterations.set(id, (intervalIterations.get(id) ?? 0) + 1);
        sendPrompt(ctx, prompt);
      }, intervalMs);

      // Do not let a running interval loop pin the Node event loop / block a
      // clean process exit (mirrors swarm-relay's heartbeat). The interactive
      // REPL keeps the session alive; the loop still fires while the session is
      // running, and self-clears once the controller leaves RUNNING state.
      if (typeof timer.unref === "function") timer.unref();

      intervalTimers.set(id, timer);

      ctx.ui?.notify?.(
        `Interval loop started: every ${intervalToken} (${intervalMs}ms)\nPrompt: "${prompt}"`,
        "info"
      );

      // Trigger first execution
      sendPrompt(ctx, prompt);
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
        for (const ctrl of runningControllers("goal")) {
          ctrl.stop();
          count++;
        }
        ctx.ui?.notify?.(`Aborted ${count} active goal loop(s).`, "info");
        return;
      }

      if (sub === "status") {
        const goalLoops = globalLoopRegistry.listLoops().filter((l) => l.mode === "goal");
        if (goalLoops.length === 0) {
          ctx.ui?.notify?.("No goal loops registered.", "info");
          return;
        }
        const summary = goalLoops
          .map(
            (l) =>
              `• [${l.status}] id=${l.id} condition="${l.condition?.raw ?? ""}" iter=${l.iteration}/${l.maxIterations} failures=${l.consecutiveFailures}/${CONSECUTIVE_FAILURES_ABORT_THRESHOLD} prompt="${l.prompt}"`
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

      const controller = new LoopController();
      const state = controller.startGoalLoop({
        prompt,
        condition: conditionToken,
        maxIterations: 10,
      });
      globalLoopRegistry.registerLoop(controller);

      ctx.ui?.notify?.(
        `Goal loop started (id=${state.id}):\n• Condition: "${conditionToken}"\n• Prompt: "${prompt}"\n• Bounds: max ${state.maxIterations} iterations, ${CONSECUTIVE_FAILURES_ABORT_THRESHOLD} consecutive failure abort`,
        "info"
      );

      // Trigger initial attempt
      sendPrompt(ctx, prompt);
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
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      try {
        parseGoalCondition(params.condition);
      } catch (e: any) {
        return {
          content: [{ type: "text", text: `Invalid goal condition: ${e.message}` }],
        };
      }

      const controller = new LoopController();
      const state = controller.startGoalLoop({
        condition: params.condition,
        prompt: params.prompt,
        maxIterations: params.maxIterations ?? 10,
      });
      globalLoopRegistry.registerLoop(controller);

      sendPrompt(ctx, params.prompt);

      return {
        content: [
          {
            type: "text",
            text: `Registered goal loop id=${state.id} condition="${params.condition}" (max iterations: ${state.maxIterations}, abort at ${CONSECUTIVE_FAILURES_ABORT_THRESHOLD} consecutive failures).`,
          },
        ],
      };
    },
    handler: async (args, ctx) => {
      try {
        parseGoalCondition(args.condition);
      } catch (e: any) {
        return {
          content: [{ type: "text", text: `Invalid goal condition: ${e.message}` }],
        };
      }

      const controller = new LoopController();
      const state = controller.startGoalLoop({
        condition: args.condition,
        prompt: args.prompt,
        maxIterations: args.maxIterations ?? 10,
      });
      globalLoopRegistry.registerLoop(controller);

      sendPrompt(ctx, args.prompt);

      return {
        content: [
          {
            type: "text",
            text: `Registered goal loop id=${state.id} condition="${args.condition}" (max iterations: ${state.maxIterations}, abort at ${CONSECUTIVE_FAILURES_ABORT_THRESHOLD} consecutive failures).`,
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
    async execute(_toolCallId, params) {
      if (params.loopId) {
        const stopped = globalLoopRegistry.stopLoop(params.loopId);
        return {
          content: [
            {
              type: "text",
              text: stopped
                ? `Successfully stopped goal loop ${params.loopId}.`
                : `Loop ${params.loopId} was not found or already stopped.`,
            },
          ],
        };
      }
      let count = 0;
      for (const ctrl of runningControllers("goal")) {
        ctrl.stop();
        count++;
      }
      return {
        content: [
          {
            type: "text",
            text: `Cancelled ${count} active goal loop(s)${params.reason ? `: ${params.reason}` : "."}`,
          },
        ],
      };
    },
    handler: async (args) => {
      if (args.loopId) {
        const stopped = globalLoopRegistry.stopLoop(args.loopId);
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
      for (const ctrl of runningControllers("goal")) {
        ctrl.stop();
        count++;
      }
      return {
        content: [{ type: "text", text: `Cancelled ${count} active goal loop(s).` }],
      };
    },
  });
}
