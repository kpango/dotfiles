/**
 * Subagent Orchestration Extension for Pi Coding Agent
 *
 * Discovers specialized agents defined in ~/.pi/agent/agents/*.md and .pi/agents/*.md,
 * and enables single, parallel, and sequential chain delegation with isolated contexts.
 */

import { spawn } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Markdown, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { allocateWorktree, releaseWorktree, collectWorktreeDiff } from "./worktree-manager";

export interface AgentConfig {
  name: string;
  description: string;
  tools?: string[];
  model?: string;
  systemPrompt: string;
  source: "user" | "project";
  filePath: string;
}

export type AgentCategory = "coding" | "research" | "benchmark" | "testing" | "debugging" | "review" | "general";

export const CATEGORY_CONCURRENCY_LIMITS: Record<AgentCategory, number> = {
  coding: 16,
  research: 100,
  benchmark: 4,
  testing: 50,
  debugging: 4,
  review: 16,
  general: 8,
};

export const MAX_PARALLEL_TASKS = 100;
export const DEFAULT_CONCURRENCY = 8;
export const PER_TASK_OUTPUT_CAP = 64 * 1024;

export function inferTaskCategory(agentName: string, taskText = ""): AgentCategory {
  const normAgent = agentName.toLowerCase();
  const normTask = taskText.toLowerCase();

  // 1. Benchmark (CPU-intensive / timing sensitive) -> 4
  if (
    normAgent.includes("perf") ||
    normAgent.includes("benchmark") ||
    normTask.includes("benchmark") ||
    normTask.includes("criterion") ||
    normTask.includes("pprof")
  ) {
    return "benchmark";
  }

  // 2. Debugging (Trace / interactive / heavy log collection) -> 4
  if (
    normAgent.includes("debugger") ||
    normAgent.includes("ci-investigator") ||
    normTask.includes("debug") ||
    normTask.includes("root-cause") ||
    normTask.includes("trace")
  ) {
    return "debugging";
  }

  // 3. Testing (Test execution / test authoring) -> 50
  if (
    normAgent.includes("test_writer") ||
    normAgent.includes("test") ||
    normTask.includes("unit test") ||
    normTask.includes("go test") ||
    normTask.includes("cargo test") ||
    normTask.includes("pytest") ||
    normTask.includes("run test")
  ) {
    return "testing";
  }

  // 4. Coding (Implementation / Refactor / Surgical edits) -> 16
  if (
    normAgent.endsWith("-expert") ||
    normAgent.includes("worker") ||
    normTask.includes("implement") ||
    normTask.includes("refactor") ||
    normTask.includes("edit") ||
    normTask.includes("write code")
  ) {
    return "coding";
  }

  // 5. Research (Wide search / Read-only survey / Log analysis) -> 100
  if (
    normAgent.includes("research") ||
    normAgent.includes("explorer") ||
    normAgent.includes("explore") ||
    normAgent.includes("spec_miner") ||
    normTask.includes("survey") ||
    normTask.includes("search") ||
    normTask.includes("research") ||
    normTask.includes("explore")
  ) {
    return "research";
  }

  // 6. Review (Adversarial / Code review / Invariant audit) -> 16
  if (
    normAgent.includes("reviewer") ||
    normAgent.includes("challenger") ||
    normAgent.includes("auditor") ||
    normAgent.includes("audit") ||
    normTask.includes("review")
  ) {
    return "review";
  }

  return "general";
}

export function calculateEffectiveConcurrency(tasks: Array<{ agent: string; task: string }>): number {
  if (!tasks || tasks.length === 0) return DEFAULT_CONCURRENCY;
  const categories = tasks.map((t) => inferTaskCategory(t.agent, t.task));
  const uniqueCats = Array.from(new Set(categories));
  if (uniqueCats.length === 1) {
    return CATEGORY_CONCURRENCY_LIMITS[uniqueCats[0]] || DEFAULT_CONCURRENCY;
  }
  const limits = uniqueCats.map((c) => CATEGORY_CONCURRENCY_LIMITS[c] || DEFAULT_CONCURRENCY);
  return Math.min(...limits);
}

export async function runTasksInParallelPool<T, R>(
  items: T[],
  concurrency: number,
  worker: (item: T, index: number) => Promise<R>,
  onItemProgress?: (completed: number, total: number, itemResult: R) => void
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let nextIndex = 0;
  let completedCount = 0;

  const poolSize = Math.max(1, Math.min(concurrency, items.length));
  const workers = Array.from({ length: poolSize }, async () => {
    while (nextIndex < items.length) {
      const idx = nextIndex++;
      const res = await worker(items[idx], idx);
      results[idx] = res;
      completedCount++;
      if (onItemProgress) {
        onItemProgress(completedCount, items.length, res);
      }
    }
  });

  await Promise.all(workers);
  return results;
}

/**
 * `agent/agents/*.md`(Claude Code式 PascalCase, 例: "Read, Write, Bash, Glob")の `tools:` を
 * pi-coding-agent の `--tools` フラグが要求する語彙(小文字・完全一致 Set.has()、`Glob` という
 * 概念は無く find/ls の2トークン)へ変換する。
 *
 * 2026-09-03以前は `agent/scripts/gen-pi-agents.sh`(廃止済み)がビルド時に `agent/agents/*.md` を
 * `pi/agents/*.md` へ変換・実体コピーしていたが、agent-hooks-and-pi-agents-unification ミッションで
 * `~/.pi/agent/agents` のsymlink先を `agent/agents` へ直接向けるよう変更したため、この変換を
 * ビルド時ではなく実行時(本関数)で行う。マッピング内容は旧 gen-pi-agents.sh の `MAPPING` 定数と
 * 完全に同一(agent/scripts/gen-pi-agents.sh の git 履歴参照)。
 */
const TOOL_NAME_MAPPING: Record<string, string[]> = {
  Read: ["read"],
  Write: ["write"],
  Edit: ["edit"],
  Bash: ["bash"],
  Grep: ["grep"],
  Glob: ["find", "ls"],
  Agent: ["agent"],
  Workflow: ["workflow"],
  Skill: ["skill"],
};

export function mapToolNames(rawTools: string | string[]): string[] {
  const tokens = Array.isArray(rawTools)
    ? rawTools.map((t) => t.trim()).filter((t) => t.length > 0)
    : rawTools
        .split(",")
        .map((t) => t.trim())
        .filter((t) => t.length > 0);
  const mapped: string[] = [];
  for (const t of tokens) {
    mapped.push(...(TOOL_NAME_MAPPING[t] ?? [t.toLowerCase()]));
  }
  return mapped;
}

function parseFrontmatter(content: string): { frontmatter: Record<string, any>; body: string } {
  const match = content.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!match) return { frontmatter: {}, body: content };
  const rawFm = match[1];
  const body = match[2];
  const frontmatter: Record<string, any> = {};

  for (const line of rawFm.split("\n")) {
    const colonIdx = line.indexOf(":");
    if (colonIdx === -1) continue;
    const key = line.slice(0, colonIdx).trim();
    let value: any = line.slice(colonIdx + 1).trim();
    if (value.startsWith("[") && value.endsWith("]")) {
      value = value.slice(1, -1).split(",").map((s: string) => s.trim().replace(/^['"]|['"]$/g, ""));
    } else if (value.toLowerCase() === "true") value = true;
    else if (value.toLowerCase() === "false") value = false;
    frontmatter[key] = value;
  }
  return { frontmatter, body };
}

function findRepoRoot(): string {
  let dir = __dirname;
  while (dir !== "/" && dir !== ".") {
    if (fs.existsSync(path.join(dir, ".git"))) {
      return dir;
    }
    dir = path.dirname(dir);
  }
  return os.homedir();
}

export interface ModelResolutionContext {
  tools?: string[];
  task?: string;
  prompt?: string;
  type?: "code_research" | "web_research" | string;
  trigger?: "rate_limit" | "token_exhaustion" | "cost_saver" | "context_overflow" | string;
  fallbackIndex?: number;
}

export function resolveModelTier(
  modelStr: string | undefined,
  context?: ModelResolutionContext
): string | undefined {
  if (!modelStr || modelStr.toLowerCase() === "inherit") return undefined;

  let cleanTier = modelStr;
  let subRoute: "code_research" | "web_research" | undefined;

  // 1. Explicit sub-tier suffix (e.g. Low-Code, Low:Code, Low_Code, Low-Web, Low:Web)
  for (const sep of ["-", ":", "_"]) {
    if (modelStr.includes(sep)) {
      const parts = modelStr.split(sep);
      const base = parts[0];
      const sub = parts.slice(1).join(sep).toLowerCase();
      if (["low", "medium", "high", "xhigh", "max"].includes(base.toLowerCase())) {
        cleanTier = base;
        if (sub === "code" || sub === "code_research" || sub === "coderesearch") {
          subRoute = "code_research";
        } else if (sub === "web" || sub === "web_research" || sub === "webresearch") {
          subRoute = "web_research";
        }
        break;
      }
    }
  }

  // 2. Dynamic sub-route inference for Low tier based on context (tools / prompt / task)
  if (!subRoute && cleanTier.toLowerCase() === "low" && context) {
    if (context.type === "code_research" || context.type === "code") {
      subRoute = "code_research";
    } else if (context.type === "web_research" || context.type === "web") {
      subRoute = "web_research";
    } else {
      const tools = context.tools?.map((t) => t.toLowerCase()) || [];
      const text = `${context.task || ""} ${context.prompt || ""}`.toLowerCase();

      const hasWebTool = tools.some(
        (t) => t.includes("fetch") || t.includes("web") || t.includes("curl") || t.includes("url")
      );
      const hasWebKeyword =
        text.includes("web") ||
        text.includes("url") ||
        text.includes("http") ||
        text.includes("rfc") ||
        text.includes("doc") ||
        text.includes("paper") ||
        text.includes("research");

      const hasCodeTool = tools.some((t) =>
        ["read", "write", "edit", "grep", "find", "ls", "bash"].includes(t)
      );
      const hasCodeKeyword =
        text.includes("shard") ||
        text.includes("codebase") ||
        text.includes("grep") ||
        text.includes("ast") ||
        text.includes("lint") ||
        text.includes("scan") ||
        text.includes("survey");

      if (hasWebTool || (hasWebKeyword && !hasCodeKeyword)) {
        subRoute = "web_research";
      } else if (hasCodeTool || hasCodeKeyword) {
        subRoute = "code_research";
      }
    }
  }

  const normalizedTier = ["Low", "Medium", "High", "XHigh", "Max"].find(
    (t) => t.toLowerCase() === cleanTier.toLowerCase()
  );
  if (!normalizedTier) {
    return modelStr;
  }

  const routingPaths = [
    path.join(os.homedir(), ".pi", "agent", "model-routing.json"),
    path.join(findRepoRoot(), "agent", "harnesses", "pi", "model-routing.json"),
  ];
  for (const p of routingPaths) {
    if (fs.existsSync(p)) {
      try {
        const raw = fs.readFileSync(p, "utf-8");
        const parsed = JSON.parse(raw);
        if (parsed.tiers && parsed.tiers[normalizedTier]) {
          const tierCfg = parsed.tiers[normalizedTier];
          if (subRoute && tierCfg.sub_routes?.[subRoute]?.model) {
            return tierCfg.sub_routes[subRoute].model;
          }

          // Intelligent Model Routing: fallback resolution for token limit / rate limit / cost
          const fallbacks = tierCfg.fallbacks as Array<{ model: string; trigger?: string }> | undefined;
          if (fallbacks && fallbacks.length > 0) {
            if (
              context?.fallbackIndex !== undefined &&
              context.fallbackIndex >= 0 &&
              context.fallbackIndex < fallbacks.length
            ) {
              return fallbacks[context.fallbackIndex].model;
            }
            if (context?.trigger) {
              const matched = fallbacks.find((f) => f.trigger === context.trigger);
              if (matched?.model) {
                return matched.model;
              }
            }
          }

          if (tierCfg.model) {
            return tierCfg.model;
          }
        }
      } catch {
        // ignore parse error and try next
      }
    }
  }
  return modelStr;
}

export function loadAgentsFromDirForTest(dir: string, source: "user" | "project"): AgentConfig[] {
  return loadAgentsFromDir(dir, source);
}

function loadAgentsFromDir(dir: string, source: "user" | "project"): AgentConfig[] {
  const agents: AgentConfig[] = [];
  if (!fs.existsSync(dir)) return agents;

  try {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isFile() || !entry.name.endsWith(".md")) continue;

      const filePath = path.join(dir, entry.name);
      try {
        const content = fs.readFileSync(filePath, "utf-8");
        const { frontmatter, body } = parseFrontmatter(content);
        const name = frontmatter.name || path.basename(entry.name, ".md");
        const description = frontmatter.description || "Specialized subagent";
        let tools: string[] | undefined;
        if (Array.isArray(frontmatter.tools) || typeof frontmatter.tools === "string") {
          tools = mapToolNames(frontmatter.tools);
        }

        agents.push({
          name,
          description,
          tools,
          model: resolveModelTier(frontmatter.model, {
            tools,
            prompt: `${description} ${body.trim()}`,
          }),
          systemPrompt: body.trim(),
          source,
          filePath,
        });
      } catch {
        // Skip unreadable files
      }
    }
  } catch {
    // Skip unreadable directories
  }
  return agents;
}

function discoverAgents(cwd: string): AgentConfig[] {
  const homeDir = os.homedir();
  const userAgentDir = path.join(homeDir, ".pi", "agent", "agents");
  const projectAgentDir = path.join(cwd, ".pi", "agents");

  const userAgents = loadAgentsFromDir(userAgentDir, "user");
  const projectAgents = loadAgentsFromDir(projectAgentDir, "project");

  const map = new Map<string, AgentConfig>();
  for (const a of userAgents) map.set(a.name, a);
  for (const a of projectAgents) map.set(a.name, a);
  return Array.from(map.values());
}

async function writePromptToTempFile(agentName: string, prompt: string): Promise<{ dir: string; filePath: string }> {
  const tmpDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), "pi-subagent-"));
  const safeName = agentName.replace(/[^\w.-]+/g, "_");
  const filePath = path.join(tmpDir, `prompt-${safeName}.md`);
  await fs.promises.writeFile(filePath, prompt, { encoding: "utf-8", mode: 0o600 });
  return { dir: tmpDir, filePath };
}

interface SingleResult {
  agent: string;
  agentSource: string;
  task: string;
  exitCode: number;
  stdout: string;
  stderr: string;
  model?: string;
  step?: number;
}

interface SubagentDetails {
  mode: "single" | "parallel" | "chain";
  results: SingleResult[];
}

async function runSingleAgent(
  defaultCwd: string,
  agents: AgentConfig[],
  agentName: string,
  task: string,
  targetCwd?: string,
  step?: number,
  signal?: AbortSignal,
  onUpdate?: (partial: { content: Array<{ type: "text"; text: string }>; details: SubagentDetails }) => void,
  makeDetails?: (results: SingleResult[]) => SubagentDetails
): Promise<SingleResult> {
  const agent = agents.find((a) => a.name === agentName);
  if (!agent) {
    const available = agents.map((a) => `"${a.name}"`).join(", ") || "none";
    return {
      agent: agentName,
      agentSource: "unknown",
      task,
      exitCode: 1,
      stdout: "",
      stderr: `Unknown agent: "${agentName}". Available agents: ${available}`,
      step,
    };
  }

  const args: string[] = ["-p", "--no-context-files"];
  if (agent.model) {
    args.push("--model", agent.model);
  }
  if (agent.tools && agent.tools.length > 0) {
    args.push("--tools", agent.tools.join(","));
  }

  let tmpDir: string | null = null;
  let tmpPromptFile: string | null = null;

  const currentResult: SingleResult = {
    agent: agentName,
    agentSource: agent.source,
    task,
    exitCode: 0,
    stdout: "",
    stderr: "",
    model: agent.model,
    step,
  };

  try {
    if (agent.systemPrompt) {
      const tmp = await writePromptToTempFile(agent.name, agent.systemPrompt);
      tmpDir = tmp.dir;
      tmpPromptFile = tmp.filePath;
      args.push("--prompt-template", tmpPromptFile);
    }

    args.push(task);

    let wasAborted = false;
    const exitCode = await new Promise<number>((resolve) => {
      const proc = spawn("pi", args, {
        cwd: targetCwd ?? defaultCwd,
        stdio: ["ignore", "pipe", "pipe"],
      });

      proc.stdout.on("data", (chunk) => {
        currentResult.stdout += chunk.toString();
        if (onUpdate && makeDetails) {
          onUpdate({
            content: [{ type: "text", text: currentResult.stdout || "(subagent executing...)" }],
            details: makeDetails([currentResult]),
          });
        }
      });

      proc.stderr.on("data", (chunk) => {
        currentResult.stderr += chunk.toString();
      });

      proc.on("close", (code) => {
        resolve(code ?? 0);
      });

      proc.on("error", () => {
        resolve(1);
      });

      if (signal) {
        const killProc = () => {
          wasAborted = true;
          proc.kill("SIGTERM");
          setTimeout(() => {
            if (!proc.killed) proc.kill("SIGKILL");
          }, 3000);
        };
        if (signal.aborted) killProc();
        else signal.addEventListener("abort", killProc, { once: true });
      }
    });

    currentResult.exitCode = exitCode;
    if (wasAborted) throw new Error("Subagent was aborted");
    return currentResult;
  } finally {
    if (tmpPromptFile) {
      try {
        fs.unlinkSync(tmpPromptFile);
      } catch {}
    }
    if (tmpDir) {
      try {
        fs.rmdirSync(tmpDir);
      } catch {}
    }
  }
}

const TaskItem = Type.Object({
  agent: Type.String({ description: "Name of the agent to invoke" }),
  task: Type.String({ description: "Task to delegate to the agent" }),
  cwd: Type.Optional(Type.String({ description: "Working directory for the subagent" })),
});

const ChainItem = Type.Object({
  agent: Type.String({ description: "Name of the agent to invoke" }),
  task: Type.String({ description: "Task with optional {previous} placeholder for prior output" }),
  cwd: Type.Optional(Type.String({ description: "Working directory for the subagent" })),
});

const SubagentParams = Type.Object({
  agent: Type.Optional(Type.String({ description: "Name of the agent to invoke (single mode)" })),
  task: Type.Optional(Type.String({ description: "Task to delegate (single mode)" })),
  tasks: Type.Optional(Type.Array(TaskItem, { description: "Array of {agent, task} for parallel execution" })),
  chain: Type.Optional(Type.Array(ChainItem, { description: "Array of {agent, task} for sequential execution" })),
  cwd: Type.Optional(Type.String({ description: "Working directory for the agent process" })),
});

export default function (pi: ExtensionAPI) {
  // Register Tool
  pi.registerTool({
    name: "subagent",
    label: "Subagent Delegation",
    description:
      "Delegate tasks to specialized agents (go-expert, rust-expert, arch-ops, security-audit, code-reviewer, etc.) in single, parallel, or sequential chain mode.",
    parameters: SubagentParams,

    async execute(_toolCallId, params, signal, onUpdate, ctx) {
      const agents = discoverAgents(ctx.cwd);
      const hasChain = (params.chain?.length ?? 0) > 0;
      const hasTasks = (params.tasks?.length ?? 0) > 0;
      const hasSingle = Boolean(params.agent && params.task);
      const modeCount = Number(hasChain) + Number(hasTasks) + Number(hasSingle);

      const makeDetails = (mode: "single" | "parallel" | "chain") => (results: SingleResult[]): SubagentDetails => ({
        mode,
        results,
      });

      if (modeCount !== 1) {
        const available = agents.map((a) => `${a.name} (${a.source})`).join(", ") || "none";
        return {
          content: [
            {
              type: "text",
              text: `Invalid parameters. Provide exactly one of 'agent'+'task', 'tasks', or 'chain'.\nAvailable agents: ${available}`,
            },
          ],
          details: makeDetails("single")([]),
        };
      }

      // Single Mode
      if (params.agent && params.task) {
        const result = await runSingleAgent(
          ctx.cwd,
          agents,
          params.agent,
          params.task,
          params.cwd,
          undefined,
          signal,
          onUpdate,
          makeDetails("single")
        );
        const isError = result.exitCode !== 0;
        const text = result.stdout.trim() || (isError ? result.stderr.trim() || "Agent failed." : "(no output)");
        return {
          content: [{ type: "text", text }],
          isError,
          details: makeDetails("single")([result]),
        };
      }

      // Chain Mode
      if (params.chain && params.chain.length > 0) {
        const results: SingleResult[] = [];
        let previousOutput = "";

        for (let i = 0; i < params.chain.length; i++) {
          const step = params.chain[i];
          const taskWithContext = step.task.replace(/\{previous\}/g, previousOutput);

          const result = await runSingleAgent(
            ctx.cwd,
            agents,
            step.agent,
            taskWithContext,
            step.cwd,
            i + 1,
            signal,
            (partial) => {
              if (onUpdate) {
                onUpdate({
                  content: partial.content,
                  details: makeDetails("chain")([...results, partial.details.results[0]]),
                });
              }
            },
            makeDetails("chain")
          );

          results.push(result);
          if (result.exitCode !== 0) {
            return {
              content: [
                {
                  type: "text",
                  text: `Chain failed at step ${i + 1} (${step.agent}):\n${result.stderr || result.stdout}`,
                },
              ],
              isError: true,
              details: makeDetails("chain")(results),
            };
          }
          previousOutput = result.stdout.trim();
        }

        return {
          content: [{ type: "text", text: previousOutput || "(chain complete with no output)" }],
          details: makeDetails("chain")(results),
        };
      }

      // Parallel Mode
      if (params.tasks && params.tasks.length > 0) {
        if (params.tasks.length > MAX_PARALLEL_TASKS) {
          return {
            content: [{ type: "text", text: `Too many parallel tasks (${params.tasks.length}). Max allowed is ${MAX_PARALLEL_TASKS}.` }],
            isError: true,
            details: makeDetails("parallel")([]),
          };
        }

        const effectiveConcurrency = calculateEffectiveConcurrency(params.tasks);
        const allResults = await runTasksInParallelPool(
          params.tasks,
          effectiveConcurrency,
          async (t, idx) => {
            let targetCwd = t.cwd;
            let allocatedWt: { worktreePath: string; branchName: string } | null = null;
            const category = inferTaskCategory(t.agent, t.task);

            // Automatically allocate isolated worktree for coding tasks if no cwd specified
            if (category === "coding" && !targetCwd) {
              const safeId = `subagent-${idx + 1}-${Date.now().toString(36)}`;
              const alloc = allocateWorktree(ctx.cwd, safeId);
              if (alloc.success) {
                targetCwd = alloc.worktreePath;
                allocatedWt = alloc;
              }
            }

            try {
              const res = await runSingleAgent(
                ctx.cwd,
                agents,
                t.agent,
                t.task,
                targetCwd,
                idx + 1,
                signal,
                undefined,
                makeDetails("parallel")
              );

              if (allocatedWt) {
                const diffData = collectWorktreeDiff(allocatedWt.worktreePath);
                if (diffData.files.length > 0) {
                  res.stdout += `\n\n[Worktree ${allocatedWt.branchName} modified: ${diffData.files.join(", ")}]`;
                }
              }

              return res;
            } finally {
              if (allocatedWt) {
                releaseWorktree(ctx.cwd, allocatedWt.worktreePath, allocatedWt.branchName);
              }
            }
          },
          (completed, total, latest) => {
            if (onUpdate) {
              onUpdate({
                content: [
                  {
                    type: "text",
                    text: `[Parallel Pool] Running with concurrency ${effectiveConcurrency} | Progress: ${completed}/${total} tasks completed (Latest: ${latest.agent} ${latest.exitCode === 0 ? "✓" : "✗"})`,
                  },
                ],
                details: makeDetails("parallel")([]),
              });
            }
          }
        );

        const successCount = allResults.filter((r) => r.exitCode === 0).length;
        const summaries = allResults.map((r) => {
          const out = r.stdout.trim() || r.stderr.trim() || "(no output)";
          return `### [${r.agent}] ${r.exitCode === 0 ? "✓ Success" : "✗ Failed"}\n\n${out}`;
        });

        return {
          content: [
            {
              type: "text",
              text: `Parallel (${effectiveConcurrency} concurrent): ${successCount}/${allResults.length} succeeded\n\n${summaries.join("\n\n---\n\n")}`,
            },
          ],
          details: makeDetails("parallel")(allResults),
        };
      }

      return {
        content: [{ type: "text", text: "No actions executed." }],
        details: makeDetails("single")([]),
      };
    },

    renderCall(args, theme) {
      if (args.chain) {
        return new Text(theme.fg("toolTitle", theme.bold("subagent ")) + theme.fg("accent", `chain (${args.chain.length} steps)`), 0, 0);
      }
      if (args.tasks) {
        return new Text(theme.fg("toolTitle", theme.bold("subagent ")) + theme.fg("accent", `parallel (${args.tasks.length} tasks)`), 0, 0);
      }
      return new Text(
        theme.fg("toolTitle", theme.bold("subagent ")) + theme.fg("accent", args.agent || "") + "\n  " + theme.fg("dim", args.task || ""),
        0,
        0
      );
    },

    renderResult(result, { expanded }, theme) {
      const details = result.details as SubagentDetails | undefined;
      const container = new Container();

      if (!details || details.results.length === 0) {
        const txt = result.content[0]?.type === "text" ? result.content[0].text : "(no output)";
        container.addChild(new Text(txt, 0, 0));
        return container;
      }

      for (const r of details.results) {
        const icon = r.exitCode === 0 ? theme.fg("success", "✓") : theme.fg("error", "✗");
        const header = `${icon} ${theme.bold(r.agent)} (${r.agentSource})${r.model ? theme.fg("muted", ` [${r.model}]`) : ""}`;
        container.addChild(new Text(header, 0, 0));

        const bodyText = r.stdout.trim() || r.stderr.trim() || "(no output)";
        if (expanded || r.exitCode !== 0) {
          container.addChild(new Text(theme.fg("toolOutput", bodyText), 0, 0));
        } else {
          const preview = bodyText.split("\n").slice(0, 4).join("\n");
          container.addChild(new Text(theme.fg("toolOutput", preview), 0, 0));
        }
      }
      return container;
    },
  });

  // Slash Command /subagents (list all agents)
  pi.registerCommand("subagents", {
    description: "List all available specialized subagents",
    handler: async (_args, ctx) => {
      const agents = discoverAgents(ctx.cwd);
      if (agents.length === 0) {
        ctx.ui.notify("No specialized subagents found in ~/.pi/agent/agents or .pi/agents", "warning");
        return;
      }

      let msg = `Available Subagents (${agents.length}):\n`;
      for (const a of agents) {
        msg += `\n• ${a.name} [${a.source}]: ${a.description.slice(0, 80)}...`;
      }
      ctx.ui.notify(msg, "info");
    },
  });

  // Slash Command /agent <name> <task>
  pi.registerCommand("agent", {
    description: "Delegate a task to a specific subagent (/agent <name> <task>)",
    handler: async (args, ctx) => {
      if (!args || !args.trim()) {
        ctx.ui.notify("Usage: /agent <name> <task>", "warning");
        return;
      }
      const spaceIdx = args.indexOf(" ");
      if (spaceIdx === -1) {
        ctx.ui.notify("Usage: /agent <name> <task>", "warning");
        return;
      }
      const name = args.slice(0, spaceIdx).trim();
      const task = args.slice(spaceIdx + 1).trim();

      ctx.ui.notify(`Delegating to agent [${name}]...`, "info");
      ctx.sendUserMessage(`Delegate to subagent "${name}" with task: ${task}`);
    },
  });
}
