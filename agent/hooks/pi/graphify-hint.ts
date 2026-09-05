/**
 * Graphify Knowledge Graph Extension for Pi Coding Agent
 *
 * Detects wide grep / find operations on repositories containing
 * a committed knowledge graph (.claude/graph/graphify/graph.json)
 * and hints semantic graph queries for faster, token-efficient navigation.
 *
 * 検出パターン・グラフパス候補・ヒント文言は agent/graphify-hint-config.json (claude/agy/pi 共通) を
 * 読む。判定アルゴリズム自体は agent/scripts/hooks/rule_engine.py + decide.py へ統合済み
 * (2026-09-03、claude/agy/piで3回独立に再実装されていたロジックを1箇所化)。本ファイルは
 * Pi Extension APIとの結線(ctx.ui.setStatus)のみを持つ薄いシム。
 */

import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { callDecide, repoRoot } from "./lib/shared";

function evaluateGraphifyHint(root: string, cwd: string, command: string): string | null {
  const result = callDecide<{ hint?: string }>(
    root,
    {
      family: "graphify_hint",
      command,
      config_file: path.join(root, "agent", "graphify-hint-config.json"),
      search_bases: [cwd],
    },
    {},
  );
  return result.hint ?? null;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return;

    const command = (event.input.command as string) || "";
    if (!command) return;

    const root = repoRoot(import.meta.url);
    if (!root) return;

    const hint = evaluateGraphifyHint(root, ctx.cwd, command);
    if (hint) {
      ctx.ui.setStatus("graphify", `💡 ${hint}`);
    }
  });
}
