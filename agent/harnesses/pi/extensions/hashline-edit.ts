/**
 * Self-hosted Hashline Edit Extension for Pi 1.7.0
 *
 * - Annotates `read` tool results with `[PATH#TAG]` and `N#XXXX|` line anchors.
 * - Overrides built-in `edit` tool with tag-verified hashline edits + exact-string fallback.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import {
  CasUndoStore,
  annotateFileWithHashlines,
  applyEditToContent,
  createHashlineState,
  unwrapHashlinePath,
  type HashlineInput,
} from "./lib/hashline-core";

export * from "./lib/hashline-core";

const HashlineEditOpSchema = Type.Object({
  anchor: Type.String({ description: "Line anchor '<line>#<4-hex>' from read output" }),
  end_anchor: Type.Optional(Type.String({ description: "Optional inclusive end anchor '<line>#<4-hex>'" })),
  op: Type.Optional(Type.Union([Type.Literal("replace"), Type.Literal("insert_after"), Type.Literal("delete")])),
  content: Type.Optional(Type.String({ description: "Replacement or inserted lines" })),
});

const EditParamsSchema = Type.Object({
  path: Type.String({ description: "Path to the file to edit" }),
  file_tag: Type.Optional(Type.String({ description: "Optional 4-hex file snapshot tag from [path#TAG]" })),
  edits: Type.Optional(Type.Array(HashlineEditOpSchema, { description: "Hashline-anchored edit operations" })),
  oldText: Type.Optional(Type.String({ description: "Fallback exact text to replace" })),
  newText: Type.Optional(Type.String({ description: "Fallback replacement text" })),
});

export default function (pi: ExtensionAPI) {
  const state = createHashlineState();
  const undoStore = new CasUndoStore(32);

  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "read" || event.isError) return;
    const rawPath = (event.input as { path?: unknown } | undefined)?.path;
    if (typeof rawPath !== "string" || !rawPath) return;
    const clean = unwrapHashlinePath(rawPath);
    const abs = path.isAbsolute(clean) ? clean : path.resolve(ctx.cwd, clean);
    const offsetRaw = (event.input as { offset?: unknown } | undefined)?.offset;
    const offset = typeof offsetRaw === "number" && offsetRaw >= 1 ? Math.floor(offsetRaw) : 1;

    const firstText = event.content.find((c): c is { type: "text"; text: string } => c.type === "text");
    if (!firstText) return;
    // Skip if already annotated or binary/image placeholder.
    if (/^\[[^\]]+#[0-9a-f]{4}\]\n/i.test(firstText.text)) return;

    const { text } = annotateFileWithHashlines(rawPath, firstText.text, state, offset);
    // Keep exact absolute path seen too.
    annotateFileWithHashlines(abs, firstText.text, state, offset);
    return {
      content: event.content.map((c) => (c === firstText ? { type: "text" as const, text } : c)),
    };
  });

  pi.registerTool({
    name: "edit",
    label: "Edit (Hashline)",
    description:
      "Edit a file using hashline anchors (`edits`: `[{anchor:'12#a3f1', op:'replace'|'insert_after'|'delete', content:'...'}]`) or exact-text fallback (`oldText`/`newText`).",
    promptSnippet: "Edit an existing file using hashline anchors from read output or exact oldText/newText replacement.",
    parameters: EditParamsSchema,
    prepareArguments(args: unknown) {
      if (!args || typeof args !== "object") return args as HashlineInput;
      const a = args as Record<string, unknown>;
      return {
        ...a,
        path: typeof a.path === "string" ? a.path : typeof a.file_path === "string" ? a.file_path : "",
        oldText: typeof a.oldText === "string" ? a.oldText : typeof a.old_string === "string" ? a.old_string : undefined,
        newText: typeof a.newText === "string" ? a.newText : typeof a.new_string === "string" ? a.new_string : undefined,
      } as HashlineInput;
    },
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const cleanPath = unwrapHashlinePath(params.path);
      const absPath = path.isAbsolute(cleanPath) ? cleanPath : path.resolve(ctx.cwd, cleanPath);
      if (!fs.existsSync(absPath)) {
        return {
          content: [{ type: "text", text: `File not found: ${cleanPath}` }],
          isError: true,
        };
      }
      const current = fs.readFileSync(absPath, "utf-8");
      try {
        const res = applyEditToContent(absPath, current, params, state);
        if (res.changed) {
          undoStore.push(absPath, current);
          fs.writeFileSync(absPath, res.nextContent, "utf-8");
        }
        return {
          content: [{ type: "text", text: res.diffPreview }],
          details: { path: cleanPath, changed: res.changed, snapshotTag: res.snapshotTag },
        };
      } catch (err) {
        return {
          content: [{ type: "text", text: err instanceof Error ? err.message : String(err) }],
          isError: true,
        };
      }
    },
    renderCall(args, theme) {
      const count = Array.isArray(args.edits) ? `${args.edits.length} hashline op(s)` : "exact replace";
      return new Text(theme.fg("toolTitle", theme.bold("edit ")) + theme.fg("accent", args.path) + theme.fg("dim", ` (${count})`), 0, 0);
    },
    renderResult(result, { expanded }, theme) {
      const container = new Container();
      const text = result.content[0]?.type === "text" ? result.content[0].text : "";
      const preview = expanded ? text : text.split("\n").slice(0, 8).join("\n");
      container.addChild(new Text(result.isError ? theme.fg("error", preview) : theme.fg("toolOutput", preview), 0, 0));
      return container;
    },
  });

  pi.registerCommand("edit-undo", {
    description: "Rollback the last hashline edit via bounded CAS snapshot store (/edit-undo [path])",
    handler: async (args, ctx) => {
      const raw = (args || "").trim();
      const targetPath = raw ? (path.isAbsolute(raw) ? raw : path.resolve(ctx.cwd, raw)) : undefined;
      const entry = undoStore.pop(targetPath);
      if (!entry) {
        ctx.ui.notify(targetPath ? `No CAS undo snapshot for ${raw}` : "CAS undo stack is empty.", "warning");
        return;
      }
      fs.writeFileSync(entry.absPath, entry.content, "utf-8");
      ctx.ui.notify(`Restored ${entry.absPath} from CAS snapshot ${entry.digest} (${undoStore.list().length} remaining).`, "info");
    },
  });
}
