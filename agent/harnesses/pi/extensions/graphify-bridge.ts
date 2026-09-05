/**
 * Graphify Knowledge Graph Bridge Extension for Pi Coding Agent
 *
 * Exposes first-class tools for semantic graph queries:
 * - graphify_query: Search the committed knowledge graph for relevant concepts, god nodes, and communities.
 * - graphify_path: Trace relationship paths between two code entities (functions, files, modules).
 * - graphify_explain: Retrieve focused details and community context for a specific concept.
 *
 * Falls back to directly parsing .claude/graph/graphify/graph.json if graphify CLI is not in PATH.
 */

import { execSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

export interface GraphNode {
  id: string;
  label?: string;
  type?: string;
  community?: number | string;
  degree?: number;
  file?: string;
}

export interface GraphEdge {
  source: string;
  target: string;
  relation?: string;
}

export interface GraphData {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

/**
 * Locate the graph.json file in cwd or known standard directories.
 */
export function findGraphFile(cwd: string): string | null {
  const candidates = [
    process.env.GRAPHIFY_OUT ? path.join(process.env.GRAPHIFY_OUT, "graph.json") : null,
    path.join(cwd, ".claude", "graph", "graphify", "graph.json"),
    path.join(cwd, "graph.json"),
    path.join(cwd, "..", ".claude", "graph", "graphify", "graph.json"),
  ].filter(Boolean) as string[];

  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

/**
 * Execute graphify CLI command if available, otherwise return null.
 */
function tryGraphifyCli(subcommand: string, args: string[], cwd: string): string | null {
  try {
    const cmd = `graphify ${subcommand} ${args.map(a => `"${a.replace(/"/g, '\\"')}"`).join(" ")}`;
    const out = execSync(cmd, {
      cwd,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 5000,
    });
    return out.trim();
  } catch {
    return null;
  }
}

/**
 * Perform semantic search on the knowledge graph.
 */
export function queryGraph(query: string, cwd: string): { nodes: GraphNode[]; edges: GraphEdge[]; summary: string } {
  const cliOutput = tryGraphifyCli("query", [query], cwd);
  if (cliOutput) {
    return {
      nodes: [],
      edges: [],
      summary: cliOutput,
    };
  }

  const graphPath = findGraphFile(cwd);
  if (!graphPath) {
    return {
      nodes: [],
      edges: [],
      summary: `Knowledge graph not found. Run 'graphify update .' to create one.`,
    };
  }

  try {
    const content = fs.readFileSync(graphPath, "utf-8");
    const data: GraphData = JSON.parse(content);
    const q = query.toLowerCase();

    // Match nodes by id, label, or file
    const matchedNodes = (data.nodes || []).filter(n => {
      const id = (n.id || "").toLowerCase();
      const label = (n.label || "").toLowerCase();
      const file = (n.file || "").toLowerCase();
      return id.includes(q) || label.includes(q) || file.includes(q);
    }).slice(0, 20);

    const matchedIds = new Set(matchedNodes.map(n => n.id));
    const matchedEdges = (data.edges || []).filter(e => matchedIds.has(e.source) || matchedIds.has(e.target)).slice(0, 30);

    let summary = `Found ${matchedNodes.length} nodes matching '${query}':\n`;
    for (const n of matchedNodes) {
      summary += `- ${n.id} (${n.type || "node"}, community: ${n.community ?? "N/A"})\n`;
    }

    return {
      nodes: matchedNodes,
      edges: matchedEdges,
      summary: summary.trim(),
    };
  } catch (err: any) {
    return {
      nodes: [],
      edges: [],
      summary: `Failed to query graph: ${err.message}`,
    };
  }
}

/**
 * Explain a concept or find its neighborhood in the knowledge graph.
 */
export function explainConcept(concept: string, cwd: string): { found: boolean; details: string } {
  const cliOutput = tryGraphifyCli("explain", [concept], cwd);
  if (cliOutput) {
    return { found: true, details: cliOutput };
  }

  const graphPath = findGraphFile(cwd);
  if (!graphPath) {
    return { found: false, details: "graph.json not found" };
  }

  try {
    const content = fs.readFileSync(graphPath, "utf-8");
    const data: GraphData = JSON.parse(content);
    const c = concept.toLowerCase();

    const node = (data.nodes || []).find(n => (n.id || "").toLowerCase() === c || (n.label || "").toLowerCase() === c);
    if (!node) {
      return { found: false, details: `Concept '${concept}' not found in knowledge graph.` };
    }

    const relations = (data.edges || []).filter(e => e.source === node.id || e.target === node.id);
    let details = `Concept: ${node.id}\nType: ${node.type || "unknown"}\nCommunity: ${node.community ?? "N/A"}\nConnected Edges (${relations.length}):\n`;
    for (const r of relations.slice(0, 15)) {
      details += `  - ${r.source} -> ${r.target} [${r.relation || "relates"}]\n`;
    }

    return { found: true, details: details.trim() };
  } catch (err: any) {
    return { found: false, details: `Error: ${err.message}` };
  }
}

export default function (pi: ExtensionAPI) {
  // Register graphify_query tool
  pi.registerTool({
    name: "graphify_query",
    description: "Search the knowledge graph (.claude/graph/graphify/graph.json) for code entities, god nodes, and communities before running broad grep operations.",
    parameters: Type.Object({
      query: Type.String({ description: "Entity name, concept, or architectural term to search for." }),
    }),
    handler: async (args, ctx) => {
      const result = queryGraph(args.query, ctx.cwd);
      return {
        content: [{ type: "text", text: result.summary }],
      };
    },
  });

  // Register graphify_explain tool
  pi.registerTool({
    name: "graphify_explain",
    description: "Get detailed relationship neighborhood and community metadata for a specific concept or node in the knowledge graph.",
    parameters: Type.Object({
      concept: Type.String({ description: "Concept or node ID to explain." }),
    }),
    handler: async (args, ctx) => {
      const result = explainConcept(args.concept, ctx.cwd);
      return {
        content: [{ type: "text", text: result.details }],
      };
    },
  });
}
