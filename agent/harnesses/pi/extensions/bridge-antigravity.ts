/**
 * Antigravity CLI Bridge Extension for Pi Coding Agent
 *
 * Allows Pi to delegate reasoning, multi-turn plan/edit tasks,
 * and Gemini 3 / MCP workflows to Google Antigravity CLI (`agy`).
 *
 * プロセスのspawn/ストリーミング/abort処理は bridge-claude.ts・bridge-codex.ts と
 * 一字一句同一だったため pi/extensions/lib/cli-bridge.ts へ統合済み(2026-09-03)。
 * paramsスキーマ・CLI引数構築・render関数はツール固有のためこのファイルに残す。
 */

import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { deriveCliBridgeOutput, runCliBridge } from "./lib/cli-bridge";

const AgyParams = Type.Object({
  prompt: Type.String({ description: "Prompt or instruction to send to Antigravity CLI" }),
  cwd: Type.Optional(Type.String({ description: "Working directory for Antigravity (defaults to current CWD)" })),
  model: Type.Optional(Type.String({ description: "Model for Antigravity session (e.g. gemini-3-pro-preview, gemini-2.5-pro)" })),
  effort: Type.Optional(Type.Union([Type.Literal("low"), Type.Literal("medium"), Type.Literal("high")], {
    description: "Reasoning effort level for Antigravity session",
    default: "high",
  })),
  mode: Type.Optional(Type.Union([Type.Literal("accept-edits"), Type.Literal("plan")], {
    description: "Execution mode for Antigravity (accept-edits or plan)",
    default: "accept-edits",
  })),
  sandbox: Type.Optional(Type.Boolean({ description: "Run with sandbox restrictions enabled", default: false })),
});

interface AgyResultDetails {
  exitCode: number;
  stdout: string;
  stderr: string;
  cwd: string;
  model?: string;
  effort?: string;
}

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "antigravity",
    label: "Antigravity CLI (AGY)",
    description: "Execute a task or prompt via Google Antigravity CLI (`agy`) non-interactively with Gemini reasoning and deep coding capabilities.",
    parameters: AgyParams,

    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const targetCwd = params.cwd ? path.resolve(ctx.cwd, params.cwd) : ctx.cwd;
      const args: string[] = ["-p", params.prompt];

      if (params.model) {
        args.push("--model", params.model);
      }
      if (params.effort) {
        args.push("--effort", params.effort);
      }
      if (params.mode) {
        args.push("--mode", params.mode);
      }
      if (params.sandbox) {
        args.push("--sandbox");
      }

      const { exitCode, stdout, stderr, wasAborted } = await runCliBridge({
        binary: "agy",
        args,
        cwd: targetCwd,
        env: { ...process.env },
        signal,
        runningPlaceholder: "(Antigravity reasoning...)",
        onUpdate: onUpdate
          ? (u) =>
              onUpdate({
                content: [{ type: "text", text: u.displayText }],
                details: {
                  exitCode: -1,
                  stdout: u.stdout,
                  stderr: u.stderr,
                  cwd: targetCwd,
                  model: params.model,
                  effort: params.effort,
                } as AgyResultDetails,
              })
          : undefined,
      });

      if (wasAborted) {
        return {
          content: [{ type: "text", text: "Antigravity execution was aborted." }],
          isError: true,
          details: { exitCode: 130, stdout, stderr, cwd: targetCwd } as AgyResultDetails,
        };
      }

      const { isError, outputText } = deriveCliBridgeOutput(exitCode, stdout, stderr, "Antigravity exited with error.");

      return {
        content: [{ type: "text", text: outputText }],
        isError,
        details: {
          exitCode,
          stdout,
          stderr,
          cwd: targetCwd,
          model: params.model,
          effort: params.effort,
        } as AgyResultDetails,
      };
    },

    renderCall(args, theme) {
      const preview = args.prompt.length > 60 ? `${args.prompt.slice(0, 60)}...` : args.prompt;
      const modelTag = args.model ? theme.fg("muted", ` [${args.model}]`) : "";
      const effortTag = args.effort ? theme.fg("accent", ` (${args.effort})`) : "";
      return new Text(
        theme.fg("toolTitle", theme.bold("agy ")) + theme.fg("accent", "Antigravity") + modelTag + effortTag + "\n  " + theme.fg("dim", preview),
        0,
        0
      );
    },

    renderResult(result, { expanded }, theme) {
      const details = result.details as AgyResultDetails | undefined;
      const container = new Container();
      const statusIcon = result.isError ? theme.fg("error", "✗ Antigravity Failed") : theme.fg("success", "✓ Antigravity Complete");

      container.addChild(new Text(`${statusIcon}${details?.model ? theme.fg("muted", ` (${details.model})`) : ""}`, 0, 0));

      const rawText = result.content[0]?.type === "text" ? result.content[0].text : "(no output)";
      if (expanded || result.isError) {
        container.addChild(new Text(theme.fg("toolOutput", rawText), 0, 0));
        if (details?.stderr && details.stderr.trim()) {
          container.addChild(new Text(theme.fg("error", `stderr:\n${details.stderr.trim()}`), 0, 0));
        }
      } else {
        const preview = rawText.split("\n").slice(0, 5).join("\n");
        container.addChild(new Text(theme.fg("toolOutput", preview), 0, 0));
      }
      return container;
    },
  });

  // Register Slash Command /agy
  pi.registerCommand("agy", {
    description: "Delegate a prompt directly to Antigravity CLI (AGY)",
    handler: async (args, ctx) => {
      if (!args || !args.trim()) {
        ctx.ui.notify("Usage: /agy <prompt>", "warning");
        return;
      }
      ctx.ui.notify("Delegating to Antigravity CLI...", "info");
      ctx.sendUserMessage(`Run Antigravity CLI on: ${args.trim()}`);
    },
  });
}
