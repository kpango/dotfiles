/**
 * Claude Code CLI Bridge Extension for Pi Coding Agent
 *
 * Allows Pi to delegate prompts, code analysis, and complex tasks
 * directly to Anthropic Claude Code CLI (`claude`).
 *
 * プロセスのspawn/ストリーミング/abort処理は bridge-antigravity.ts・bridge-codex.ts と
 * 一字一句同一だったため pi/extensions/lib/cli-bridge.ts へ統合済み(2026-09-03)。
 * paramsスキーマ・CLI引数構築・render関数はツール固有のためこのファイルに残す。
 */

import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { deriveCliBridgeOutput, runCliBridge } from "./lib/cli-bridge";

const ClaudeParams = Type.Object({
  prompt: Type.String({ description: "Prompt or instruction to send to Claude Code" }),
  cwd: Type.Optional(Type.String({ description: "Working directory for Claude Code (defaults to current CWD)" })),
  model: Type.Optional(Type.String({ description: "Model to use in Claude Code (e.g. sonnet, opus, haiku)" })),
  dangerouslySkipPermissions: Type.Optional(
    Type.Boolean({ description: "Skip permission checks in Claude Code for non-interactive execution. Default: true.", default: true })
  ),
  systemPrompt: Type.Optional(Type.String({ description: "Custom system prompt for Claude Code session" })),
});

interface ClaudeResultDetails {
  exitCode: number;
  stdout: string;
  stderr: string;
  cwd: string;
  model?: string;
}

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "claude_code",
    label: "Claude Code CLI",
    description: "Execute a task or prompt via Claude Code CLI (`claude`) non-interactively with full agent reasoning and permissions.",
    parameters: ClaudeParams,

    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const targetCwd = params.cwd ? path.resolve(ctx.cwd, params.cwd) : ctx.cwd;
      const skipPerms = params.dangerouslySkipPermissions ?? true;

      const args: string[] = ["--print"];
      if (skipPerms) {
        args.push("--dangerously-skip-permissions");
      }
      if (params.model) {
        args.push("--model", params.model);
      }
      if (params.systemPrompt) {
        args.push("--system-prompt", params.systemPrompt);
      }
      args.push(params.prompt);

      const { exitCode, stdout, stderr, wasAborted } = await runCliBridge({
        binary: "claude",
        args,
        cwd: targetCwd,
        env: { ...process.env, CLAUDE_CODE_ENABLE_TELEMETRY: "0" },
        signal,
        runningPlaceholder: "(Claude Code running...)",
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
                } as ClaudeResultDetails,
              })
          : undefined,
      });

      if (wasAborted) {
        return {
          content: [{ type: "text", text: "Claude Code execution was aborted." }],
          isError: true,
          details: { exitCode: 130, stdout, stderr, cwd: targetCwd, model: params.model } as ClaudeResultDetails,
        };
      }

      const { isError, outputText } = deriveCliBridgeOutput(exitCode, stdout, stderr, "Claude Code exited with error.");

      return {
        content: [{ type: "text", text: outputText }],
        isError,
        details: {
          exitCode,
          stdout,
          stderr,
          cwd: targetCwd,
          model: params.model,
        } as ClaudeResultDetails,
      };
    },

    renderCall(args, theme) {
      const preview = args.prompt.length > 60 ? `${args.prompt.slice(0, 60)}...` : args.prompt;
      const modelTag = args.model ? theme.fg("muted", ` [${args.model}]`) : "";
      return new Text(
        theme.fg("toolTitle", theme.bold("claude ")) + theme.fg("accent", "CLI") + modelTag + "\n  " + theme.fg("dim", preview),
        0,
        0
      );
    },

    renderResult(result, { expanded }, theme) {
      const details = result.details as ClaudeResultDetails | undefined;
      const container = new Container();
      const statusIcon = result.isError ? theme.fg("error", "✗ Claude Code Failed") : theme.fg("success", "✓ Claude Code Complete");

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

  // Register Slash Command /claude
  pi.registerCommand("claude", {
    description: "Delegate a prompt directly to Claude Code CLI",
    handler: async (args, ctx) => {
      if (!args || !args.trim()) {
        ctx.ui.notify("Usage: /claude <prompt>", "warning");
        return;
      }
      ctx.ui.notify("Delegating to Claude Code...", "info");
      ctx.sendUserMessage(`Run Claude Code on: ${args.trim()}`);
    },
  });
}
