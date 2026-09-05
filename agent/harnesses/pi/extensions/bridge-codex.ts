/**
 * OpenAI Codex CLI Bridge Extension for Pi Coding Agent
 *
 * Allows Pi to delegate prompts, completions, and code review
 * directly to OpenAI Codex CLI (`codex`).
 *
 * プロセスのspawn/ストリーミング/abort処理は bridge-claude.ts・bridge-antigravity.ts と
 * 一字一句同一だったため pi/extensions/lib/cli-bridge.ts へ統合済み(2026-09-03)。
 * paramsスキーマ・CLI引数構築・render関数はツール固有のためこのファイルに残す。
 */

import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { deriveCliBridgeOutput, runCliBridge } from "./lib/cli-bridge";

const CodexParams = Type.Object({
  prompt: Type.String({ description: "Prompt or instruction to send to Codex CLI" }),
  cwd: Type.Optional(Type.String({ description: "Working directory for Codex (defaults to current CWD)" })),
  model: Type.Optional(Type.String({ description: "Model to use in Codex CLI (e.g. o3, o3-mini, gpt-4o)" })),
  sandbox: Type.Optional(
    Type.Union([Type.Literal("read-only"), Type.Literal("workspace-write"), Type.Literal("danger-full-access")], {
      description: "Sandbox execution mode for Codex",
      default: "workspace-write",
    })
  ),
  search: Type.Optional(Type.Boolean({ description: "Enable live web search in Codex", default: false })),
});

interface CodexResultDetails {
  exitCode: number;
  stdout: string;
  stderr: string;
  cwd: string;
  model?: string;
}

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "codex",
    label: "Codex CLI",
    description: "Execute a task or prompt via OpenAI Codex CLI (`codex`) non-interactively.",
    parameters: CodexParams,

    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const targetCwd = params.cwd ? path.resolve(ctx.cwd, params.cwd) : ctx.cwd;
      const args: string[] = ["exec"];

      if (params.model) {
        args.push("-m", params.model);
      }
      if (params.sandbox) {
        args.push("-s", params.sandbox);
      }
      if (params.search) {
        args.push("--search");
      }
      args.push("-C", targetCwd);
      args.push(params.prompt);

      const { exitCode, stdout, stderr, wasAborted } = await runCliBridge({
        binary: "codex",
        args,
        cwd: targetCwd,
        env: { ...process.env },
        signal,
        runningPlaceholder: "(Codex running...)",
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
                } as CodexResultDetails,
              })
          : undefined,
      });

      if (wasAborted) {
        return {
          content: [{ type: "text", text: "Codex execution was aborted." }],
          isError: true,
          details: { exitCode: 130, stdout, stderr, cwd: targetCwd } as CodexResultDetails,
        };
      }

      const { isError, outputText } = deriveCliBridgeOutput(exitCode, stdout, stderr, "Codex exited with error.");

      return {
        content: [{ type: "text", text: outputText }],
        isError,
        details: {
          exitCode,
          stdout,
          stderr,
          cwd: targetCwd,
          model: params.model,
        } as CodexResultDetails,
      };
    },

    renderCall(args, theme) {
      const preview = args.prompt.length > 60 ? `${args.prompt.slice(0, 60)}...` : args.prompt;
      const modelTag = args.model ? theme.fg("muted", ` [${args.model}]`) : "";
      return new Text(
        theme.fg("toolTitle", theme.bold("codex ")) + theme.fg("accent", "CLI") + modelTag + "\n  " + theme.fg("dim", preview),
        0,
        0
      );
    },

    renderResult(result, { expanded }, theme) {
      const details = result.details as CodexResultDetails | undefined;
      const container = new Container();
      const statusIcon = result.isError ? theme.fg("error", "✗ Codex Failed") : theme.fg("success", "✓ Codex Complete");

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

  // Register Slash Command /codex
  pi.registerCommand("codex", {
    description: "Delegate a prompt directly to OpenAI Codex CLI",
    handler: async (args, ctx) => {
      if (!args || !args.trim()) {
        ctx.ui.notify("Usage: /codex <prompt>", "warning");
        return;
      }
      ctx.ui.notify("Delegating to Codex CLI...", "info");
      ctx.sendUserMessage(`Run Codex CLI on: ${args.trim()}`);
    },
  });
}
