/**
 * Hermes Agent & Oh My Hermes (OMH) CLI Bridge Extension for Oh My Pi (OMP)
 *
 * Delegates research, memory recall, or consensus planning to a named Hermes Agent
 * profile via the shared `cli-bridge.ts` runner.
 */

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import { Type } from "typebox";
import { deriveCliBridgeOutput, runCliBridge } from "./lib/cli-bridge";

export const HERMES_PROFILES = ["chief", "researcher", "swe", "perf", "sec-reviewer", "ops"] as const;
export type HermesProfile = (typeof HERMES_PROFILES)[number];

const HermesParams = Type.Object({
  profile: Type.Optional(
    Type.Union(
      HERMES_PROFILES.map((p) => Type.Literal(p)),
      {
        description: "Named Hermes Agent profile (chief, researcher, swe, perf, sec-reviewer, ops)",
        default: "chief",
      }
    )
  ),
  prompt: Type.String({ description: "Self-contained query or task for Hermes Agent" }),
  timeoutMs: Type.Optional(
    Type.Integer({
      description: "Execution timeout in milliseconds (default: 180000ms)",
      default: 180000,
      minimum: 5000,
      maximum: 600000,
    })
  ),
});

interface HermesResultDetails {
  exitCode: number;
  profile: HermesProfile;
  stdout: string;
  stderr: string;
  timedOut?: boolean;
}

export function buildHermesArgs(params: { profile?: HermesProfile; prompt: string }): string[] {
  const profile = params.profile ?? "chief";
  return ["-p", profile, "chat", "-q", params.prompt];
}

export default function bridgeHermesExtension(pi: ExtensionAPI) {
  (pi as { setLabel?: (label: string) => void }).setLabel?.("Hermes & OMH Bridge");

  pi.registerTool({
    name: "hermes_query",
    label: "Query Hermes Agent / OMH",
    description: "Delegate research, memory recall, or consensus planning to a named Hermes Agent profile.",
    parameters: HermesParams,
    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const profile: HermesProfile = params.profile ?? "chief";
      const timeoutMs = params.timeoutMs ?? 180000;
      const args = buildHermesArgs({ profile, prompt: params.prompt });

      const { exitCode, stdout, stderr, wasAborted, timedOut } = await runCliBridge({
        binary: "hermes",
        args,
        cwd: ctx.cwd,
        timeoutMs,
        signal,
        runningPlaceholder: `(Hermes ${profile} running...)`,
        onUpdate: onUpdate
          ? (u) =>
              onUpdate({
                content: [{ type: "text", text: u.displayText }],
                details: {
                  exitCode: -1,
                  profile,
                  stdout: u.stdout,
                  stderr: u.stderr,
                } as HermesResultDetails,
              })
          : undefined,
      });

      if (wasAborted) {
        return {
          content: [{ type: "text", text: "Hermes Agent execution was aborted." }],
          isError: true,
          details: { exitCode: 130, profile, stdout, stderr } as HermesResultDetails,
        };
      }

      const { isError, outputText } = deriveCliBridgeOutput(exitCode, stdout, stderr, "Hermes Agent exited with error.");

      return {
        content: [{ type: "text", text: outputText }],
        isError,
        details: {
          exitCode,
          profile,
          stdout,
          stderr,
          timedOut,
        } as HermesResultDetails,
      };
    },
  });
}
