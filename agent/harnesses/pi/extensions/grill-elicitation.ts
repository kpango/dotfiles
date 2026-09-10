/**
 * Grill Elicitation Extension for Pi Coding Agent
 *
 * Provides interactive design-tree elicitation (/grill command and grill_interview tool)
 * to prevent cognitive drift and automatically synthesize ADRs and CONTEXT.md invariants.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import {
  createInterviewSession,
  addQuestionNode,
  recordAnswer,
  getNextPendingQuestion,
  generateDefaultInterviewTree,
  formatQuestionPrompt,
  generateADR,
  synthesizeContext,
  formatStatusReport,
  type InterviewSession,
  type DesignTreeNode,
} from "./lib/grill-elicitation-core";

export default function (pi: ExtensionAPI) {
  // In-memory active session per agent instance
  let activeSession: InterviewSession | null = null;

  const getRepoRoot = (ctx?: any): string => {
    return ctx?.cwd || process.cwd();
  };

  const getNextAdrNumber = (repoRoot: string): number => {
    const adrDir = path.join(repoRoot, "docs", "adr");
    if (!fs.existsSync(adrDir)) {
      return 1;
    }
    try {
      const files = fs.readdirSync(adrDir);
      let maxNum = 0;
      for (const file of files) {
        const match = file.match(/^ADR-(\d+)/i);
        if (match) {
          const num = parseInt(match[1], 10);
          if (!isNaN(num) && num > maxNum) {
            maxNum = num;
          }
        }
      }
      return maxNum + 1;
    } catch {
      return 1;
    }
  };

  const handleInterviewAction = async (args: any, ctx: any) => {
    const action = args.action || "status";
    const topic = args.topic || "System Architecture & Design";
    const repoRoot = getRepoRoot(ctx);

    if (action === "start") {
      const defaultTree = generateDefaultInterviewTree(topic);
      activeSession = createInterviewSession(topic, defaultTree);

      const nextQ = getNextPendingQuestion(activeSession);
      const isHeadless = !ctx?.hasUI;
      const headlessNotice = isHeadless
        ? "\n*(Headless mode active: recommended choices will be auto-selected if not explicitly provided)*"
        : "";

      return {
        content: [
          {
            type: "text",
            text: `🎯 Started Grill Interview Session for "${topic}" (ID: ${activeSession.id})\n` +
              `Total design decisions to clarify: ${activeSession.nodes.length}${headlessNotice}\n\n` +
              (nextQ ? formatQuestionPrompt(nextQ) : "No questions pending."),
          },
        ],
        details: {
          sessionId: activeSession.id,
          topic: activeSession.topic,
          status: activeSession.status,
          nextQuestionId: nextQ?.id,
        },
      };
    }

    if (!activeSession) {
      // Auto-initialize if not yet started
      const defaultTree = generateDefaultInterviewTree(topic);
      activeSession = createInterviewSession(topic, defaultTree);
    }

    if (action === "ask") {
      if (args.question) {
        const optionsList = Array.isArray(args.options) && args.options.length > 0
          ? args.options.map((opt: string, idx: number) => ({
              label: opt,
              description: `Option: ${opt}`,
              recommended: idx === (args.recommendedIndex ?? 0),
            }))
          : [
              { label: "Option A", description: "Default proposed path", recommended: true },
              { label: "Option B", description: "Alternative path", recommended: false },
            ];

        const node = addQuestionNode(activeSession, {
          level: 2,
          category: args.category || "Behavior & Edge Cases",
          question: args.question,
          options: optionsList,
          recommendedIndex: args.recommendedIndex ?? 0,
        });

        return {
          content: [
            {
              type: "text",
              text: `Added question node ${node.id}:\n\n` + formatQuestionPrompt(node),
            },
          ],
          details: { nodeId: node.id },
        };
      }

      const pending = getNextPendingQuestion(activeSession);
      if (!pending) {
        return {
          content: [
            {
              type: "text",
              text: `All ${activeSession.nodes.length} questions in session "${activeSession.topic}" have already been answered. Ready for ADR/CONTEXT synthesis.`,
            },
          ],
          details: { completed: true },
        };
      }

      return {
        content: [
          {
            type: "text",
            text: formatQuestionPrompt(pending),
          },
        ],
        details: { pendingNodeId: pending.id },
      };
    }

    if (action === "answer") {
      let targetNode: DesignTreeNode | null = null;
      if (args.nodeId) {
        targetNode = activeSession.nodes.find((n) => n.id === args.nodeId) || null;
      } else {
        targetNode = getNextPendingQuestion(activeSession);
      }

      if (!targetNode) {
        return {
          content: [
            {
              type: "text",
              text: `No pending question found to answer in session "${activeSession.topic}".`,
            },
          ],
          details: { status: activeSession.status },
        };
      }

      let chosen = args.selectedOption;

      // Handle interactive UI when available and no option selected
      if (!chosen && ctx?.hasUI && ctx?.ui?.select) {
        try {
          const optLabels = targetNode.options.map(
            (o, i) => `${o.label}${i === targetNode.recommendedIndex ? " [Recommended]" : ""}: ${o.description}`
          );
          const sel = await ctx.ui.select(`[Grill] ${targetNode.question}`, optLabels);
          if (sel) {
            const matched = targetNode.options.find((o) => sel.startsWith(o.label));
            chosen = matched ? matched.label : sel;
          }
        } catch {
          // Fall back to recommended
        }
      }

      // Headless / non-interactive safe default: auto-select recommended option
      if (!chosen) {
        const rec = targetNode.options[targetNode.recommendedIndex] || targetNode.options[0];
        chosen = rec?.label || "Default Choice";
      }

      recordAnswer(activeSession, targetNode.id, chosen);

      const nextPending = getNextPendingQuestion(activeSession);
      let responseText = `✅ Recorded answer for **${targetNode.id}** (${targetNode.category}): **${chosen}**\n\n`;

      if (nextPending) {
        responseText += `Proceeding to next question:\n\n` + formatQuestionPrompt(nextPending);
      } else {
        responseText += `🎉 All design questions have been resolved! Session status: **COMPLETED**.\n` +
          `Run action: 'generate_adr' or 'synthesize_context' to persist the architectural contract.`;
      }

      return {
        content: [{ type: "text", text: responseText }],
        details: {
          answeredNodeId: targetNode.id,
          selected: chosen,
          isCompleted: activeSession.status === "completed",
        },
      };
    }

    if (action === "generate_adr") {
      const nextNum = getNextAdrNumber(repoRoot);
      const adr = generateADR(activeSession, nextNum);

      // Persist ADR file to docs/adr/
      const fullPath = path.join(repoRoot, adr.filename);
      const adrDir = path.dirname(fullPath);
      try {
        if (!fs.existsSync(adrDir)) {
          fs.mkdirSync(adrDir, { recursive: true });
        }
        fs.writeFileSync(fullPath, adr.content, "utf-8");
      } catch (err: any) {
        return {
          content: [
            {
              type: "text",
              text: `Generated ADR (failed to write to ${fullPath}: ${err?.message || err}):\n\n${adr.content}`,
            },
          ],
          details: { error: String(err), content: adr.content },
        };
      }

      return {
        content: [
          {
            type: "text",
            text: `📝 Successfully synthesized Architecture Decision Record:\n` +
              `• File: \`${adr.filename}\`\n\n` +
              adr.content,
          },
        ],
        details: {
          filename: adr.filename,
          fullPath,
          adrNumber: nextNum,
        },
      };
    }

    if (action === "synthesize_context") {
      const contextPath = path.join(repoRoot, "CONTEXT.md");
      let existingContext: string | undefined;
      try {
        if (fs.existsSync(contextPath)) {
          existingContext = fs.readFileSync(contextPath, "utf-8");
        }
      } catch {
        // ignore
      }

      const synthesized = synthesizeContext(activeSession, existingContext);

      try {
        fs.writeFileSync(contextPath, synthesized, "utf-8");
      } catch (err: any) {
        return {
          content: [
            {
              type: "text",
              text: `Synthesized CONTEXT.md (failed to write to ${contextPath}: ${err?.message || err}):\n\n${synthesized}`,
            },
          ],
          details: { error: String(err), content: synthesized },
        };
      }

      return {
        content: [
          {
            type: "text",
            text: `📘 Successfully synthesized Domain Invariants into \`CONTEXT.md\`:\n\n${synthesized}`,
          },
        ],
        details: {
          path: "CONTEXT.md",
          fullPath: contextPath,
        },
      };
    }

    // Default: status
    const statusReport = formatStatusReport(activeSession);
    return {
      content: [{ type: "text", text: statusReport }],
      details: {
        sessionId: activeSession.id,
        status: activeSession.status,
        nodesCount: activeSession.nodes.length,
      },
    };
  };

  // --------------------------------------------------------------------------
  // Tool Registration: grill_interview
  // --------------------------------------------------------------------------
  pi.registerTool({
    name: "grill_interview",
    label: "Interactive Design Elicitation",
    description:
      "Interactive design-tree interview for clarifying ambiguities, agreeing on architectural decisions, and synthesizing ADR and CONTEXT.md invariants.",
    parameters: Type.Object({
      action: Type.Union([
        Type.Literal("start"),
        Type.Literal("ask"),
        Type.Literal("answer"),
        Type.Literal("generate_adr"),
        Type.Literal("synthesize_context"),
        Type.Literal("status"),
      ]),
      topic: Type.Optional(Type.String({ description: "Topic or feature title for the design interview" })),
      question: Type.Optional(Type.String({ description: "Custom question text to add to the decision tree" })),
      category: Type.Optional(
        Type.String({ description: "Question category: Architecture & Boundaries, Behavior & Edge Cases, Consistency & Compatibility, Implementation & Tests" })
      ),
      options: Type.Optional(Type.Array(Type.String(), { description: "Options for the question" })),
      recommendedIndex: Type.Optional(Type.Integer({ description: "0-based index of recommended option" })),
      selectedOption: Type.Optional(Type.String({ description: "Chosen answer or option label" })),
      nodeId: Type.Optional(Type.String({ description: "Target question node ID (e.g. q1)" })),
    }),
    handler: async (args: any, ctx: any) => {
      return handleInterviewAction(args, ctx);
    },
    execute: async (_toolCallId: string, params: any, _signal: any, _onUpdate: any, ctx: any) => {
      return handleInterviewAction(params, ctx);
    },
  });

  // --------------------------------------------------------------------------
  // Slash Command: /grill
  // --------------------------------------------------------------------------
  pi.registerCommand("grill", {
    description: "Design-tree interview and ADR/CONTEXT.md synthesis (/grill [topic | adr list | adr generate | synthesize | status])",
    handler: async (args, ctx) => {
      const trimmed = (args || "").trim();
      const parts = trimmed.split(/\s+/);
      const subCommand = parts[0]?.toLowerCase();

      if (subCommand === "status") {
        const res = await handleInterviewAction({ action: "status" }, ctx);
        const text = res.content?.[0]?.text || "No status";
        if (ctx?.ui?.notify) ctx.ui.notify(text, "info");
        return;
      }

      if (subCommand === "adr") {
        const subAction = parts[1]?.toLowerCase() || "generate";
        if (subAction === "list") {
          const adrDir = path.join(getRepoRoot(ctx), "docs", "adr");
          if (!fs.existsSync(adrDir)) {
            if (ctx?.ui?.notify) ctx.ui.notify("No ADRs found in docs/adr/", "warning");
            return;
          }
          const files = fs.readdirSync(adrDir).filter((f) => f.endsWith(".md"));
          const listText = `📋 ADR Records (${files.length} found):\n` + files.map((f) => `• docs/adr/${f}`).join("\n");
          if (ctx?.ui?.notify) ctx.ui.notify(listText, "info");
          return;
        }

        const res = await handleInterviewAction({ action: "generate_adr" }, ctx);
        const text = res.content?.[0]?.text || "ADR generated";
        if (ctx?.ui?.notify) ctx.ui.notify(text, "info");
        return;
      }

      if (subCommand === "synthesize") {
        const res = await handleInterviewAction({ action: "synthesize_context" }, ctx);
        const text = res.content?.[0]?.text || "CONTEXT.md synthesized";
        if (ctx?.ui?.notify) ctx.ui.notify(text, "info");
        return;
      }

      // Default: start or continue interview
      const topic = trimmed || "System Design & Boundaries";
      const res = await handleInterviewAction({ action: activeSession ? "ask" : "start", topic }, ctx);
      const text = res.content?.[0]?.text || "Interview updated";
      if (ctx?.ui?.notify) ctx.ui.notify(text, "info");
    },
  });
}
