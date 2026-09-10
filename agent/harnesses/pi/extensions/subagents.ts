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
import { performance } from "node:perf_hooks";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Container, Markdown, Text } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { allocateWorktree, releaseWorktree, collectWorktreeDiff, listAllocatedWorktrees } from "./worktree-manager";
import { globalReplStore } from "./lib/repl-context-core";

export interface AgentConfig {
  name: string;
  description: string;
  tools?: string[];
  model?: string;
  // Raw frontmatter model string (e.g. an abstract tier "High") preserved
  // verbatim BEFORE resolution to a concrete provider id. `model` above is the
  // resolved concrete id; `modelTier` is required for correct rate-limit /
  // token-exhaustion failover, which must re-resolve fallbacks from the tier
  // (a concrete id cannot be mapped back to its tier's fallbacks).
  modelTier?: string;
  effort?: string;
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

/**
 * Automatically infer the optimal specialized agent from task description and repository context.
 * Enables effortless delegation when the agent name is omitted or specified as "auto".
 */
export function inferAgentFromTask(taskText: string, targetCwd?: string, availableAgents?: AgentConfig[]): string {
  const t = (taskText || "").toLowerCase();
  const checkDir = targetCwd || process.cwd();

  // 1. Vald repository boundary. Match the cwd as a path COMPONENT (vdaas/vald or
  // a `vald` segment) rather than a bare substring — otherwise unrelated repos
  // like `/home/x/vald-benchmarks` or `/home/x/klausvald` misroute to
  // vald-reviewer (same class as vald-guard.isValdRepo). The explicit task-text
  // mention of "vald"/"vald law" is intentional and kept.
  const normDir = checkDir.replace(/\\/g, "/").toLowerCase();
  const cwdIsVald = normDir.includes("vdaas/vald") || /(^|\/)vald(\/|$)/.test(normDir);
  if (cwdIsVald || t.includes("vald") || t.includes("vald law")) {
    if (!availableAgents || availableAgents.some((a) => a.name === "vald-reviewer")) {
      return "vald-reviewer";
    }
  }

  // 2. Exact domain keywords and technology signatures
  if (
    t.includes("go test") ||
    t.includes("golang") ||
    t.includes("go.mod") ||
    t.includes("goroutine") ||
    /\bgo\b|goの|goで|go製|goコード/.test(t)
  ) {
    return "go-expert";
  }

  if (
    t.includes("rust") ||
    t.includes("cargo") ||
    t.includes("crates.io") ||
    t.includes("lifetime") ||
    t.includes("borrow checker") ||
    /\brs\b|\.rs\b/.test(t)
  ) {
    return "rust-expert";
  }

  if (
    t.includes("c++") ||
    t.includes("cpp") ||
    t.includes("cmake") ||
    t.includes("clang++") ||
    t.includes("vcpkg") ||
    /\bcpp\b|\.cpp\b/.test(t)
  ) {
    return "cpp-expert";
  }

  if (
    t.includes("python") ||
    t.includes("pytorch") ||
    t.includes("pytest") ||
    t.includes("pip ") ||
    t.includes("pyproject") ||
    /\bpy\b|\.py\b/.test(t)
  ) {
    return "python-expert";
  }

  if (t.includes("zig") || t.includes("build.zig") || /\.zig\b/.test(t)) {
    return "zig-expert";
  }

  if (
    t.includes("k8s") ||
    t.includes("kubernetes") ||
    t.includes("helm") ||
    t.includes("kustomize") ||
    t.includes("crd") ||
    t.includes("manifest")
  ) {
    return "k8s-expert";
  }

  if (
    t.includes("nix") ||
    t.includes("nixos") ||
    t.includes("nix-darwin") ||
    t.includes("home-manager") ||
    t.includes("flake.nix")
  ) {
    return "nix-expert";
  }

  if (
    t.includes("github action") ||
    t.includes("github actions") ||
    t.includes("workflow") ||
    t.includes(".github/workflows") ||
    t.includes("ci/cd")
  ) {
    return "github-actions-expert";
  }

  if (
    t.includes("proto") ||
    t.includes("protobuf") ||
    t.includes("grpc") ||
    t.includes("buf lint") ||
    /\.proto\b/.test(t)
  ) {
    return "proto-expert";
  }

  if (
    t.includes("ann ") ||
    t.includes("vector search") ||
    t.includes("simd") ||
    t.includes("arcflare") ||
    t.includes("ngtaq")
  ) {
    return "ann-perf-engineer";
  }

  if (
    t.includes("benchmark") ||
    t.includes("perf") ||
    t.includes("pprof") ||
    t.includes("criterion") ||
    t.includes("profiling") ||
    t.includes("latency") ||
    t.includes("throughput")
  ) {
    return "perf-analyzer";
  }

  if (
    t.includes("security") ||
    t.includes("vulnerability") ||
    t.includes("cve") ||
    t.includes("owasp") ||
    t.includes("auth") ||
    t.includes("secret") ||
    t.includes("token leak")
  ) {
    return "security-audit";
  }

  if (
    t.includes("debug") ||
    t.includes("root cause") ||
    t.includes("panic") ||
    t.includes("segfault") ||
    t.includes("crash") ||
    t.includes("failure") ||
    t.includes("stack trace")
  ) {
    return "debugger";
  }

  if (
    t.includes("review") ||
    t.includes("audit") ||
    t.includes("inspect") ||
    t.includes("verify")
  ) {
    return "code-reviewer";
  }

  if (
    t.includes("arch linux") ||
    t.includes("pacman") ||
    t.includes("aur") ||
    t.includes("systemd") ||
    t.includes("sway") ||
    t.includes("wayland")
  ) {
    return "arch-ops";
  }

  // 3. Fallback based on repository manifest files
  try {
    if (fs.existsSync(path.join(checkDir, "go.mod"))) return "go-expert";
    if (fs.existsSync(path.join(checkDir, "Cargo.toml"))) return "rust-expert";
    if (fs.existsSync(path.join(checkDir, "CMakeLists.txt"))) return "cpp-expert";
    if (
      fs.existsSync(path.join(checkDir, "pyproject.toml")) ||
      fs.existsSync(path.join(checkDir, "requirements.txt"))
    ) {
      return "python-expert";
    }
    if (fs.existsSync(path.join(checkDir, "flake.nix"))) return "nix-expert";
  } catch {}

  // 4. Default general purpose fallback
  return "code-reviewer";
}

/**
 * Dynamically negotiate the tool set for a subagent when its definition does not
 * declare an explicit `tools` list. Reviewers/auditors/security roles receive a
 * minimal read-only set (no Write/Edit); all other roles receive the full
 * implementation capability set. The returned PascalCase tokens are converted to
 * the pi `--tools` vocabulary by `mapToolNames` at the spawn site, identical to
 * the path for explicitly declared tools.
 */
export function resolveAgentTools(agentName: string): string[] {
  const n = (agentName || "").toLowerCase();
  if (
    n === "security-audit" ||
    n === "code-reviewer" ||
    n === "vald-reviewer" ||
    n.includes("adversarial-reviewer") ||
    n.includes("auditor") ||
    n.includes("reviewer")
  ) {
    return ["Bash", "Read", "Grep", "Glob"];
  }
  return ["Bash", "Read", "Grep", "Glob", "Write", "Edit"];
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

/**
 * Build a failed StepResult for a workflow step whose task threw (e.g. on
 * abort), so the DAG scheduler can record it and degrade gracefully instead of
 * rejecting the whole workflow.
 */
export function makeFailedStepResult(
  stepId: string,
  agent: string,
  task: string,
  errorMessage: string,
  durationMs = 0
): SingleResult {
  return {
    agent,
    agentSource: "unknown",
    task,
    exitCode: 1,
    stdout: "",
    stderr: `Step "${stepId}" failed: ${errorMessage}`,
    stepId,
    durationMs,
  };
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

/**
 * Bare model aliases (e.g. "sonnet", "haiku") without a provider prefix resolve
 * ambiguously inside the child `pi -p --model <alias>` spawn: pi matches them against
 * ALL registered providers and can pick `amazon-bedrock` (a built-in provider with no
 * API key here), causing every such subagent to fail with
 * "No API key found for amazon-bedrock". Qualify the well-known Claude aliases with the
 * native `anthropic` provider so subagents run on the active subscription. Effort is left
 * unqualified so pi applies it from settings.json `modelThinkingLevels` / `defaultThinkingLevel`
 * (single source of truth). Verified ids: anthropic/claude-sonnet-5, anthropic/claude-haiku-4-5,
 * anthropic/claude-opus-5.
 */
const BARE_MODEL_ALIASES: Record<string, string> = {
  sonnet: "anthropic/claude-sonnet-5",
  haiku: "anthropic/claude-haiku-4-5",
  opus: "anthropic/claude-opus-5",
};

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
    // Not an abstract tier: qualify bare Claude aliases so child `pi -p` spawns do not
    // fall through to the unconfigured amazon-bedrock provider (see BARE_MODEL_ALIASES).
    if (!modelStr.includes("/")) {
      const alias = BARE_MODEL_ALIASES[modelStr.toLowerCase()];
      if (alias) return alias;
    }
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

        const effort = frontmatter.effort ? String(frontmatter.effort).toLowerCase() : undefined;
        agents.push({
          name,
          description,
          tools,
          model: resolveModelTier(frontmatter.model, {
            tools,
            prompt: `${description} ${body.trim()}`,
          }),
          // Preserve the raw tier for failover re-resolution (see AgentConfig.modelTier).
          modelTier: frontmatter.model,
          effort,
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

// Exported so the fable-spot budget gate (fable-gate.ts) can resolve an agent
// name to its model tier at tool_call time (SWARM.md §1 spot layer detection).
export function discoverAgents(cwd: string): AgentConfig[] {
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

export interface SingleResult {
  agent: string;
  agentSource: string;
  task: string;
  exitCode: number;
  stdout: string;
  stderr: string;
  model?: string;
  step?: number;
  stepId?: string;
  durationMs?: number;
  worktree?: string;
  retries?: number;
  failoverModel?: string;
}

export interface SubagentDetails {
  mode: "single" | "parallel" | "chain" | "workflow";
  results: SingleResult[];
  workflowDag?: Array<{
    id: string;
    agent: string;
    status: "pending" | "running" | "success" | "failed" | "skipped";
    durationMs?: number;
    dependsOn?: string[];
  }>;
}

export interface WorkflowStep {
  id: string;
  agent: string;
  task: string;
  dependsOn?: string[];
  worktree?: boolean;
  cwd?: string;
  model?: string;
  effort?: string;
  retries?: number;
}

export interface RunAgentOptions {
  targetCwd?: string;
  step?: number;
  stepId?: string;
  modelOverride?: string;
  effortOverride?: string;
  retries?: number;
  correlationId?: string;
  signal?: AbortSignal;
  onUpdate?: (partial: { content: Array<{ type: "text"; text: string }>; details: SubagentDetails }) => void;
  makeDetails?: (results: SingleResult[]) => SubagentDetails;
}

export function capTaskOutput(agentName: string, output: string, cap = PER_TASK_OUTPUT_CAP): string {
  // The cap is a BYTE budget, so compare byte length (UTF-8), not the UTF-16
  // code-unit `output.length` — otherwise a multibyte output under `cap` chars
  // but over `cap` bytes would escape truncation.
  if (!output) return output;
  const byteLen = Buffer.byteLength(output, "utf-8");
  if (byteLen <= cap) return output;
  const safeName = agentName.replace(/[^\w.-]+/g, "_");
  const tmpLog = path.join(os.tmpdir(), `pi-subagent-${safeName}-${Date.now()}.log`);
  try {
    fs.writeFileSync(tmpLog, output, "utf-8");
  } catch {}

  // Register the full output with the REPL context store so the orchestrator can
  // surgically slice/grep it via repl_filter without re-running the subagent.
  let bufferHint = "";
  try {
    const stored = globalReplStore.store(output, `subagent:${safeName}`);
    if (stored && (stored.bufferId || stored.handle)) {
      bufferHint = ` Use repl_filter (bufferId: ${stored.handle || stored.bufferId}) to query the full output.`;
    }
  } catch {}

  const lines = output.split("\n");
  const HEAD_LINES = 25;
  const TAIL_LINES = 25;
  const head = lines.slice(0, HEAD_LINES).join("\n");
  // Start the tail AFTER the head so the two windows never overlap when the
  // output has few (but long) lines — otherwise the middle lines would be shown
  // twice. `output.length` is a UTF-16 code-unit count; report the true byte size.
  const tailStart = Math.max(HEAD_LINES, lines.length - TAIL_LINES);
  const tail = lines.slice(tailStart).join("\n");
  return `${head}\n\n... [Output truncated (${byteLen} bytes exceeds ${cap} byte cap). Full log: ${tmpLog}.${bufferHint}] ...\n\n${tail}`;
}

export function validateWorkflowDag(steps: WorkflowStep[]): { valid: boolean; error?: string } {
  if (!steps || steps.length === 0) {
    return { valid: false, error: "Workflow steps array cannot be empty." };
  }

  const idSet = new Set<string>();
  for (const s of steps) {
    if (!s.id || typeof s.id !== "string" || !s.id.trim()) {
      return { valid: false, error: "Step missing valid non-empty 'id'." };
    }
    if (idSet.has(s.id)) {
      return { valid: false, error: `Duplicate step id "${s.id}". Step IDs must be unique.` };
    }
    idSet.add(s.id);
  }

  for (const s of steps) {
    if (s.dependsOn) {
      for (const dep of s.dependsOn) {
        if (!idSet.has(dep)) {
          return { valid: false, error: `Step "${s.id}" depends on unknown step "${dep}".` };
        }
        if (dep === s.id) {
          return { valid: false, error: `Step "${s.id}" cannot depend on itself.` };
        }
      }
    }
  }

  const visited = new Map<string, "visiting" | "visited">();
  const depMap = new Map<string, string[]>();
  for (const s of steps) {
    depMap.set(s.id, s.dependsOn || []);
  }

  function hasCycle(id: string): boolean {
    const state = visited.get(id);
    if (state === "visiting") return true;
    if (state === "visited") return false;

    visited.set(id, "visiting");
    for (const dep of depMap.get(id) || []) {
      if (hasCycle(dep)) return true;
    }
    visited.set(id, "visited");
    return false;
  }

  for (const s of steps) {
    if (!visited.has(s.id)) {
      if (hasCycle(s.id)) {
        return { valid: false, error: `Cycle detected in workflow dependencies involving step "${s.id}".` };
      }
    }
  }

  return { valid: true };
}

/**
 * Substitute `{depId}` / `{depId.output}` tokens in a workflow task with the
 * dependency's output. Uses literal split/join rather than String.replace with
 * a RegExp+string replacement, which would (a) interpret `$&`/`$$`/`$1` in the
 * dependency output as replacement patterns (corrupting the task) and (b) treat
 * regex metacharacters in a step id as a pattern. `{depId.output}` is replaced
 * before the bare `{depId}` so the longer token wins.
 */
export function interpolateWorkflowTask(
  task: string,
  depOutputs: Array<{ id: string; output: string }>
): string {
  let out = task;
  for (const { id, output } of depOutputs) {
    out = out.split(`{${id}.output}`).join(output).split(`{${id}}`).join(output);
  }
  return out;
}

export async function executeWorkflowDag(
  defaultCwd: string,
  agents: AgentConfig[],
  steps: WorkflowStep[],
  options?: {
    correlationId?: string;
    signal?: AbortSignal;
    onUpdate?: (partial: { content: Array<{ type: "text"; text: string }>; details: SubagentDetails }) => void;
    makeDetails?: (results: SingleResult[]) => SubagentDetails;
  }
): Promise<{ results: SingleResult[]; allSucceeded: boolean }> {
  const correlationId = options?.correlationId ?? `wf-${Date.now().toString(36)}`;
  const effectiveConcurrency = calculateEffectiveConcurrency(steps);
  const stepResults = new Map<string, SingleResult>();
  const remainingDeps = new Map<string, Set<string>>();
  const dependents = new Map<string, string[]>();

  for (const s of steps) {
    const deps = new Set(s.dependsOn || []);
    remainingDeps.set(s.id, deps);
    for (const d of deps) {
      if (!dependents.has(d)) dependents.set(d, []);
      dependents.get(d)!.push(s.id);
    }
  }

  const activePromises = new Set<Promise<void>>();

  function broadcastProgress() {
    if (options?.onUpdate && options?.makeDetails) {
      const allRes = Array.from(stepResults.values());
      const activeNames = Array.from(activePromises).length;
      const completed = allRes.filter((r) => r.exitCode === 0).length;
      const failed = allRes.filter((r) => r.exitCode !== 0 && !r.stdout.includes("Skipped:")).length;
      const skipped = allRes.filter((r) => r.stdout.includes("Skipped:")).length;

      const summary = `[Workflow DAG] Progress: ${allRes.length}/${steps.length} | Active: ${activeNames} | Succeeded: ${completed} | Failed: ${failed} | Skipped: ${skipped}`;
      options.onUpdate({
        content: [{ type: "text", text: summary }],
        details: options.makeDetails(allRes),
      });
    }
  }

  async function scheduleReady(): Promise<void> {
    for (const s of steps) {
      if (stepResults.has(s.id)) continue;
      const deps = remainingDeps.get(s.id);
      if (deps && deps.size === 0 && activePromises.size < effectiveConcurrency) {
        if (options?.signal?.aborted) break;

        // Check if any prerequisite dependency failed or was skipped
        const failedDep = (s.dependsOn || []).find((d) => {
          const depRes = stepResults.get(d);
          return !depRes || depRes.exitCode !== 0;
        });

        if (failedDep) {
          const skippedResult: SingleResult = {
            agent: s.agent,
            agentSource: "workflow",
            task: s.task,
            exitCode: 1,
            stdout: `Skipped: dependency "${failedDep}" did not succeed.`,
            stderr: `Blocked by upstream failure in step "${failedDep}".`,
            stepId: s.id,
            durationMs: 0,
          };
          stepResults.set(s.id, skippedResult);
          for (const nextId of dependents.get(s.id) || []) {
            remainingDeps.get(nextId)?.delete(s.id);
          }
          broadcastProgress();
          await scheduleReady();
          continue;
        }

        // Interpolate dependency outputs into task prompt (literal, injection-safe).
        const depOutputs: Array<{ id: string; output: string }> = [];
        for (const depId of s.dependsOn || []) {
          const depRes = stepResults.get(depId);
          if (depRes) depOutputs.push({ id: depId, output: depRes.stdout.trim() });
        }
        const interpolatedTask = interpolateWorkflowTask(s.task, depOutputs);

        let targetCwd = s.cwd;
        let allocatedWt: { worktreePath: string; branchName: string } | null = null;
        if (s.worktree) {
          const safeTaskId = `${correlationId}-${s.id}`;
          const alloc = allocateWorktree(defaultCwd, safeTaskId);
          if (alloc.success) {
            targetCwd = alloc.worktreePath;
            allocatedWt = alloc;
          }
        }

        const taskPromise = (async () => {
          const t0 = performance.now();
          try {
            const res = await runSingleAgent(
              defaultCwd,
              agents,
              s.agent,
              interpolatedTask,
              {
                targetCwd,
                stepId: s.id,
                modelOverride: s.model,
                effortOverride: s.effort,
                retries: s.retries,
                correlationId,
                signal: options?.signal,
              }
            );

            res.stepId = s.id;
            res.durationMs = performance.now() - t0;

            if (allocatedWt) {
              const diffData = collectWorktreeDiff(allocatedWt.worktreePath);
              if (diffData.files.length > 0) {
                res.stdout += `\n\n[Worktree ${allocatedWt.branchName} modified: ${diffData.files.join(", ")}]`;
                res.worktree = allocatedWt.branchName;
              }
            }

            stepResults.set(s.id, res);

            // Publish event to subagent mesh stream if available
            try {
              const { BlackboardStream } = await import("./lib/subagent-mesh-core");
              const stream = new BlackboardStream({ correlationId });
              await stream.append({
                id: `evt-${s.id}-${Date.now()}`,
                topic: res.exitCode === 0 ? "verification" : "critique",
                sender: { id: s.agent, role: "worker" },
                correlationId,
                timestamp: Date.now(),
                payload: {
                  stepId: s.id,
                  agent: s.agent,
                  exitCode: res.exitCode,
                  durationMs: res.durationMs,
                  outputPreview: res.stdout.slice(0, 300),
                },
              });
            } catch {}

            for (const nextId of dependents.get(s.id) || []) {
              remainingDeps.get(nextId)?.delete(s.id);
            }
          } catch (err: any) {
            // runSingleAgent can throw (e.g. on abort). Without this catch the
            // task promise would reject: Promise.race in the scheduler would
            // throw and abort the whole workflow, the finally-derived promise
            // would surface as an unhandled rejection, and the missing
            // stepResults entry would later crash `finalResults.every(r =>
            // r.exitCode)` on undefined. Record a failed result so the DAG
            // degrades gracefully.
            stepResults.set(s.id, makeFailedStepResult(s.id, s.agent, interpolatedTask, err?.message ?? String(err), performance.now() - t0));
            for (const nextId of dependents.get(s.id) || []) {
              remainingDeps.get(nextId)?.delete(s.id);
            }
          } finally {
            if (allocatedWt) {
              releaseWorktree(defaultCwd, allocatedWt.worktreePath, allocatedWt.branchName);
            }
            broadcastProgress();
          }
        })();

        activePromises.add(taskPromise);
        taskPromise.finally(() => {
          activePromises.delete(taskPromise);
        });

        if (activePromises.size >= effectiveConcurrency) break;
      }
    }
  }

  while (stepResults.size < steps.length) {
    await scheduleReady();
    if (activePromises.size === 0) {
      break;
    }
    await Promise.race(activePromises);
  }

  const finalResults = steps.map((s) => stepResults.get(s.id)!);
  const allSucceeded = finalResults.every((r) => r.exitCode === 0);
  return { results: finalResults, allSucceeded };
}

async function runSingleAgent(
  defaultCwd: string,
  agents: AgentConfig[],
  agentName: string,
  task: string,
  targetCwdOrOptions?: string | RunAgentOptions,
  stepArg?: number,
  signalArg?: AbortSignal,
  onUpdateArg?: (partial: { content: Array<{ type: "text"; text: string }>; details: SubagentDetails }) => void,
  makeDetailsArg?: (results: SingleResult[]) => SubagentDetails
): Promise<SingleResult> {
  const opts: RunAgentOptions =
    typeof targetCwdOrOptions === "object"
      ? targetCwdOrOptions
      : {
          targetCwd: targetCwdOrOptions,
          step: stepArg,
          signal: signalArg,
          onUpdate: onUpdateArg,
          makeDetails: makeDetailsArg,
        };

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
      step: opts.step,
      stepId: opts.stepId,
    };
  }

  // Raw resolution source (abstract tier or explicit override) preserved for
  // failover: fallbacks live under the tier in model-routing.json and can only
  // be reached from the tier string, never from an already-resolved concrete id.
  // modelOverride may itself be a raw tier (from tool input); agent.modelTier is
  // the raw frontmatter value; agent.model is the pre-resolved concrete fallback.
  const modelResolutionSource = opts.modelOverride ?? agent.modelTier ?? agent.model;
  // Resolve the source to a concrete id for the initial `--model` arg. This also
  // fixes a latent bug where a raw-tier modelOverride (e.g. "High") was passed
  // verbatim to the child `pi -p --model High`.
  let effectiveModel =
    resolveModelTier(modelResolutionSource) ?? agent.model ?? modelResolutionSource;
  let effectiveEffort = opts.effortOverride ?? agent.effort;
  const maxAttempts = Math.max(1, opts.retries ?? 2);
  let attempt = 0;
  let finalExitCode = 1;
  let finalStdout = "";
  let finalStderr = "";
  let lastFailoverModel: string | undefined;

  while (attempt < maxAttempts) {
    attempt++;
    const args: string[] = ["-p", "--no-context-files"];
    if (effectiveModel) {
      args.push("--model", effectiveModel);
    }
    if (effectiveEffort) {
      args.push("--thinking", effectiveEffort);
    }
    const effectiveTools = agent.tools && agent.tools.length > 0 ? agent.tools : mapToolNames(resolveAgentTools(agent.name));
    args.push("--tools", effectiveTools.join(","));

    let tmpDir: string | null = null;
    let tmpPromptFile: string | null = null;
    let localStdout = "";
    let localStderr = "";

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
        const env = {
          ...process.env,
          PI_SUBAGENT: "1",
          ...(opts.correlationId ? { PI_CORRELATION_ID: opts.correlationId } : {}),
          PI_SUBAGENT_NAME: agent.name,
        };

        // `detached: true` puts the child `pi` process in its own process group so
        // that on abort we can signal the whole group (`process.kill(-pid, ...)`),
        // reaping any grandchildren the subagent itself spawned (bridges, tools,
        // model subprocesses). Mirrors the cli-bridge lifecycle; without it a
        // SIGTERM/SIGKILL to the direct child alone orphans those descendants.
        const proc = spawn("pi", args, {
          cwd: opts.targetCwd ?? defaultCwd,
          env,
          stdio: ["ignore", "pipe", "pipe"],
          detached: true,
        });

        proc.stdout.on("data", (chunk) => {
          localStdout += chunk.toString();
          if (opts.onUpdate && opts.makeDetails) {
            opts.onUpdate({
              content: [{ type: "text", text: localStdout || "(subagent executing...)" }],
              details: opts.makeDetails([
                {
                  agent: agentName,
                  agentSource: agent.source,
                  task,
                  exitCode: 0,
                  stdout: localStdout,
                  stderr: localStderr,
                  model: effectiveModel,
                  step: opts.step,
                  stepId: opts.stepId,
                },
              ]),
            });
          }
        });

        proc.stderr.on("data", (chunk) => {
          localStderr += chunk.toString();
        });

        // Lifecycle cleanup shared by close/error/abort: clear the pending SIGKILL
        // escalation timer and detach the abort listener so retries (the outer
        // while-loop) do not accumulate one dead-proc listener per attempt on the
        // long-lived AbortSignal, and a normal exit after an abort does not keep
        // the event loop alive for the full escalation window.
        let killTimer: ReturnType<typeof setTimeout> | undefined;
        let abortListener: (() => void) | undefined;
        const cleanup = () => {
          if (killTimer) {
            clearTimeout(killTimer);
            killTimer = undefined;
          }
          if (abortListener && opts.signal) {
            opts.signal.removeEventListener("abort", abortListener);
            abortListener = undefined;
          }
        };

        const killGroup = (sig: NodeJS.Signals) => {
          if (proc.pid) {
            try {
              process.kill(-proc.pid, sig);
              return;
            } catch {}
          }
          try {
            proc.kill(sig);
          } catch {}
        };

        proc.on("close", (code) => {
          cleanup();
          resolve(code ?? 0);
        });

        proc.on("error", () => {
          cleanup();
          resolve(1);
        });

        if (opts.signal) {
          const killProc = () => {
            wasAborted = true;
            killGroup("SIGTERM");
            killTimer = setTimeout(() => {
              if (!proc.killed) killGroup("SIGKILL");
            }, 3000);
            killTimer.unref?.();
          };
          if (opts.signal.aborted) killProc();
          else {
            abortListener = killProc;
            opts.signal.addEventListener("abort", killProc, { once: true });
          }
        }
      });

      finalExitCode = exitCode;
      finalStdout = localStdout;
      finalStderr = localStderr;

      if (wasAborted) throw new Error("Subagent was aborted");
      if (exitCode === 0) break;

      // Recoverable error detection & model failover
      const combined = `${localStdout} ${localStderr}`.toLowerCase();
      const isRateLimit = combined.includes("429") || combined.includes("rate limit") || combined.includes("too many requests") || combined.includes("overloaded");
      const isTokenExhaustion = combined.includes("prompt is too long") || combined.includes("context_overflow") || combined.includes("maximum context length");
      const isNetwork = combined.includes("econnreset") || combined.includes("etimedout") || combined.includes("fetch failed");

      if (attempt < maxAttempts && (isRateLimit || isTokenExhaustion || isNetwork)) {
        let failover: string | undefined;
        // Re-resolve from the ORIGINAL tier (modelResolutionSource), not from the
        // already-resolved concrete effectiveModel — otherwise the fallbacks are
        // unreachable and failover silently no-ops for tier-configured agents.
        if (isRateLimit) {
          failover = resolveModelTier(modelResolutionSource, { trigger: "rate_limit" });
        } else if (isTokenExhaustion) {
          failover = resolveModelTier(modelResolutionSource, { trigger: "token_exhaustion" });
        }
        if (failover && failover !== effectiveModel) {
          lastFailoverModel = failover;
          finalStderr += `\n[Auto-Recovery] Attempt ${attempt} encountered ${isRateLimit ? "rate limit" : "token limit"}. Escalating model: ${effectiveModel} -> ${failover}\n`;
          effectiveModel = failover;
        } else {
          // Exponential backoff
          await new Promise((r) => setTimeout(r, 1000 * attempt));
        }
        continue;
      }
      break;
    } finally {
      if (tmpPromptFile) {
        try { fs.unlinkSync(tmpPromptFile); } catch {}
      }
      if (tmpDir) {
        try { fs.rmdirSync(tmpDir); } catch {}
      }
    }
  }

  return {
    agent: agentName,
    agentSource: agent.source,
    task,
    exitCode: finalExitCode,
    stdout: capTaskOutput(agentName, finalStdout),
    stderr: finalStderr,
    model: effectiveModel,
    step: opts.step,
    stepId: opts.stepId,
    retries: attempt - 1,
    failoverModel: lastFailoverModel,
  };
}

const TaskItem = Type.Object({
  agent: Type.Optional(Type.String({ description: "Name of the agent to invoke (defaults to 'auto')" })),
  task: Type.String({ description: "Task to delegate to the agent" }),
  cwd: Type.Optional(Type.String({ description: "Working directory for the subagent" })),
});

const ChainItem = Type.Object({
  agent: Type.Optional(Type.String({ description: "Name of the agent to invoke (defaults to 'auto')" })),
  task: Type.String({ description: "Task with optional {previous} placeholder for prior output" }),
  cwd: Type.Optional(Type.String({ description: "Working directory for the subagent" })),
});

const WorkflowStepSchema = Type.Object({
  id: Type.String({ description: "Unique step ID in the workflow (e.g. 'spec', 'worker-1')" }),
  agent: Type.Optional(Type.String({ description: "Name of the agent to invoke (defaults to 'auto')" })),
  task: Type.String({ description: "Task with optional {<stepId>} or {<stepId>.output} interpolation" }),
  dependsOn: Type.Optional(Type.Array(Type.String(), { description: "Prerequisite step IDs" })),
  worktree: Type.Optional(Type.Boolean({ description: "Run task in isolated git worktree" })),
  cwd: Type.Optional(Type.String({ description: "Working directory" })),
  model: Type.Optional(Type.String({ description: "Model or abstract tier override" })),
  effort: Type.Optional(Type.String({ description: "Thinking effort level override" })),
  retries: Type.Optional(Type.Number({ description: "Autonomous retry attempts on recoverable error" })),
});

const SubagentParams = Type.Object({
  agent: Type.Optional(Type.String({ description: "Name of the agent to invoke (single mode, defaults to 'auto' if task is provided)" })),
  task: Type.Optional(Type.String({ description: "Task to delegate (single mode)" })),
  tasks: Type.Optional(Type.Array(TaskItem, { description: "Array of {agent?, task} for parallel execution" })),
  chain: Type.Optional(Type.Array(ChainItem, { description: "Array of {agent?, task} for sequential execution" })),
  workflow: Type.Optional(Type.Array(WorkflowStepSchema, { description: "Array of DAG steps with dependency execution" })),
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
      const hasWorkflow = (params.workflow?.length ?? 0) > 0;
      const hasSingle = Boolean(params.task && !hasChain && !hasTasks && !hasWorkflow);
      const modeCount = Number(hasChain) + Number(hasTasks) + Number(hasSingle) + Number(hasWorkflow);

      const makeDetails = (mode: "single" | "parallel" | "chain" | "workflow") => (results: SingleResult[]): SubagentDetails => ({
        mode,
        results,
      });

      if (modeCount !== 1) {
        const available = agents.map((a) => `${a.name} (${a.source})`).join(", ") || "none";
        return {
          content: [
            {
              type: "text",
              text: `Invalid parameters. Provide exactly one of 'task' (with optional 'agent'), 'tasks', 'chain', or 'workflow'.\nAvailable agents: ${available}`,
            },
          ],
          details: makeDetails("single")([]),
        };
      }

      // Single Mode
      if (hasSingle && params.task) {
        const targetCwd = params.cwd ? path.resolve(ctx.cwd, params.cwd) : ctx.cwd;
        const targetAgent = (!params.agent || params.agent.toLowerCase() === "auto")
          ? inferAgentFromTask(params.task, targetCwd, agents)
          : params.agent;
        const result = await runSingleAgent(
          ctx.cwd,
          agents,
          targetAgent,
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
          const targetCwd = step.cwd ? path.resolve(ctx.cwd, step.cwd) : ctx.cwd;
          const targetAgent = (!step.agent || step.agent.toLowerCase() === "auto")
            ? inferAgentFromTask(step.task, targetCwd, agents)
            : step.agent;
          const taskWithContext = step.task.replace(/\{previous\}/g, previousOutput);

          const result = await runSingleAgent(
            ctx.cwd,
            agents,
            targetAgent,
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
                  text: `Chain failed at step ${i + 1} (${targetAgent}):\n${result.stderr || result.stdout}`,
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

        const effectiveTasks = params.tasks.map((t) => {
          const targetCwd = t.cwd ? path.resolve(ctx.cwd, t.cwd) : ctx.cwd;
          return {
            ...t,
            agent: (!t.agent || t.agent.toLowerCase() === "auto")
              ? inferAgentFromTask(t.task, targetCwd, agents)
              : t.agent,
          };
        });

        const effectiveConcurrency = calculateEffectiveConcurrency(effectiveTasks);
        const allResults = await runTasksInParallelPool(
          effectiveTasks,
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

      // Workflow (DAG) Mode
      if (params.workflow && params.workflow.length > 0) {
        const effectiveWorkflow = params.workflow.map((s) => {
          const targetCwd = s.cwd ? path.resolve(ctx.cwd, s.cwd) : ctx.cwd;
          return {
            ...s,
            agent: (!s.agent || s.agent.toLowerCase() === "auto")
              ? inferAgentFromTask(s.task, targetCwd, agents)
              : s.agent,
          };
        });
        const validation = validateWorkflowDag(effectiveWorkflow);
        if (!validation.valid) {
          return {
            content: [{ type: "text", text: `Invalid workflow DAG:\n${validation.error}` }],
            isError: true,
            details: makeDetails("workflow")([]),
          };
        }

        const { results: wfResults, allSucceeded } = await executeWorkflowDag(
          ctx.cwd,
          agents,
          effectiveWorkflow,
          {
            signal,
            onUpdate,
            makeDetails: (r) => makeDetails("workflow")(r),
          }
        );

        const summaries = wfResults.map((r) => {
          const icon = r.exitCode === 0 ? "✓" : r.stdout.includes("Skipped:") ? "⊘" : "✗";
          const out = r.stdout.trim() || r.stderr.trim() || "(no output)";
          return `### [${r.stepId || r.agent}] (${r.agent}) ${icon} ${
            r.exitCode === 0 ? "Success" : r.stdout.includes("Skipped:") ? "Skipped" : "Failed"
          }${r.failoverModel ? ` (Failover: ${r.failoverModel})` : ""}${
            r.worktree ? ` [Worktree: ${r.worktree}]` : ""
          }\n\n${out}`;
        });

        const successCount = wfResults.filter((r) => r.exitCode === 0).length;
        const total = wfResults.length;

        return {
          content: [
            {
              type: "text",
              text: `Workflow DAG: ${successCount}/${total} steps succeeded${
                allSucceeded
                  ? " (All steps completed successfully)"
                  : " (Some steps failed or were skipped)"
              }\n\n${summaries.join("\n\n---\n\n")}`,
            },
          ],
          isError: !allSucceeded,
          details: makeDetails("workflow")(wfResults),
        };
      }

      return {
        content: [{ type: "text", text: "No actions executed." }],
        details: makeDetails("single")([]),
      };
    },

    renderCall(args, theme) {
      if (args.workflow) {
        return new Text(theme.fg("toolTitle", theme.bold("subagent ")) + theme.fg("accent", `workflow (${args.workflow.length} DAG steps)`), 0, 0);
      }
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

  // Slash Command /agent [name|auto] <task>
  pi.registerCommand("agent", {
    description: "Delegate a task to a specialized agent (/agent [name|auto] <task>)",
    handler: async (args, ctx) => {
      if (!args || !args.trim()) {
        ctx.ui.notify("Usage: /agent [name|auto] <task>", "warning");
        return;
      }
      const agents = discoverAgents(ctx.cwd);
      const spaceIdx = args.indexOf(" ");
      let targetAgent = "auto";
      let taskText = args.trim();

      if (spaceIdx !== -1) {
        const candidateName = args.slice(0, spaceIdx).trim();
        if (candidateName.toLowerCase() === "auto" || agents.some((a) => a.name === candidateName)) {
          targetAgent = candidateName;
          taskText = args.slice(spaceIdx + 1).trim();
        }
      }

      if (targetAgent === "auto") {
        targetAgent = inferAgentFromTask(taskText, ctx.cwd, agents);
      }

      ctx.ui.notify(`Auto-routing to agent [${targetAgent}]...`, "info");
      ctx.sendUserMessage(`Delegate to subagent "${targetAgent}" with task: ${taskText}`);
    },
  });

  // Slash Command /workflow
  pi.registerCommand("workflow", {
    description: "Manage and inspect autonomous multi-agent workflows (/workflow [status|cleanup])",
    handler: async (args, ctx) => {
      const sub = (args || "status").trim().toLowerCase();
      if (sub === "cleanup") {
        const list = listAllocatedWorktrees(ctx.cwd);
        let cleaned = 0;
        for (const wt of list) {
          const res = releaseWorktree(ctx.cwd, wt);
          if (res.success) cleaned++;
        }
        ctx.ui.notify(`Cleaned up ${cleaned}/${list.length} workflow task worktrees.`, "info");
      } else {
        const activeWts = listAllocatedWorktrees(ctx.cwd);
        ctx.ui.notify(
          `Autonomous Multi-Agent Workflow Engine\n\n• Supported Modes: single, parallel pool, sequential chain, and dynamic DAG (with dependency interpolation and auto-worktree isolation)\n• Active Worktrees: ${activeWts.length}\n• SSoT Concurrency Bounds: Coding(16), Research(100), Testing(50), Benchmark(4), Debugging(4), Review(16)`,
          "info"
        );
      }
    },
  });
}
