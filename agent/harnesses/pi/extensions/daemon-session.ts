/**
 * GrokBot-Style Persistent Daemon Session Extension for Pi Coding Agent
 *
 * Spawns headless detached background daemon processes surviving TTY disconnection,
 * provides /daemon CLI control, registers daemon_spawn tool, and broadcasts
 * progress events over the Subagent Mesh / Blackboard.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

import {
  DaemonSessionRecord,
  SpawnDaemonOptions,
  generateDaemonId,
  spawnDaemonProcess,
  checkDaemonLiveness,
  terminateDaemonProcess,
  listActiveDaemons,
  readDaemonLog,
  getDaemonDetails,
  emitMeshProgress,
  getDefaultDaemonDir,
} from "./lib/daemon-session-core";

// Re-export core types and functions
export * from "./lib/daemon-session-core";

export default function (pi: ExtensionAPI) {
  // --------------------------------------------------------------------------
  // Tool: daemon_spawn
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "daemon_spawn",
    label: "Spawn Daemon Process",
    description:
      "Spawn a persistent detached background daemon process for long-running execution surviving TTY disconnect.",
    parameters: Type.Object({
      objective: Type.String({ description: "Task objective or prompt for the background daemon to execute." }),
      model: Type.Optional(Type.String({ description: "Optional model name or tier override for the daemon." })),
    }),
    handler: async (args, ctx) => {
      try {
        const cwd = ctx?.cwd || process.cwd();
        const record = spawnDaemonProcess({
          objective: args.objective,
          cwd,
          model: args.model,
        });

        // Notify user
        ctx.ui?.notify?.(
          `[Daemon] Spawned background process (${record.daemonId}, PID: ${record.pid})\nLog: ${record.logPath}`,
          "info"
        );

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(
                {
                  spawned: true,
                  daemonId: record.daemonId,
                  pid: record.pid,
                  status: record.status,
                  objective: record.objective,
                  model: record.model,
                  logPath: record.logPath,
                  statePath: record.statePath,
                },
                null,
                2
              ),
            },
          ],
        };
      } catch (err: any) {
        return {
          content: [
            {
              type: "text",
              text: `Error spawning daemon process: ${err.message}`,
            },
          ],
        };
      }
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /daemon [spawn <prompt> | list | kill <id> | status <id>]
  // --------------------------------------------------------------------------
  pi.registerCommand("daemon", {
    description: "Manage background daemon sessions (/daemon [spawn <prompt>|list|kill <id>|status <id>])",
    handler: async (args, ctx) => {
      const parts = (args || "").trim().split(/\s+/);
      const action = parts[0]?.toLowerCase() || "list";
      const target = parts.slice(1).join(" ");

      if (action === "spawn") {
        if (!target) {
          ctx.ui?.notify?.("Usage: /daemon spawn <prompt>", "warning");
          return;
        }
        try {
          const cwd = ctx?.cwd || process.cwd();
          const record = spawnDaemonProcess({
            objective: target,
            cwd,
          });
          ctx.ui?.notify?.(
            `Daemon spawned successfully!\n• ID: ${record.daemonId}\n• PID: ${record.pid}\n• Log: ${record.logPath}`,
            "info"
          );
        } catch (err: any) {
          ctx.ui?.notify?.(`Failed to spawn daemon: ${err.message}`, "error");
        }
        return;
      }

      if (action === "list") {
        const daemons = listActiveDaemons();
        if (daemons.length === 0) {
          ctx.ui?.notify?.("No daemon sessions recorded in " + getDefaultDaemonDir(), "info");
          return;
        }

        const lines = ["Active / Recent Daemon Sessions:"];
        for (const d of daemons) {
          const aliveIndicator = checkDaemonLiveness(d.pid) ? "🟢" : "⚪";
          const started = new Date(d.startedAt).toLocaleTimeString();
          lines.push(
            `• ${aliveIndicator} [${d.status}] ${d.daemonId} (PID: ${d.pid}) started at ${started}\n  Objective: ${d.objective}`
          );
        }
        ctx.ui?.notify?.(lines.join("\n"), "info");
        return;
      }

      if (action === "status") {
        if (!target) {
          ctx.ui?.notify?.("Usage: /daemon status <id>", "warning");
          return;
        }
        const { record, logTail } = getDaemonDetails(target);
        if (!record) {
          ctx.ui?.notify?.(`Daemon session '${target}' not found.`, "error");
          return;
        }

        const isAlive = checkDaemonLiveness(record.pid);
        const aliveStr = isAlive ? "ALIVE (Running)" : "DEAD (Exited)";
        const info = [
          `Daemon Status: ${record.daemonId}`,
          `• PID: ${record.pid} (${aliveStr})`,
          `• Status: ${record.status}`,
          `• Objective: ${record.objective}`,
          `• Started: ${new Date(record.startedAt).toISOString()}`,
          `• Log File: ${record.logPath}`,
          `\nRecent Log Tail:\n${logTail}`,
        ];
        ctx.ui?.notify?.(info.join("\n"), "info");
        return;
      }

      if (action === "kill" || action === "stop") {
        if (!target) {
          ctx.ui?.notify?.("Usage: /daemon kill <id|pid>", "warning");
          return;
        }

        let targetPid: number | undefined;
        let daemonRecord: DaemonSessionRecord | undefined;

        if (/^\d+$/.test(target)) {
          targetPid = parseInt(target, 10);
        } else {
          const { record } = getDaemonDetails(target);
          if (record) {
            daemonRecord = record;
            targetPid = record.pid;
          }
        }

        if (!targetPid) {
          ctx.ui?.notify?.(`Daemon session or PID '${target}' not found.`, "error");
          return;
        }

        const ok = terminateDaemonProcess(targetPid);
        if (daemonRecord) {
          emitMeshProgress(daemonRecord, "daemon", { event: "DAEMON_TERMINATED" });
        }

        if (ok) {
          ctx.ui?.notify?.(`Daemon process ${targetPid} terminated.`, "info");
        } else {
          ctx.ui?.notify?.(`Failed to terminate daemon process ${targetPid}.`, "error");
        }
        return;
      }

      ctx.ui?.notify?.(
        `Unknown action '${action}'. Usage: /daemon [spawn <prompt>|list|status <id>|kill <id>]`,
        "warning"
      );
    },
  });
}
