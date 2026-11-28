/**
 * Continual Harness Refinement Core Library
 *
 * Scans session logs for failure patterns (hook rejections, rate limits, tool errors,
 * token exhaustion), formulates concrete configuration refinement proposals for
 * model-routing.json and sol-pi.json, validates syntax, and applies patches with backups.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { writeFileAtomic } from "./fs-atomic";
import { getLowFallbackEntry } from "./model-catalog";
import {
  evaluateOnlineCompaction,
  isBuildOrTestCommand,
  isEditTool,
  loadSolPiConfig,
  pricingCliffFor,
  verifyQuotesInRawLog,
  type SolPiConfig,
} from "./sol-pi-core";

export type FailureCategory =
  | "hook_rejection"
  | "tool_error"
  | "rate_limit"
  | "token_exhaustion"
  | "action_fusion_miss"
  | "pricing_cliff_crossed"
  | "evidence_quote_mismatch";

export interface FailureSignature {
  signatureId: string;
  category: FailureCategory;
  toolName?: string;
  model?: string;
  occurrences: number;
  firstSeen: number;
  lastSeen: number;
  sampleErrorMessage: string;
}

export type DiffType =
  | "routing_fallback"
  | "thinking_budget"
  | "retry_tuning"
  | "prompt_guardrail";

export interface RefinementProposal {
  id: string;
  targetFile: "model-routing.json" | "sol-pi.json" | string;
  rationale: string;
  diffType: DiffType;
  proposedPatch: any;
  confidence: number; // 0.0 - 1.0
}

/**
 * Scan session directory for JSON / JSONL files and extract grouped failure signatures.
 */
export function scanSessionErrors(sessionsDir: string, daysWindow = 7, config?: SolPiConfig): FailureSignature[] {
  if (!fs.existsSync(sessionsDir)) {
    return [];
  }

  // Loaded once per scan (not per event) for the Harness² pattern detectors.
  let patternConfig: SolPiConfig | undefined = config;
  if (!patternConfig) {
    try {
      patternConfig = loadSolPiConfig();
    } catch (err: any) {
      console.error(`[continual-harness] Harness² pattern detection disabled: ${err?.message ?? err}`);
    }
  }

  const now = Date.now();
  const cutoffTime = now - daysWindow * 24 * 60 * 60 * 1000;
  const signatureMap = new Map<string, FailureSignature>();

  // OMP writes <sessionsDir>/<encoded-cwd>/<timestamp>_<id>.jsonl (sub-agents: <timestamp>_<id>/<agentId>.jsonl),
  // so walk down (bounded, never through symlinks) instead of reading only the top level.
  // Bounded: at most MAX_SESSION_FILES files are listed (and the cut is reported), and files above MAX_SESSION_BYTES or
  // that are not regular files at read time (a FIFO swapped in after readdir would block the synchronous read) are skipped.
  const MAX_SESSION_FILES = 5000;
  const MAX_SESSION_BYTES = 64 * 1024 * 1024;
  const files: string[] = [];
  const walk = (dir: string, depth: number): void => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const d of entries) {
      if (files.length >= MAX_SESSION_FILES) return;
      const p = path.join(dir, d.name);
      if (d.isFile() && (d.name.endsWith(".json") || d.name.endsWith(".jsonl"))) files.push(p);
      else if (d.isDirectory() && depth < 3) walk(p, depth + 1);
    }
  };
  walk(sessionsDir, 0);
  if (files.length >= MAX_SESSION_FILES) {
    console.error(`[continual-harness] session scan capped at ${MAX_SESSION_FILES} files (directory order, not newest first); the remaining sessions were not read`);
  }

  for (const filePath of files) {
    let mtime = 0;
    try {
      const st = fs.statSync(filePath);
      if (!st.isFile() || st.size > MAX_SESSION_BYTES) continue;
      mtime = st.mtimeMs;
    } catch {
      continue;
    }

    if (mtime < cutoffTime) {
      continue;
    }

    let fileContent = "";
    try {
      fileContent = fs.readFileSync(filePath, "utf-8");
    } catch {
      continue;
    }

    // Process line by line (works for both JSONL and pretty JSON lines)
    const lines = fileContent.split(/\r?\n/);
    const events: any[] = [];
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;

      let record: any = null;
      if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
        try {
          record = JSON.parse(trimmed);
        } catch {
          // Fall back to plain text scan below
        }
      }

      if (record) events.push(record);
      extractSignaturesFromRecord(record, trimmed, mtime, signatureMap);
    }
    if (patternConfig) addHarnessPatternSignatures(events, mtime, signatureMap, patternConfig);
  }

  // Sort descending by occurrences
  return Array.from(signatureMap.values()).sort((a, b) => b.occurrences - a.occurrences);
}

// OMP のセッションエントリ type(@earendil-works/pi-coding-agent 19.0.1 src/session/session-entries.ts)。
const SESSION_ENTRY_TYPES = new Set([
  "session", "message", "model_usage", "thinking_level_change", "model_change", "service_tier_change", "compaction",
  "branch_summary", "reset_boundary", "custom", "label", "ttsr_injection", "credential_pin", "session_init", "mode_change",
  "custom_message",
]);

function extractSignaturesFromRecord(
  record: any,
  rawText: string,
  timestamp: number,
  map: Map<string, FailureSignature>
): void {
  // 実セッションのエントリは会話本文・usage の数値・ツール引数を含むため、全文の部分一致は誤検出になる
  // (例: usage.input=14290 が "429" に一致し rate_limit、本文中の語 "security-gate" が hook_rejection になる)。
  // 失敗を表す場所だけを見る: toolResult(isError)の本文と、assistant の stopReason:"error" の errorMessage。
  if (record && typeof record.type === "string" && SESSION_ENTRY_TYPES.has(record.type)) {
    const m = record.type === "message" ? record.message : undefined;
    const asText = (v: unknown): string => (typeof v === "string" ? v : JSON.stringify(v ?? ""));
    if (m?.role === "toolResult" && m.isError === true) {
      const body = asText(m.content);
      extractSignaturesFromRecord({ isError: true, toolName: m.toolName, error: body }, body, timestamp, map);
    } else if (m?.role === "assistant" && m.stopReason === "error") {
      const body = asText(m.errorMessage);
      extractSignaturesFromRecord({ model: m.model, error: body }, body, timestamp, map);
    }
    return;
  }
  const text = record ? JSON.stringify(record) : rawText;
  const lower = text.toLowerCase();

  // 1. Hook Rejection
  if (
    lower.includes("security-gate") ||
    lower.includes("vald-guard") ||
    lower.includes("hook rejected") ||
    lower.includes("security gate blocked") ||
    lower.includes("pretooluse rejected") ||
    (record?.error && String(record.error).toLowerCase().includes("rejected"))
  ) {
    const hookName = lower.includes("security-gate")
      ? "security-gate"
      : lower.includes("vald-guard")
      ? "vald-guard"
      : "pretooluse_hook";
    const sigId = `hook_rejection:${hookName}`;
    addOrUpdateSignature(map, sigId, "hook_rejection", rawText, timestamp, hookName);
  }

  // 2. Rate Limit (429 / quota)
  if (
    // HTTP 429 as its own token: not part of a longer number (14290 / 42429) and not a file:line suffix (foo.go:429, a/b.ts:429).
    /(?<![\w.\/-]:?)429(?!\w)/.test(lower) ||
    lower.includes("rate_limit") ||
    lower.includes("rate limit") ||
    lower.includes("quota exceeded") ||
    lower.includes("too many requests")
  ) {
    const model = record?.model || record?.modelId || extractModelFromText(text) || "unknown";
    const sigId = `rate_limit:${model}`;
    addOrUpdateSignature(map, sigId, "rate_limit", rawText, timestamp, undefined, model);
  }

  // 3. Token Exhaustion (context window / max tokens)
  if (
    lower.includes("token_exhaustion") ||
    lower.includes("context_length_exceeded") ||
    lower.includes("max_tokens") ||
    lower.includes("maximum context length") ||
    lower.includes("prompt too long")
  ) {
    const model = record?.model || record?.modelId || extractModelFromText(text) || "unknown";
    const sigId = `token_exhaustion:${model}`;
    addOrUpdateSignature(map, sigId, "token_exhaustion", rawText, timestamp, undefined, model);
  }

  // 4. Tool Error
  if (
    (record?.isError || record?.exitCode !== undefined && record?.exitCode !== 0) ||
    lower.includes("command failed") ||
    lower.includes("tool execution error") ||
    lower.includes("tool_error")
  ) {
    const tool = record?.tool || record?.toolName || extractToolFromText(text) || "tool";
    const sigId = `tool_error:${tool}`;
    addOrUpdateSignature(map, sigId, "tool_error", rawText, timestamp, tool);
  }
}

function extractModelFromText(text: string): string | undefined {
  const match = text.match(/\b((?:anthropic|openai|opencode-go|antigravity-cli|antigravity|ollama)\/[\w.:-]+)\b/i);
  return match ? match[0] : undefined;
}

function extractToolFromText(text: string): string | undefined {
  const match = text.match(/(?:bash|read|write|edit|grep|find|ls)/i);
  return match ? match[0].toLowerCase() : undefined;
}

function addOrUpdateSignature(
  map: Map<string, FailureSignature>,
  sigId: string,
  category: FailureCategory,
  sampleText: string,
  timestamp: number,
  toolName?: string,
  model?: string
): void {
  const existing = map.get(sigId);
  const sample = sampleText.length > 200 ? sampleText.slice(0, 197) + "..." : sampleText;

  if (existing) {
    existing.occurrences++;
    existing.lastSeen = Math.max(existing.lastSeen, timestamp);
    existing.firstSeen = Math.min(existing.firstSeen, timestamp);
  } else {
    map.set(sigId, {
      signatureId: sigId,
      category,
      toolName,
      model,
      occurrences: 1,
      firstSeen: timestamp,
      lastSeen: timestamp,
      sampleErrorMessage: sample,
    });
  }
}

/**
 * Formulate concrete configuration refinement proposals based on observed failure signatures.
 */
export function generateRefinements(
  signatures: FailureSignature[],
  currentRouting: any,
  currentSettings: any
): RefinementProposal[] {
  const proposals: RefinementProposal[] = [];

  for (const sig of signatures) {
    // A. Rate limits -> Refine model-routing fallbacks
    if (sig.category === "rate_limit" && sig.occurrences >= 2) {
      const affectedModel = sig.model || "";
      const routingClone = JSON.parse(JSON.stringify(currentRouting || {}));

      // Search which tier hosts this model
      let targetTier: string | null = null;
      if (routingClone.tiers) {
        for (const [tierName, tierConf] of Object.entries(routingClone.tiers as Record<string, any>)) {
          if (tierConf.model === affectedModel) {
            targetTier = tierName;
            break;
          }
        }
      }

      if (targetTier && routingClone.tiers[targetTier]) {
        const fallbacks = routingClone.tiers[targetTier].fallbacks || [];
        const hasRateLimitFallback = fallbacks.some(
          (f: any) => f.trigger === "rate_limit" && f.model !== affectedModel
        );

        if (!hasRateLimitFallback) {
          const lowFallback = getLowFallbackEntry();
          fallbacks.unshift({
            provider: lowFallback.provider,
            model: lowFallback.model,
            effort: lowFallback.effort,
            trigger: "rate_limit",
            description: `Auto-refined rate_limit fallback triggered by ${sig.occurrences} observed limits`,
          });
          routingClone.tiers[targetTier].fallbacks = fallbacks;

          proposals.push({
            id: `refine_routing_${targetTier.toLowerCase()}_ratelimit`,
            targetFile: "model-routing.json",
            rationale: `Detected ${sig.occurrences} rate-limit events for model '${affectedModel}' in tier '${targetTier}'. Added immediate load-balancing fallback.`,
            diffType: "routing_fallback",
            proposedPatch: routingClone,
            confidence: 0.95,
          });
        }
      }
    }

    // B. Token exhaustion -> Refine settings thinking levels and reserve tokens
    if (sig.category === "token_exhaustion" && sig.occurrences >= 1) {
      const settingsClone = JSON.parse(JSON.stringify(currentSettings || {}));
      let modified = false;

      // Adjust model thinking level from high to medium if applicable
      if (sig.model && settingsClone.modelThinkingLevels?.[sig.model] === "high") {
        settingsClone.modelThinkingLevels[sig.model] = "medium";
        modified = true;
      }

      // Increase compaction reserves
      if (settingsClone.compaction) {
        settingsClone.compaction.reserveTokens = Math.max(
          settingsClone.compaction.reserveTokens || 16384,
          24576
        );
        modified = true;
      }
      if (settingsClone.onlineContextCompact === false) {
        settingsClone.onlineContextCompact = true;
        modified = true;
      }

      if (modified) {
        proposals.push({
          id: `refine_sol_pi_token_exhaustion_${(sig.model || "general").replace(/[^a-zA-Z0-9]/g, "_")}`,
          targetFile: "sol-pi.json",
          rationale: `Detected token exhaustion (${sig.occurrences}x). Reduced thinking level to 'medium' and increased compaction reserveTokens / onlineContextCompact to protect session lifespan.`,
          diffType: "thinking_budget",
          proposedPatch: settingsClone,
          confidence: 0.9,
        });
      }
    }

    // C. Tool errors -> Refine retry settings
    if (sig.category === "tool_error" && sig.occurrences >= 3) {
      const settingsClone = JSON.parse(JSON.stringify(currentSettings || {}));
      if (settingsClone.retry) {
        const currentMax = settingsClone.retry.maxRetries || 3;
        if (currentMax < 5) {
          settingsClone.retry.maxRetries = 5;
          settingsClone.retry.baseDelayMs = 3000;

          proposals.push({
            id: `refine_sol_pi_retry_tuning`,
            targetFile: "sol-pi.json",
            rationale: `Observed ${sig.occurrences} recurring tool execution errors (${sig.toolName || "tool"}). Tuned maxRetries to 5 and baseDelay to 3000ms for transient resilience.`,
            diffType: "retry_tuning",
            proposedPatch: settingsClone,
            confidence: 0.85,
          });
        }
      }
    }
  }

  return proposals;
}

/**
 * Strictly validate that the proposed refinement produces valid JSON and satisfies schema invariants.
 */
export function validateProposalSyntax(
  proposal: RefinementProposal,
  baseContent: string
): { valid: boolean; error?: string } {
  if (!proposal || !proposal.proposedPatch) {
    return { valid: false, error: "Proposal does not contain a proposedPatch" };
  }

  let baseObj: any;
  try {
    baseObj = JSON.parse(baseContent);
  } catch (err: any) {
    return { valid: false, error: `Base content is not valid JSON: ${err.message}` };
  }

  // Verify proposedPatch is serializable
  let serialized = "";
  try {
    serialized = JSON.stringify(proposal.proposedPatch, null, 2);
    JSON.parse(serialized);
  } catch (err: any) {
    return { valid: false, error: `Proposed patch cannot be serialized/parsed as JSON: ${err.message}` };
  }

  // Invariant checks per target file
  if (proposal.targetFile === "model-routing.json") {
    const patch = proposal.proposedPatch;
    if (!patch.tiers || typeof patch.tiers !== "object") {
      return { valid: false, error: "model-routing.json proposal missing required 'tiers' object" };
    }
    if (!patch.default_tier || typeof patch.default_tier !== "string") {
      return { valid: false, error: "model-routing.json proposal missing required 'default_tier'" };
    }
  }

  if (proposal.targetFile === "sol-pi.json") {
    const patch = proposal.proposedPatch;
    if (patch.version === undefined && !patch.defaultModel && !patch.defaultProvider) {
      return { valid: false, error: "sol-pi.json proposal missing 'version' / 'defaultModel' / 'defaultProvider'" };
    }
  }

  return { valid: true };
}

/**
 * Safely apply an approved proposal with an automated timestamped backup.
 */
export function applyProposal(
  repoRoot: string,
  proposal: RefinementProposal
): {
  success: boolean;
  modifiedPath: string;
  backupPath?: string;
  error?: string;
} {
  // Resolve target file path
  let targetPath = path.join(repoRoot, "agent", "harnesses", "pi", proposal.targetFile);
  if (!fs.existsSync(targetPath)) {
    const directPath = path.join(repoRoot, proposal.targetFile);
    if (fs.existsSync(directPath)) {
      targetPath = directPath;
    }
  }

  if (!fs.existsSync(targetPath)) {
    return {
      success: false,
      modifiedPath: targetPath,
      error: `Target configuration file does not exist: ${targetPath}`,
    };
  }

  try {
    const originalContent = fs.readFileSync(targetPath, "utf-8");

    // Pre-apply validation
    const validation = validateProposalSyntax(proposal, originalContent);
    if (!validation.valid) {
      return {
        success: false,
        modifiedPath: targetPath,
        error: `Proposal validation failed: ${validation.error}`,
      };
    }

    // Create backup file
    const backupPath = `${targetPath}.bak.${Date.now()}`;
    fs.writeFileSync(backupPath, originalContent, "utf-8");

    // Write updated configuration atomically: a torn write to a live config file
    // (sol-pi.json or model-routing.json) would corrupt it for the next session start. The backup
    // above allows manual recovery, but the atomic rename avoids the torn state
    // entirely (readers see either the old or the new complete config).
    const formatted = JSON.stringify(proposal.proposedPatch, null, 2) + "\n";
    writeFileAtomic(targetPath, formatted);

    return {
      success: true,
      modifiedPath: targetPath,
      backupPath,
    };
  } catch (err: any) {
    return {
      success: false,
      modifiedPath: targetPath,
      error: `Failed to apply proposal: ${err.message}`,
    };
  }
}

// ---------------------------------------------------------------------------
// Harness² (arXiv:2610.14224) — C1-C8 mapping, INV/DOM tags, Net Token Budget.
// The classification and estimation rules mirror agent/scripts/evolve/harness2-offline.py
// (classify / cluster_traces / est_tokens / check_target / has_unsafe); the parity test in
// continual-harness.test.ts feeds one input table through both and compares. A divergence is a bug.
// ---------------------------------------------------------------------------

export type HarnessComponent = "C1" | "C2" | "C3" | "C4" | "C5" | "C6" | "C7" | "C8";
export type HarnessScope = "INV" | "DOM";

/** Always-loaded layers: only these must satisfy Net Token Budget <= 0. */
export const ALWAYS_LOADED_COMPONENTS: ReadonlySet<HarnessComponent> = new Set<HarnessComponent>(["C1", "C2", "C4", "C6"]);

/** Same cap as harness2-offline.py MAX_INPUT_BYTES. */
export const HARNESS_MAX_INPUT_BYTES = 1 << 20;
const HARNESS_MAX_TRACES = 10_000;
const HARNESS_TARGET_RE = /^[A-Za-z0-9._/@+-]+$/;

// Same rule as harness2-offline.py unsafe_char: control/format/surrogate/private-use/unassigned/line+paragraph
// separators, non-ASCII spaces, variation selectors and the explicit invisible letters.
const UNSAFE_CATEGORY = new RegExp("[\\p{Cc}\\p{Cf}\\p{Cs}\\p{Co}\\p{Cn}\\p{Zl}\\p{Zp}]|(?! )\\p{Zs}", "u");
const EXTRA_INVISIBLE = new Set([0x034f, 0x115f, 0x1160, 0x17b4, 0x17b5, 0x2800, 0x3164, 0xffa0, 0x1d159]);

/** True when the string contains a character harness2-offline.py rejects in signature/task/target (has_unsafe, strict mode). */
export function hasUnsafeHarnessChar(s: string): boolean {
  for (const ch of s) {
    const o = ch.codePointAt(0)!;
    if (UNSAFE_CATEGORY.test(ch) || EXTRA_INVISIBLE.has(o)) return true;
    if ((o >= 0xfe00 && o <= 0xfe0f) || (o >= 0xe0100 && o <= 0xe01ef) || (o >= 0x180b && o <= 0x180d)) return true;
  }
  return false;
}

/** Repo-relative target check (harness2-offline.py check_target); returns the normalized posix path, throws otherwise. */
export function validateHarnessTarget(target: unknown): string {
  if (typeof target !== "string" || target.length === 0 || target.length > 300) throw new Error("invalid target: must be a non-empty string of at most 300 chars");
  if (!HARNESS_TARGET_RE.test(target)) throw new Error("invalid target: allowed characters are A-Z a-z 0-9 . _ / @ + -");
  if (target.startsWith("/") || target.split("/").includes("..")) throw new Error("invalid target: must be a repo-relative path without '..'");
  const parts = target.split("/").filter((p) => p !== "" && p !== ".");
  if (parts.length === 0) throw new Error("invalid target: empty path");
  return parts.join("/");
}

/** Map a repo-relative path to a Harness² component (C1-C8), or null. */
export function classifyHarnessComponent(target: string): HarnessComponent | null {
  if (typeof target !== "string") return null;
  const parts = target.split("/").filter((p) => p !== "" && p !== ".");
  const name = parts[parts.length - 1] ?? "";
  const dot = name.lastIndexOf(".");
  const suffix = dot > 0 && dot < name.length - 1 ? name.slice(dot) : "";
  const dirs = parts.slice(0, -1);
  if (name === "SYSTEM.md") return "C1";
  if (name === "EXPERIENCE.md") return "C3";
  if (name === "AGENTS.md" || name === "CLAUDE.md") return "C4";
  if (name === "SKILL.md" && parts.length >= 3 && parts[parts.length - 3] === "skills") return "C6";
  if (suffix === ".md" && dirs.includes("rules")) return "C2";
  if (suffix === ".md" && parts.length >= 2 && parts[parts.length - 2] === "agents") return "C5";
  if (suffix === ".py" && dirs.includes("scripts")) return "C7";
  // hooks/pi/*.ts are deployed into ~/.pi/agent/extensions (merged directory)
  if (suffix === ".ts" && (dirs.includes("extensions") || (parts.length >= 3 && parts[parts.length - 3] === "hooks" && parts[parts.length - 2] === "pi"))) {
    return "C8";
  }
  return null;
}

/** INV = the failure spans >= 2 distinct tasks, DOM = a single task. */
export function classifyHarnessScope(tasks: Iterable<string>): HarnessScope {
  return new Set(tasks).size >= 2 ? "INV" : "DOM";
}

export interface HarnessTrace {
  signature: string;
  task: string;
  target: string;
  /** AHE change manifest: repo-relative paths, at most 32 entries of at most 300 chars. */
  manifest?: string[];
}

export interface HarnessCluster {
  signature: string;
  count: number;
  tasks: number;
  scope: HarnessScope;
  target: string;
  component: HarnessComponent | null;
  status: "accepted" | "rejected";
  reason: "below_min_occurrences" | "unclassified_target" | null;
  manifests: string[];
}

/** Code point order (Python str comparison); the default JS sort compares UTF-16 code units and disagrees above U+D7FF. */
function cmpCodePoints(a: string, b: string): number {
  const A = Array.from(a);
  const B = Array.from(b);
  for (let i = 0; i < Math.min(A.length, B.length); i++) {
    const d = A[i].codePointAt(0)! - B[i].codePointAt(0)!;
    if (d !== 0) return d;
  }
  return A.length - B.length;
}

function reqTraceString(v: unknown, key: string, maxLen: number): string {
  if (typeof v !== "string" || hasUnsafeHarnessChar(v) || !v.trim()) throw new Error(`trace '${key}' must be a non-empty string without control/invisible characters`);
  if (Array.from(v).length > maxLen) throw new Error(`trace '${key}' exceeds ${maxLen} chars`);
  return v;
}

function normalizeTraceManifest(v: unknown): string[] {
  if (v === undefined) return [];
  if (!Array.isArray(v)) throw new Error("trace 'manifest' must be an array");
  if (v.length > 32) throw new Error("trace 'manifest' has more than 32 entries");
  const seen = new Set<string>();
  for (const p of v) {
    if (typeof p !== "string") throw new Error("trace 'manifest' entries must be strings");
    if (Array.from(p).length > 300) throw new Error("trace manifest entry exceeds 300 chars");
    seen.add(validateHarnessTarget(p));
  }
  return [...seen].sort().slice(0, 32);
}

/** Cluster traces by normalized signature (lower-case, spaces collapsed); mirrors load_traces + cluster_traces. Throws on malformed input. */
export function clusterHarnessTraces(traces: HarnessTrace[], minOccurrences = 3): HarnessCluster[] {
  if (!Array.isArray(traces) || traces.length > HARNESS_MAX_TRACES) throw new Error("traces must be an array of at most 10000 records");
  if (!Number.isInteger(minOccurrences) || minOccurrences < 1) throw new Error("minOccurrences must be an integer >= 1");
  const groups = new Map<string, HarnessTrace[]>();
  for (const t of traces) {
    if (!t || typeof t !== "object") throw new Error("trace record must be an object");
    const sig = reqTraceString(t.signature, "signature", 200).toLowerCase().split(" ").filter(Boolean).join(" ");
    const task = reqTraceString(t.task, "task", 200);
    const target = validateHarnessTarget(reqTraceString(t.target, "target", 300));
    const manifest = normalizeTraceManifest(t.manifest);
    const g = groups.get(sig);
    if (g) g.push({ signature: sig, task, target, manifest });
    else groups.set(sig, [{ signature: sig, task, target, manifest }]);
  }
  const clusters: HarnessCluster[] = [];
  for (const sig of [...groups.keys()].sort(cmpCodePoints)) {
    const items = groups.get(sig)!;
    const counts = new Map<string, number>();
    for (const t of items) counts.set(t.target, (counts.get(t.target) ?? 0) + 1);
    const target = [...counts.keys()].sort((a, b) => counts.get(b)! - counts.get(a)! || (a < b ? -1 : a > b ? 1 : 0))[0]; // targets are ASCII-only (validateHarnessTarget), so code unit order == code point order
    const component = classifyHarnessComponent(target);
    const tasks = new Set(items.map((t) => t.task));
    let status: HarnessCluster["status"] = "accepted";
    let reason: HarnessCluster["reason"] = null;
    if (items.length < minOccurrences) [status, reason] = ["rejected", "below_min_occurrences"];
    else if (component === null) [status, reason] = ["rejected", "unclassified_target"];
    const manifests = [...new Set(items.flatMap((t) => t.manifest ?? []))].sort();
    clusters.push({ signature: sig, count: items.length, tasks: tasks.size, scope: classifyHarnessScope(tasks), target, component, status, reason, manifests });
  }
  return clusters;
}

/** ceil(UTF-8 bytes / 4); byte based so CJK cannot hide growth (same as est_tokens). */
export function estimateHarnessTokens(text: string): number {
  return Math.ceil(Buffer.byteLength(text, "utf8") / 4);
}

export interface NetTokenBudgetResult {
  ok: boolean;
  /** NaN when the input is invalid, so a caller that only tests `delta <= 0` cannot mistake bad input for a pass. */
  delta: number;
  before: number;
  after: number;
  error?: string;
}

function invalidBudgetInput(text: unknown): string | undefined {
  if (typeof text !== "string") return "input must be a string";
  if (text.length > HARNESS_MAX_INPUT_BYTES || Buffer.byteLength(text, "utf8") > HARNESS_MAX_INPUT_BYTES) return `input exceeds ${HARNESS_MAX_INPUT_BYTES} bytes`;
  if (!text.isWellFormed()) return "input contains lone surrogates";
  return undefined;
}

/** Net Token Budget: delta = tokens(after) - tokens(before) must be <= 0. Invalid input fails closed (ok=false, delta=NaN, error set). */
export function validateNetTokenBudget(beforeText: string, afterText: string): NetTokenBudgetResult {
  const error = invalidBudgetInput(beforeText) ?? invalidBudgetInput(afterText);
  if (error) return { ok: false, delta: Number.NaN, before: Number.NaN, after: Number.NaN, error };
  const before = estimateHarnessTokens(beforeText);
  const after = estimateHarnessTokens(afterText);
  return { ok: after - before <= 0, delta: after - before, before, after };
}

export interface TargetBudgetVerdict extends NetTokenBudgetResult {
  component: HarnessComponent | null;
  enforced: boolean;
  /** Budget-stage verdict: false for invalid input, an unclassified target, or an always-loaded component that grows. */
  accepted: boolean;
  reason?: "invalid_input" | "unclassified_target" | "net_token_budget";
}

/** Net Token Budget applied per target: only always-loaded components (C1, C2, C4, C6) are enforced; an unclassified target is rejected like harness2-offline.py does. */
export function evaluateTargetBudget(target: string, beforeText: string, afterText: string): TargetBudgetVerdict {
  const budget = validateNetTokenBudget(beforeText, afterText);
  const component = classifyHarnessComponent(target);
  const enforced = component !== null && ALWAYS_LOADED_COMPONENTS.has(component);
  const reason = budget.error ? "invalid_input" : component === null ? "unclassified_target" : enforced && !budget.ok ? "net_token_budget" : undefined;
  return { ...budget, component, enforced, accepted: reason === undefined, ...(reason ? { reason } : {}) };
}

// ---------------------------------------------------------------------------
// Bounded file reads for the net-budget tool: never follows a path out of the repo, never blocks on
// FIFOs/devices, never reads more than the cap, rejects invalid UTF-8 (harness2-offline.py read_text).
// ---------------------------------------------------------------------------
/** Reads at most `max` bytes from `fd` (position-less reads); throws when more is available. Independent of any size reported by fstat. */
export function readFdBounded(fd: number, max: number = HARNESS_MAX_INPUT_BYTES): Buffer {
  const chunk = Buffer.allocUnsafe(65536);
  const parts: Buffer[] = [];
  let total = 0;
  for (;;) {
    const n = fs.readSync(fd, chunk, 0, Math.min(chunk.length, max + 1 - total), null);
    if (n === 0) break;
    total += n;
    if (total > max) throw new Error(`file exceeds ${max} bytes`);
    parts.push(Buffer.from(chunk.subarray(0, n)));
  }
  return Buffer.concat(parts, total);
}

/** Reads a UTF-8 text file located inside `repoRoot` (symlinks resolved first; anything resolving outside is rejected). */
export function readHarnessTextFile(repoRoot: string, p: string): string {
  if (typeof p !== "string" || p === "" || p.includes("\0")) throw new Error("invalid file path");
  const root = fs.realpathSync(repoRoot);
  const real = fs.realpathSync(path.resolve(repoRoot, p));
  const rel = path.relative(root, real);
  if (rel === ".." || rel.startsWith(".." + path.sep) || path.isAbsolute(rel)) throw new Error(`${p} resolves outside the repository`);
  const c = fs.constants;
  // O_NONBLOCK: opening a FIFO must not wait for a writer. The checks below run on the opened descriptor (no TOCTOU).
  const fd = fs.openSync(real, c.O_RDONLY | c.O_NONBLOCK | c.O_NOFOLLOW | c.O_CLOEXEC);
  try {
    const st = fs.fstatSync(fd);
    if (!st.isFile()) throw new Error(`${p} is not a regular file`);
    if (st.size > HARNESS_MAX_INPUT_BYTES) throw new Error(`${p} exceeds ${HARNESS_MAX_INPUT_BYTES} bytes`);
    const bytes = readFdBounded(fd);
    try {
      return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes);
    } catch {
      throw new Error(`${p} is not valid UTF-8`);
    }
  } finally {
    fs.closeSync(fd);
  }
}

// ---------------------------------------------------------------------------
// Harness² failure patterns over ordered session events. Reuses sol-pi-core (config, cliffs, quote verifier);
// no values are duplicated here. Two shapes are read: the flat events below (tool_use/tool_call + tool/params, turn,
// usage with input_tokens...) and real OMP session entries, which normalizeSessionEvents maps onto them (checked against
// @earendil-works/pi-coding-agent 19.0.1 sources, not against a live session log from this host). Events that match
// neither shape are ignored, so a mismatch yields 0 detections (safe).
// ---------------------------------------------------------------------------
const SEGMENT_SPLIT = /&&|\|\||[;|\n]/;
const SEGMENT_WRAPPERS = new Set(["sudo", "time", "env", "command", "nice", "nohup", "exec"]);
const ENV_ASSIGN = /^[A-Za-z_][A-Za-z0-9_]*=/;
const ISOLATION_FLAGS = new Set(["-I", "-B", "-E", "-s", "-S"]); // python isolation flags: do not change what a validator checks

function commandSegments(command: string): string[][] {
  const out: string[][] = [];
  for (const seg of command.split(SEGMENT_SPLIT)) {
    const toks = seg.trim().split(/\s+/).filter(Boolean);
    let i = 0;
    while (i < toks.length && (ENV_ASSIGN.test(toks[i]) || SEGMENT_WRAPPERS.has(toks[i]))) i++;
    if (i < toks.length) out.push(toks.slice(i));
  }
  return out;
}

/** Validator command patterns derived from actionFusionConfig.defaultValidators (leading tokens; trailing path-like args and python isolation flags dropped). */
function validatorPatterns(config: SolPiConfig): string[][] {
  const patterns: string[][] = [];
  for (const v of Object.values(config.actionFusionConfig?.defaultValidators ?? {})) {
    if (typeof v !== "string") continue;
    const toks = v.trim().split(/\s+/).filter((t) => t && !ISOLATION_FLAGS.has(t));
    while (toks.length > 0 && /^(\.|\/)|\*/.test(toks[toks.length - 1])) toks.pop();
    if (toks.length > 0) patterns.push(toks);
  }
  return patterns;
}

const baseName = (t: string) => t.slice(t.lastIndexOf("/") + 1);

function isValidatorCommand(command: string, patterns: string[][]): boolean {
  if (isBuildOrTestCommand(command)) return true;
  return commandSegments(command).some((seg) => patterns.some((p) => baseName(seg[0]) === baseName(p[0]) && p.slice(1).every((t) => seg.includes(t))));
}

function eventTool(e: any): string | undefined {
  const t = e?.tool ?? e?.toolName;
  return typeof t === "string" ? t : undefined;
}

function eventCommand(e: any): string | undefined {
  const c = e?.command ?? e?.params?.command ?? e?.input?.command;
  return typeof c === "string" ? c : undefined;
}

function eventCallId(e: any): string | undefined {
  const id = e?.id ?? e?.toolCallId ?? e?.callId ?? e?.tool_use_id;
  return typeof id === "string" && id !== "" ? id : undefined;
}

/**
 * OMP session JSONL entries -> the flat events the detectors read. Real shape (src/session/session-entries.ts and
 * agent-session.ts of @earendil-works/pi-coding-agent 19.0.1): {type:"message", message:{role, model, usage:{input, cacheRead,
 * cacheWrite}, content:[{type:"toolCall", id, name, arguments}]}}. An assistant toolCall block becomes
 * {type:"tool_call", id, tool, params}; a user message becomes a {type:"turn"} boundary; the original entry is kept so
 * message.usage / message.model still reach the Pricing Cliff detector. Already-flat events pass through unchanged.
 */
export function normalizeSessionEvents(events: any[]): any[] {
  const out: any[] = [];
  for (const e of events) {
    const m = e?.type === "message" ? e.message : undefined;
    if (m?.role === "user") out.push({ type: "turn" });
    out.push(e);
    if (m?.role === "assistant" && Array.isArray(m.content)) {
      for (const b of m.content) {
        if (b?.type === "toolCall" && typeof b.name === "string") out.push({ type: "tool_call", id: b.id, tool: b.name, params: b.arguments ?? {} });
      }
    }
  }
  return out;
}

/**
 * action_fusion_miss: a batch of two or more edit/write/ast_edit calls that is never validated. An edit run is
 * cleared by a validator (validator output on an event, a build/test command, or a command matching an
 * actionFusionConfig.defaultValidators entry) at any point after it, so editing several files and then running
 * the build once is NOT a miss. A run is closed unvalidated at a turn/turn_end event or at the end of the log
 * and counts once when it holds >= 2 edits. A call logged twice (tool_use + tool_call, same id or same
 * tool+arguments back to back) counts once. Returns the number of misses.
 */
export function detectActionFusionMisses(events: any[], config: SolPiConfig = loadSolPiConfig()): number {
  const patterns = validatorPatterns(config);
  const seenIds = new Set<string>();
  let prevKey: string | undefined;
  let prevType: unknown;
  let edits = 0;
  let misses = 0;
  const closeRun = () => {
    if (edits >= 2) misses++;
    edits = 0;
  };
  for (const e of events) {
    if (e?.validator) edits = 0;
    if (e?.type === "turn" || e?.type === "turn_end") {
      closeRun();
      continue;
    }
    if (e?.type !== "tool_use" && e?.type !== "tool_call") continue;
    const tool = eventTool(e);
    const id = eventCallId(e);
    if (id !== undefined) {
      if (seenIds.has(id)) continue;
      seenIds.add(id);
      prevKey = undefined;
    } else {
      const key = `${tool}|${JSON.stringify(e.params ?? e.input ?? e.command ?? null)}`;
      const duplicate = prevKey === key && prevType !== e.type;
      prevKey = key;
      prevType = e.type;
      if (duplicate) continue;
    }
    if (tool !== undefined && isEditTool(tool)) {
      edits = e.validator ? 0 : edits + 1;
    } else if (tool === "bash" && isValidatorCommand(eventCommand(e) ?? "", patterns)) {
      edits = 0;
    }
  }
  closeRun();
  return misses;
}

export interface PricingCliffCrossing {
  model: string;
  from: number;
  to: number;
  cliff: number;
}

// Context size = input + cache read + cache write, the same sum sol-pi.ts uses for its online compaction advice.
const USAGE_GROUPS = [
  ["inputTokens", "input_tokens", "promptTokens", "prompt_tokens", "input"],
  ["cacheReadInputTokens", "cache_read_input_tokens", "cacheReadTokens", "cache_read_tokens", "cacheRead"],
  ["cacheCreationInputTokens", "cache_creation_input_tokens", "cacheWriteTokens", "cache_write_tokens", "cacheWrite"],
];

/** Sum of the usage fields found on `u`; undefined when none is present or any present value is not a finite number >= 0. */
function usageTokens(u: any): number | undefined {
  if (!u || typeof u !== "object") return undefined;
  let total = 0;
  let found = false;
  for (const group of USAGE_GROUPS) {
    const key = group.find((k) => u[k] !== undefined && u[k] !== null);
    if (key === undefined) continue;
    const n = u[key];
    if (typeof n !== "number" || !Number.isFinite(n) || n < 0) return undefined;
    total += n;
    found = true;
  }
  return found ? total : undefined;
}

function eventContextTokens(e: any): number | undefined {
  if (typeof e?.contextTokens === "number") return Number.isFinite(e.contextTokens) && e.contextTokens >= 0 ? e.contextTokens : undefined;
  return usageTokens(e?.usage) ?? usageTokens(e?.message?.usage) ?? usageTokens(e);
}

/**
 * pricing_cliff_crossed: per model, the context size moved from below the Pricing Cliff to at/above it between two
 * consecutive observations. The first observation of a model has nothing to compare with and never counts.
 * Disabled when pricingCliffAdvisoryConfig.enabled is false (sol-pi.json `pricingCliffAdvisory`); independent of the onlineContextCompact kill switch.
 */
export function detectPricingCliffCrossings(events: any[], config: SolPiConfig = loadSolPiConfig()): PricingCliffCrossing[] {
  if (!config.pricingCliffAdvisoryConfig.enabled) return [];
  const last = new Map<string, number>();
  const out: PricingCliffCrossing[] = [];
  for (const e of events) {
    // 実 OMP の model_usage エントリは別呼び出し(補助的な呼び出し)の集計で、会話本体の文脈サイズではない。
    // stopReason:"error" の assistant メッセージは usage が 0 のことがあり、観測にすると次の実メッセージが偽の crossing になる。
    if (e?.type === "model_usage" || e?.message?.stopReason === "error") continue;
    const model = e?.model ?? e?.modelId ?? e?.message?.model;
    const tokens = eventContextTokens(e);
    if (typeof model !== "string" || tokens === undefined) continue;
    const from = last.get(model);
    last.set(model, tokens);
    if (from === undefined) continue;
    const cliff = pricingCliffFor(model, config);
    if (from < cliff && evaluateOnlineCompaction(tokens, model, undefined, config).level === "exceeded") {
      out.push({ model, from, to: tokens, cliff });
    }
  }
  return out;
}

/** evidence_quote_mismatch: events carrying reducer `quotes` plus the `rawLog` they must be substrings of; counts the violations. */
export function countEvidenceQuoteMismatches(events: any[]): number {
  let n = 0;
  for (const e of events) {
    if (!Array.isArray(e?.quotes) || typeof e?.rawLog !== "string") continue;
    if (!e.quotes.every((q: unknown) => typeof q === "string") || !verifyQuotesInRawLog(e.quotes, e.rawLog)) n++;
  }
  return n;
}

function addHarnessPatternSignatures(rawEvents: any[], timestamp: number, map: Map<string, FailureSignature>, config: SolPiConfig): void {
  const events = normalizeSessionEvents(rawEvents);
  const repeat = (n: number, sigId: string, category: FailureCategory, sample: string, model?: string) => {
    for (let i = 0; i < n; i++) addOrUpdateSignature(map, sigId, category, sample, timestamp, undefined, model);
  };
  // One broken detector (e.g. a malformed catalog entry) must not take the whole scan down.
  const guarded = (name: string, fn: () => void) => {
    try {
      fn();
    } catch (err: any) {
      console.error(`[continual-harness] ${name} detection skipped: ${err?.message ?? err}`);
    }
  };
  guarded("action_fusion_miss", () =>
    repeat(detectActionFusionMisses(events, config), "action_fusion_miss:edit_without_validation", "action_fusion_miss", "two or more edit/write calls without a validator run"),
  );
  guarded("pricing_cliff_crossed", () => {
    for (const c of detectPricingCliffCrossings(events, config)) {
      repeat(1, `pricing_cliff_crossed:${c.model}`, "pricing_cliff_crossed", `context ${c.from} -> ${c.to} crossed Pricing Cliff ${c.cliff}`, c.model);
    }
  });
  guarded("evidence_quote_mismatch", () =>
    repeat(countEvidenceQuoteMismatches(events), "evidence_quote_mismatch:reducer", "evidence_quote_mismatch", "reducer quote is not a substring of the raw log"),
  );
}

// ---------------------------------------------------------------------------
// Harness² Lightweight Regression Auto-Rollback (pi-agent-improvement.pdf #21)
// ---------------------------------------------------------------------------

export interface AppliedRefinementRecord {
  id: string;
  appliedAt: number;
  modifiedPath: string;
  backupPath: string;
  baselineFriction: number;
  consecutiveRegressions: number;
  rolledBackAt?: number;
}

export function defaultRefinementLedgerPath(
  telemetryDir: string = path.join(os.homedir(), ".pi", "agent", "telemetry"),
): string {
  return path.join(telemetryDir, "refinement-ledger.json");
}

export function computeSessionFriction(signatures: FailureSignature[]): number {
  let total = 0;
  for (const s of signatures) {
    if (s && typeof s.occurrences === "number" && Number.isFinite(s.occurrences) && s.occurrences > 0) {
      total += s.occurrences;
    }
  }
  return total;
}

export function evaluateRegressionStep(
  record: AppliedRefinementRecord,
  currentFriction: number,
  maxConsecutive = 2,
): { next: AppliedRefinementRecord; shouldRollback: boolean; regressed: boolean } {
  if (record.rolledBackAt) {
    return { next: record, shouldRollback: false, regressed: false };
  }
  const regressed = currentFriction > record.baselineFriction;
  const consecutiveRegressions = regressed ? record.consecutiveRegressions + 1 : 0;
  const shouldRollback = consecutiveRegressions >= Math.max(1, maxConsecutive);
  return {
    next: { ...record, consecutiveRegressions },
    shouldRollback,
    regressed,
  };
}

export function rollbackRefinementFromBackup(record: AppliedRefinementRecord): {
  success: boolean;
  error?: string;
} {
  try {
    if (!record.backupPath || !record.modifiedPath) {
      return { success: false, error: "missing backupPath or modifiedPath" };
    }
    const backupStat = fs.lstatSync(record.backupPath);
    if (backupStat.isSymbolicLink() || !backupStat.isFile()) {
      return { success: false, error: `unsafe backupPath: ${record.backupPath}` };
    }
    const targetStat = fs.lstatSync(record.modifiedPath);
    if (targetStat.isSymbolicLink() || !targetStat.isFile()) {
      return { success: false, error: `unsafe modifiedPath: ${record.modifiedPath}` };
    }
    const backupContent = fs.readFileSync(record.backupPath, "utf-8");
    writeFileAtomic(record.modifiedPath, backupContent);
    return { success: true };
  } catch (err: any) {
    return { success: false, error: err?.message ?? String(err) };
  }
}

export function loadRefinementLedger(
  ledgerPath: string = defaultRefinementLedgerPath(),
): AppliedRefinementRecord[] {
  try {
    if (!fs.existsSync(ledgerPath)) return [];
    const parsed = JSON.parse(fs.readFileSync(ledgerPath, "utf-8"));
    return Array.isArray(parsed) ? (parsed as AppliedRefinementRecord[]) : [];
  } catch {
    return [];
  }
}

export function saveRefinementLedger(
  records: AppliedRefinementRecord[],
  ledgerPath: string = defaultRefinementLedgerPath(),
): void {
  const dir = path.dirname(ledgerPath);
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  fs.chmodSync(dir, 0o700);
  writeFileAtomic(ledgerPath, JSON.stringify(records, null, 2) + "\n");
  try {
    fs.chmodSync(ledgerPath, 0o600);
  } catch {
    // ignore chmod failures on filesystems without POSIX modes
  }
}
