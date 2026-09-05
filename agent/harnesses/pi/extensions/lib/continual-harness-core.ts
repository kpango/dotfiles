/**
 * Continual Harness Refinement Core Library
 *
 * Scans session logs for failure patterns (hook rejections, rate limits, tool errors,
 * token exhaustion), formulates concrete configuration refinement proposals for
 * model-routing.json and settings.json, validates syntax, and applies patches with backups.
 */

import * as fs from "node:fs";
import * as path from "node:path";

export type FailureCategory =
  | "hook_rejection"
  | "tool_error"
  | "rate_limit"
  | "token_exhaustion";

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
  targetFile: "model-routing.json" | "settings.json" | string;
  rationale: string;
  diffType: DiffType;
  proposedPatch: any;
  confidence: number; // 0.0 - 1.0
}

/**
 * Scan session directory for JSON / JSONL files and extract grouped failure signatures.
 */
export function scanSessionErrors(sessionsDir: string, daysWindow = 7): FailureSignature[] {
  if (!fs.existsSync(sessionsDir)) {
    return [];
  }

  const now = Date.now();
  const cutoffTime = now - daysWindow * 24 * 60 * 60 * 1000;
  const signatureMap = new Map<string, FailureSignature>();

  let files: string[] = [];
  try {
    files = fs.readdirSync(sessionsDir).filter((f) => f.endsWith(".json") || f.endsWith(".jsonl"));
  } catch {
    return [];
  }

  for (const file of files) {
    const filePath = path.join(sessionsDir, file);
    let mtime = 0;
    try {
      const st = fs.statSync(filePath);
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

      extractSignaturesFromRecord(record, trimmed, mtime, signatureMap);
    }
  }

  // Sort descending by occurrences
  return Array.from(signatureMap.values()).sort((a, b) => b.occurrences - a.occurrences);
}

function extractSignaturesFromRecord(
  record: any,
  rawText: string,
  timestamp: number,
  map: Map<string, FailureSignature>
): void {
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
    lower.includes("429") ||
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
  const match = text.match(/(?:anthropic\/[\w-]+|codex\/[\w-]+|opencode-go\/[\w-]+|antigravity\/[\w.-]+)/i);
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
          fallbacks.unshift({
            provider: "opencode-go",
            model: "opencode-go/qwen3.8-flash",
            effort: "low",
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

      if (modified) {
        proposals.push({
          id: `refine_settings_token_exhaustion_${(sig.model || "general").replace(/[^a-zA-Z0-9]/g, "_")}`,
          targetFile: "settings.json",
          rationale: `Detected token exhaustion (${sig.occurrences}x). Reduced thinking level to 'medium' and increased compaction reserveTokens to protect session lifespan.`,
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
            id: `refine_settings_retry_tuning`,
            targetFile: "settings.json",
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

  if (proposal.targetFile === "settings.json") {
    const patch = proposal.proposedPatch;
    if (!patch.defaultModel && !patch.defaultProvider) {
      return { valid: false, error: "settings.json proposal missing 'defaultModel' / 'defaultProvider'" };
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

    // Write updated configuration
    const formatted = JSON.stringify(proposal.proposedPatch, null, 2) + "\n";
    fs.writeFileSync(targetPath, formatted, "utf-8");

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
