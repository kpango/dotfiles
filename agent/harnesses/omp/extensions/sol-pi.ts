/**
 * SoL-Pi Runtime Enforcement Extension for Oh My Pi (OMP) — arXiv:2609.20519
 *
 * Ports the four upstream mechanisms (github.com/NVlabs/SoL-Pi) onto the OMP
 * extension surface:
 *
 * 1. Action Fusion — validate an edit right after it lands; on failure the model
 *    sees the validator output instead of the bare success. OMP executes one tool
 *    call at a time, so the upstream same-turn batch barrier is inherent; the new
 *    part is the deterministic validator plus the fused read-only preview.
 * 2. ObservationPack — archive a large tool result once and replace it with an
 *    obs_<24hex> placeholder in the *request projection* only (`context` event),
 *    after the result has been sent `fullReplayTurns` times. History keeps the raw
 *    text; `obs_recall` pages the archive back on demand.
 * 3. Evidence-Preserving Reducer — a cheap side model turns a large build/test log
 *    into a receipt whose every quote is verified against a full raw line; failures
 *    fall back to the deterministic excerpt (never a fabricated receipt). Receipts
 *    are journalled so a restart never pays twice.
 * 4. Online compaction — Estimate the remaining request budget from observed output
 *    tokens; at a settle boundary with fewer than `remainingRequestsTrigger` requests
 *    left, compact once with plan/evidence-preserving instructions. An unneeded
 *    native compaction (usage below window−reserve) is cancelled.
 *
 * The `/sol-pi` command reports status; nothing here switches models.
 */
import { createHash } from "node:crypto";
import * as path from "node:path";
import { completeSimple } from "@oh-my-pi/pi-ai";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
  ONLINE_STATE_ENTRY,
  ReducerJournal,
  applyPlanTransition,
  archiveObservation,
  archiveTokensFor,
  buildEvidenceReceipt,
  buildReducerProviderPrompt,
  compactionInstructions,
  decideCompaction,
  detectEditThenBash,
  parseThenRun,
  runThenRun,
  evaluateOnlineCompaction,
  formatPlanSnapshot,
  initialOnlineState,
  isBuildOrTestCommand,
  isEditTool,
  loadSolPiConfig,
  normalizePlan,
  parseOnlineState,
  packProjectionMessages,
  readObservationChunk,
  redactSecrets,
  reduceAndArchive,
  resolveArchiveDir,
  resolveExitCode,
  runActionFusionValidator,
  type ObservationRecord,
  type OnlineState,
  type PlanStep,
  THEN_RUN_FAILED,
  THEN_RUN_SKIPPED,
  type SolPiConfig,
  type ThenRunSpec,
} from "./lib/sol-pi-core";
import { extractWrittenPaths } from "./stop-verify";

interface TextPart {
  type?: string;
  text?: string;
}
interface ToolEvent {
  toolName?: string;
  tool?: string;
  input?: Record<string, unknown>;
  isError?: boolean;
  error?: unknown;
  exitCode?: number;
  toolCallId?: string;
  result?: unknown;
  content?: unknown;
}
interface UsageLike {
  // pi-ai style
  input?: number;
  output?: number;
  cacheRead?: number;
  cacheWrite?: number;
  totalTokens?: number;
  contextTokens?: number;
  // provider raw / legacy pi style (kept for backward compatibility)
  inputTokens?: number;
  outputTokens?: number;
  promptTokens?: number;
  cacheReadInputTokens?: number;
  cacheReadTokens?: number;
  cacheCreationInputTokens?: number;
  cacheWriteTokens?: number;
}
interface Ctx {
  cwd?: string;
  model?: { id?: string };
  ui?: { notify?: (msg: string, level: "info" | "warning" | "error") => void };
  getContextUsage?: () => { tokens: number; contextWindow: number; percent: number } | undefined;
  compact?: (opts: { internalGuidance?: string }) => Promise<void>;
  sessionManager?: {
    getSessionDir?: () => string;
    getSessionId?: () => string;
    getBranch?: () => { type?: string; customType?: string; data?: unknown }[];
  };
  modelRegistry?: {
    find: (provider: string, modelId: string) => unknown;
    resolver: (model: unknown, sessionId?: string) => unknown;
  };
}
interface TurnEvent {
  message?: { model?: string; usage?: UsageLike };
  toolResults?: { toolName?: string }[];
}
interface ContextEvent {
  messages?: unknown[];
}
interface AgentEndEvent {
  willContinue?: boolean;
  awaitingAsyncWork?: boolean;
}
interface BeforeAgentStartEvent {
  systemPrompt?: string[];
}
interface InputEvent {
  text?: string;
  source?: string;
}
interface InterruptSignal {
  aborted: boolean;
}

interface Slot {
  get: () => string;
  set: (v: string) => void;
}

/**
 * Every mutable text slot of a tool event (same shapes repl-context.ts handles).
 * `event.content` and `event.result.content` may be the same array: parts are de-duplicated
 * by identity so one output is never processed (archived, counted) twice.
 */
export function textSlots(event: ToolEvent): Slot[] {
  const slots: Slot[] = [];
  const seen = new Set<object>();
  const addParts = (parts: unknown) => {
    if (!Array.isArray(parts)) return;
    for (const p of parts as TextPart[]) {
      if (!p || typeof p !== "object" || seen.has(p)) continue;
      if (p.type === "text" && typeof p.text === "string") {
        seen.add(p);
        slots.push({ get: () => p.text as string, set: (v) => void (p.text = v) });
      }
    }
  };
  if (typeof event.result === "string") slots.push({ get: () => event.result as string, set: (v) => void (event.result = v) });
  else if (event.result && typeof event.result === "object") {
    const r = event.result as { content?: unknown; text?: unknown };
    addParts(r.content);
    if (typeof r.text === "string") slots.push({ get: () => r.text as string, set: (v) => void (r.text = v) });
  }
  addParts(event.content);
  return slots;
}

/** Context tokens for the current request: provider-reported context when present. */
export function usageContextTokens(usage: UsageLike | undefined): number | undefined {
  if (!usage) return undefined;
  if (typeof usage.contextTokens === "number") return usage.contextTokens;
  if (typeof usage.totalTokens === "number") return usage.totalTokens;
  const sum = usage.input ?? usage.inputTokens ?? usage.promptTokens ?? 0;
  const cacheRead = usage.cacheRead ?? usage.cacheReadInputTokens ?? usage.cacheReadTokens ?? 0;
  const cacheWrite = usage.cacheWrite ?? usage.cacheCreationInputTokens ?? usage.cacheWriteTokens ?? 0;
  const total = sum + cacheRead + cacheWrite;
  return total > 0 ? total : undefined;
}

/** User text that reads as a correction of the current plan/approach. */
const CORRECTION_RE = /(違う|そうじゃない|そうではなく|ではなく|間違|not what i|instead of|that's wrong|no,? (?:use|do))/i;

export function register(pi: ExtensionAPI, loadConfig: () => SolPiConfig = loadSolPiConfig): void {
  let config: SolPiConfig = loadConfig();
  let state: OnlineState = initialOnlineState();
  let archiveDir = resolveArchiveDir(config);
  let journal: ReducerJournal | undefined;
  const archived = new Map<string, ObservationRecord>();
  const recentTools: string[] = [];
  const editedFiles = new Set<string>();
  let lastValidatorFailed = false;
  let postFailureBash = 0;
  let lastLevel: "ok" | "warn" | "exceeded" = "ok";
  let lastAdvice = "";
  let lastProjection: unknown[] = [];
  let lastUsage: { tokens: number; contextWindow: number } | undefined;
  let reducerCalls = 0;
  const stats = {
    packed: 0,
    rawBytes: 0,
    savedBytes: 0,
    reduced: 0,
    reducedFallback: 0,
    recalled: 0,
    compactions: 0,
  };

  const notify = (ctx: Ctx, m: string, level: "info" | "warning" | "error" = "warning") => ctx.ui?.notify?.(m, level);
  const persist = () => {
    try {
      pi.appendEntry(ONLINE_STATE_ENTRY, state);
    } catch (e) {
      notify({}, `[SoL-Pi] could not persist online state: ${(e as Error).message}`);
    }
  };

  pi.on("session_start", async (_event: unknown, ctx: Ctx) => {
    config = loadConfig();
    reducerCalls = 0;
    recentTools.length = 0;
    editedFiles.clear();
    archived.clear();
    lastProjection = [];
    lastValidatorFailed = false;
    postFailureBash = 0;
    lastLevel = "ok";
    lastAdvice = "";
    stats.packed = stats.rawBytes = stats.savedBytes = stats.reduced = stats.reducedFallback = stats.recalled = stats.compactions = 0;
    state = initialOnlineState();
    const sessionDir = ctx.sessionManager?.getSessionDir?.() ?? undefined;
    for (const entry of ctx.sessionManager?.getBranch?.() ?? []) {
      if (entry.type === "custom" && entry.customType === ONLINE_STATE_ENTRY) state = parseOnlineState(entry.data);
    }
    archiveDir = resolveArchiveDir(config, sessionDir);
    journal = sessionDir
      ? new ReducerJournal(path.join(sessionDir, "sol-pi", "reducer.jsonl"), config.evidencePreservingReducerConfig.cacheEntries)
      : undefined;
  });

  // -------------------------------------------------------------------------
  // Plan reminder: append the active plan to the system prompt for this request.
  // -------------------------------------------------------------------------
  pi.on("before_agent_start", async (event: BeforeAgentStartEvent) => {
    if (state.plan.length === 0) return;
    const base = event.systemPrompt ?? [];
    return { systemPrompt: [...base, `SoL-Pi session plan (authoritative):\n${formatPlanSnapshot(state.plan)}`] };
  });

  // -------------------------------------------------------------------------
  // Tool call anti-pattern (unchanged): bash right after a failed validation.
  // -------------------------------------------------------------------------
  pi.on("tool_call", async (event: ToolEvent, ctx: Ctx) => {
    recentTools.push(String(event.toolName ?? event.tool));
    if (recentTools.length > 8) recentTools.shift();
    if (config.actionFusionConfig.enabled && lastValidatorFailed && detectEditThenBash(recentTools)) {
      postFailureBash++;
      notify(ctx, "[SoL-Pi] Previous edit failed its validator; fix it before running further commands.");
    }
  });

  // -------------------------------------------------------------------------
  // Action Fusion: validate an edit before its result reaches the model.
  // -------------------------------------------------------------------------
  pi.on("tool_result", async (event: ToolEvent, ctx: Ctx) => {
    const name = String(event.toolName ?? event.tool ?? "tool");
    const cwd = ctx.cwd || process.cwd();
    const failed = Boolean(event.isError || event.error);
    const af = config.actionFusionConfig;

    if (!isEditTool(name)) return undefined;
    const files = extractWrittenPaths(event.input)
      .filter((p) => !/[*?[\]{}]/.test(p) && !p.endsWith("/"))
      .slice(0, 20);
    const extras: string[] = [];

    if (!failed && af.enabled) {
      let failedAny = false;
      const reports: string[] = [];
      for (const file of files) {
        editedFiles.add(file);
        try {
          const r = await runActionFusionValidator(file, cwd, config);
          if (r.ran && !r.ok) {
            // A timeout is inconclusive, not a failure.
            if (!r.timedOut) failedAny = true;
            notify(ctx, `[SoL-Pi Action Fusion] validator ${r.timedOut ? "timed out" : "failed"} for ${file}:\n${r.output.slice(0, 1500)}`);
            reports.push(`### ${file}: ${r.timedOut ? "timeout" : "FAILED"}\n${r.output.slice(0, 4000)}`);
          }
        } catch (e) {
          notify(ctx, `[SoL-Pi Action Fusion] validator error for ${file}: ${(e as Error).message}`);
        }
      }
      if (files.length > 0) lastValidatorFailed = failedAny;
      if (reports.length > 0 && af.barrier) {
        extras.push(
          [
            "<action-fusion-validation-failed>",
            "The edit was written, but its validator did not pass. Fix this before any further edit or command:",
            ...reports,
            "</action-fusion-validation-failed>",
          ].join("\n"),
        );
      }
    }

    // Action Fusion: the edit call may carry a fused follow-up command (`then_run`).
    const thenRun = af.enabled && af.thenRun.enabled ? parseThenRun(event.input?.then_run) : undefined;
    if (thenRun) extras.push(await fuseThenRun(ctx, cwd, name, thenRun, files, failed));
    if (extras.length === 0) return undefined;
    return { content: [...(Array.isArray(event.content) ? event.content : []), ...extras.map((text) => ({ type: "text", text }))] };
  });

  /**
   * Run the edit call's `then_run` in the same observation as the mutation.
   * A failed mutation never reaches the command (`[then_run:skipped]`); the
   * mutation stays applied either way, and the marker is always present.
   */
  const fuseThenRun = async (
    ctx: Ctx,
    cwd: string,
    toolName: string,
    spec: ThenRunSpec,
    files: string[],
    mutationFailed: boolean,
  ): Promise<string> => {
    if (mutationFailed) return `${THEN_RUN_SKIPPED} ${toolName} did not complete successfully; the command was not run.`;
    if (files.length === 0) return `${THEN_RUN_SKIPPED} no edited file was recorded for this call; the command was not run.`;
    const target = path.resolve(cwd, files[0]);
    try {
      const r = await runThenRun({
        filePath: target,
        cwd,
        spec,
        timeoutMs: config.actionFusionConfig.thenRun.timeoutSec * 1000,
        maxOutputChars: config.actionFusionConfig.thenRun.maxOutputChars,
      });
      if (r.status === "succeeded") return r.output ? `${r.marker}\n$ ${spec.command}\n${r.output}` : `${r.marker}\n$ ${spec.command}`;
      if (r.status === "skipped") return `${r.marker} ${r.output}`;
      const exit = r.exitCode !== undefined ? ` (exit code ${r.exitCode})` : r.timedOut ? " (timeout)" : "";
      return `${r.marker}${exit}\n$ ${spec.command}\n${r.output}`;
    } catch (e) {
      notify(ctx, `[SoL-Pi Action Fusion] then_run error: ${(e as Error).message}`);
      return `${THEN_RUN_FAILED}\n$ ${spec.command}\n${(e as Error).message}`;
    }
  };

  // -------------------------------------------------------------------------
  // Evidence-Preserving Reducer: large build/test logs -> verified receipt.
  // -------------------------------------------------------------------------
  pi.on("tool_result", async (event: ToolEvent, ctx: Ctx) => {
    const name = String(event.toolName ?? event.tool ?? "tool");
    const rc = config.evidencePreservingReducerConfig;
    const command = typeof event.input?.command === "string" ? event.input.command : "";
    if (!rc.enabled || name !== "bash" || !isBuildOrTestCommand(command)) return undefined;
    const slot = textSlots(event).find((s) => Buffer.byteLength(s.get()) >= rc.minBytesThreshold);
    if (!slot) return undefined;
    const raw = slot.get();
    const exitCode = resolveExitCode(event);
    const key = event.toolCallId || createHash("sha256").update(name).update("\0").update(raw).digest("hex").slice(0, 24);

    const cached = journal?.entries.get(key);
    if (cached?.status === "applied" && cached.receipt) {
      slot.set(cached.receipt);
      stats.reduced++;
      return undefined;
    }
    if (!rc.provider || !rc.model || !ctx.modelRegistry) {
      return undefined; // nothing to call; leave the raw log intact
    }
    if (reducerCalls >= rc.maxCallsPerSession) {
      journal?.record({ key, status: "fallback", reason: "call-budget" });
      return undefined;
    }
    const model = ctx.modelRegistry.find(rc.provider, rc.model);
    if (!model) {
      notify(ctx, `[SoL-Pi Reducer] model ${rc.provider}/${rc.model} is not available; log left unreduced.`);
      journal?.record({ key, status: "fallback", reason: "no-model" });
      return undefined;
    }

    reducerCalls++;
    try {
      const masked = redactSecrets(raw);
      const sessionDir = ctx.sessionManager?.getSessionDir?.();
      const archive = archiveObservation(name, raw, config, masked, sessionDir);
      const prompt = buildReducerProviderPrompt({
        toolName: name,
        command,
        exitCode,
        maskedLog: masked,
        maxChars: rc.maxProviderChars,
      });
      const signal = AbortSignal.timeout(rc.timeoutMs);
      const res = await completeSimple(
        model as Parameters<typeof completeSimple>[0],
        { systemPrompt: ["You compress logs into evidence-preserving receipts. Reply with JSON only."], messages: [{ role: "user", content: prompt, timestamp: Date.now() }] },
        {
          apiKey: ctx.modelRegistry.resolver(model, ctx.sessionManager?.getSessionId?.()) as string,
          maxTokens: 2048,
          temperature: 0,
          disableReasoning: true,
          signal,
        },
      );
      if (res.stopReason === "error" || res.stopReason === "aborted") {
        throw new Error(res.errorMessage ?? `provider stopped: ${res.stopReason}`);
      }
      const providerText = res.content
        .filter((c: { type: string }) => c.type === "text")
        .map((c: { type: string; text?: string }) => c.text ?? "")
        .join("\n");
      const receipt = buildEvidenceReceipt({
        toolName: name,
        exitCode,
        rawLog: raw,
        providerText,
        archivePath: archive.archivePath,
        maxFindings: rc.maxFindings,
        maxEvidence: rc.maxEvidence,
        minAcceptedRatio: rc.minAcceptedRatio,
      });
      if (!receipt.ok || !receipt.receipt) {
        journal?.record({ key, status: "fallback", reason: receipt.reason, archivePath: archive.archivePath });
        stats.reducedFallback++;
        notify(ctx, `[SoL-Pi Reducer] provider reduction failed; deterministic fallback used: ${receipt.reason}`);
        // Fail closed to the deterministic excerpt; it archives the same masked raw log.
        deterministicFallback(ctx, slot, command, raw, exitCode);
        return undefined;
      }
      journal?.record({
        key,
        status: "applied",
        receipt: receipt.receipt,
        archivePath: archive.archivePath,
        receiptBytes: Buffer.byteLength(receipt.receipt),
        archiveBytes: Buffer.byteLength(raw),
      });
      slot.set(receipt.receipt);
      stats.reduced++;
      return undefined;
    } catch (e) {
      stats.reducedFallback++;
      journal?.record({ key, status: "fallback", reason: `error:${(e as Error).message.slice(0, 120)}` });
      notify(ctx, `[SoL-Pi Reducer] provider reduction failed; deterministic fallback used: ${(e as Error).message}`);
      deterministicFallback(ctx, slot, command, raw, exitCode);
      return undefined;
    }
  });

  /** Deterministic excerpt path; a failure here leaves the raw log in place and is reported. */
  const deterministicFallback = (ctx: Ctx, slot: Slot, command: string, raw: string, exitCode: number | undefined) => {
    try {
      const det = reduceAndArchive(command, raw, exitCode, config);
      if (det.reduced) slot.set(det.text);
    } catch (e) {
      notify(ctx, `[SoL-Pi Reducer] reducer could not archive; output left untouched: ${(e as Error).message}`);
    }
  };

  // -------------------------------------------------------------------------
  // ObservationPack: rewrite the request projection, not the history.
  // -------------------------------------------------------------------------
  pi.on("context", async (event: ContextEvent, ctx: Ctx) => {
    lastUsage = ctx.getContextUsage?.() ?? lastUsage;
    const messages = event.messages ?? [];
    lastProjection = messages;
    let packed;
    try {
      packed = packProjectionMessages(messages, {
        config,
        archiveDir,
        archived,
        sessionDir: ctx.sessionManager?.getSessionDir?.(),
      });
    } catch (e) {
      notify(ctx, `[SoL-Pi ObservationPack] observation pack skipped this request: ${(e as Error).message}`);
      return undefined;
    }
    if (packed.packed.length === 0) return undefined;
    stats.packed += packed.packed.length;
    stats.rawBytes += packed.packed.reduce((s, p) => s + p.bytes, 0);
    stats.savedBytes += packed.savedBytes;
    const next: ContextEvent = { messages: packed.messages };
    return { messages: next.messages };
  });

  // -------------------------------------------------------------------------
  // Usage accounting + Pricing Cliff advisory (unchanged).
  // -------------------------------------------------------------------------
  pi.on("turn_end", async (event: TurnEvent, ctx: Ctx) => {
    const usage = event.message?.usage;
    if (usage) {
      state.requestCount++;
      state.outputTokens += Math.max(0, usage.output ?? usage.outputTokens ?? 0);
      lastUsage = lastUsage ?? (ctx.getContextUsage?.() ?? undefined);
    }
    if (!usage || !config.pricingCliffAdvisoryConfig.enabled) return;
    const tokens = usageContextTokens(usage);
    if (tokens === undefined) return;
    const modelId = String(event.message?.model ?? ctx.model?.id ?? "");
    const advice = evaluateOnlineCompaction(tokens, modelId, config.cacheWriteReadRatio, config);
    lastAdvice = advice.message;
    if (advice.level !== lastLevel && advice.level !== "ok") notify(ctx, `[SoL-Pi] ${advice.message}`);
    lastLevel = advice.level;
  });

  // -------------------------------------------------------------------------
  // Online compaction at settle boundaries.
  // -------------------------------------------------------------------------
  const maybeCompact = async (boundary: "agent_end" | "session_stop", ctx: Ctx): Promise<void> => {
    const oc = config.onlineContextCompactConfig;
    if (!oc.enabled || !ctx.compact) return;
    if (boundary === "agent_end" && !oc.compactOnSubtaskBoundary) return;
    const usage = ctx.getContextUsage?.() ?? lastUsage;
    const archiveTokens = archiveTokensFor(lastProjection, oc.keepRecentTokens);
    const decision = decideCompaction({ usage, state, archiveTokens, config });
    if (!decision.compact) return;
    state.pendingCompaction = true;
    persist();
    try {
      await ctx.compact({ internalGuidance: compactionInstructions(state) });
      state.compactions++;
      stats.compactions++;
      state.lastCompactionAt = Date.now();
    } catch (e) {
      notify(ctx, `[SoL-Pi] boundary compaction did not run: ${(e as Error).message}`, "info");
    } finally {
      state.pendingCompaction = false;
      persist();
    }
  };

  pi.on("agent_end", async (event: AgentEndEvent, ctx: Ctx) => {
    if (event.willContinue || event.awaitingAsyncWork) return;
    await maybeCompact("agent_end", ctx);
  });

  pi.on("session_stop", async (_event: unknown, ctx: Ctx) => {
    await maybeCompact("session_stop", ctx);
    return undefined;
  });

  // An unneeded native compaction (usage below window - reserve) is cancelled.
  pi.on("session_before_compact", async (_event: unknown, ctx: Ctx) => {
    if (state.pendingCompaction) return undefined;
    const usage = ctx.getContextUsage?.() ?? lastUsage;
    if (!usage || usage.contextWindow <= 0) return undefined;
    const reserve = config.onlineContextCompactConfig.outputReserveTokens;
    if (usage.tokens < usage.contextWindow - reserve) {
      notify(ctx, "[SoL-Pi] skipped a compaction: context is below window - reserve.", "info");
      return { cancel: true };
    }
    return undefined;
  });

  // -------------------------------------------------------------------------
  // Correction tracking.
  // -------------------------------------------------------------------------
  pi.on("input", async (event: InputEvent) => {
    if (event.source && event.source !== "interactive") return;
    if (event.text && CORRECTION_RE.test(event.text)) {
      state.corrections++;
      persist();
    }
    return undefined;
  });

  // -------------------------------------------------------------------------
  // update_plan tool (upstream online-context-compact plan state).
  // -------------------------------------------------------------------------
  pi.registerTool({
    name: "update_plan",
    label: "Update Plan",
    loadMode: "essential",
    approval: "read",
    description:
      "Create or update the session plan. Steps move pending -> in_progress -> completed; completed steps are terminal. Returns the normalized plan plus diagnostics.",
    parameters: {
      type: "object",
      properties: {
        plan: {
          type: "array",
          description: "The full plan, in order. Replaces the previous plan.",
          items: {
            type: "object",
            properties: {
              step: { type: "string", description: "One concrete step (<= 200 chars)." },
              status: { type: "string", enum: ["pending", "in_progress", "completed"] },
            },
            required: ["step", "status"],
          },
        },
      },
      required: ["plan"],
    },
    async execute(_toolCallId: string, params: { plan?: unknown }) {
      const normalized = normalizePlan(params?.plan);
      const transition = applyPlanTransition(state.plan, normalized.plan);
      state.plan = transition.plan;
      persist();
      const diagnostics = [...normalized.diagnostics, ...transition.diagnostics];
      const text = [formatPlanSnapshot(state.plan), diagnostics.length ? `Diagnostics:\n- ${diagnostics.join("\n- ")}` : ""]
        .filter(Boolean)
        .join("\n\n");
      return { content: [{ type: "text", text }] };
    },
  });

  // -------------------------------------------------------------------------
  // obs_recall tool: paged read of an archived observation.
  // -------------------------------------------------------------------------
  pi.registerTool({
    name: "obs_recall",
    label: "Recall Observation",
    loadMode: "essential",
    approval: "read",
    description:
      "Read a line range of a tool result archived by SoL-Pi's ObservationPack. Use the id from a '[large tool result replaced...]' placeholder.",
    parameters: {
      type: "object",
      properties: {
        id: { type: "string", description: "Observation id (obs_...)." },
        offset: { type: "number", description: "First line, 1-based (default 1)." },
        limit: { type: "number", description: "Lines to return (default 120)." },
      },
      required: ["id"],
    },
    async execute(_toolCallId: string, params: { id?: string; offset?: number; limit?: number }, _signal: InterruptSignal | undefined, _onUpdate: unknown, ctx: Ctx) {
      const dir = resolveArchiveDir(config, ctx.sessionManager?.getSessionDir?.());
      const page = readObservationChunk(dir, String(params?.id ?? ""), params?.offset, params?.limit, config);
      stats.recalled++;
      const text = [
        `obs ${page.id}: lines ${page.startLine}-${page.endLine} of ${page.totalLines} (${page.totalBytes} bytes, ${page.path})`,
        page.text,
        page.hasMore ? `[more lines available: call again with offset=${page.endLine + 1}]` : "",
      ]
        .filter(Boolean)
        .join("\n");
      return { content: [{ type: "text", text }] };
    },
  });

  // -------------------------------------------------------------------------
  // /sol-pi status command
  // -------------------------------------------------------------------------
  pi.registerCommand("sol-pi", {
    description: "SoL-Pi enforcement: /sol-pi [status|verify|stats]",
    handler: async (args: string, ctx: Ctx) => {
      const action = (args || "status").trim().toLowerCase();
      const cwd = ctx.cwd || process.cwd();
      const c = config;
      let msg: string;
      if (action === "verify") {
        const files = [...editedFiles];
        const rows: string[] = [];
        for (const f of files) {
          try {
            const r = await runActionFusionValidator(f, cwd, c);
            rows.push(`• ${f}: ${r.ran ? (r.ok ? "ok" : `FAIL${r.timedOut ? " (timeout)" : ""}`) : `skipped (${r.reason})`}`);
          } catch (e) {
            rows.push(`• ${f}: error (${(e as Error).message})`);
          }
        }
        msg = files.length ? `Action Fusion re-verify:\n${rows.join("\n")}` : "No edited files tracked in this session.";
      } else if (action === "stats") {
        msg =
          `ObservationPack: ${stats.packed} packed, saved ${stats.savedBytes} bytes in requests, ${stats.recalled} recalls; ` +
          `Reducer: ${stats.reduced} applied (${stats.reducedFallback} fallbacks); Compactions: ${stats.compactions}`;
      } else {
        const mean = state.requestCount > 0 ? (state.outputTokens / state.requestCount).toFixed(0) : "n/a";
        msg = [
          "SoL-Pi status:",
          `• Action Fusion: ${c.actionFusionConfig.enabled} (barrier ${c.actionFusionConfig.barrier}, timeout ${c.actionFusionConfig.timeoutMs}ms, post-failure bash ${postFailureBash})`,
          `• ObservationPack: ${c.observationPackConfig.enabled} (>${c.observationPackConfig.minBytesThreshold}B, full replay ${c.observationPackConfig.fullReplayTurns} requests, archive ${archiveDir})`,
          `• Reducer: ${c.evidencePreservingReducerConfig.enabled} (${c.evidencePreservingReducerConfig.provider}/${c.evidencePreservingReducerConfig.model}, >${c.evidencePreservingReducerConfig.minBytesThreshold}B, ${reducerCalls}/${c.evidencePreservingReducerConfig.maxCallsPerSession} calls)`,
          `• Compaction: ${c.onlineContextCompactConfig.enabled} (trigger <${c.onlineContextCompactConfig.remainingRequestsTrigger} req, mean output ${mean}, done ${state.compactions}, pending ${state.pendingCompaction})`,
          `• Cliff advisory: level=${lastLevel}${lastAdvice ? ` — ${lastAdvice}` : ""}`,
          `• Plan: ${state.plan.length} steps, corrections ${state.corrections}`,
        ].join("\n");
      }
      ctx.ui?.notify?.(msg, "info");
    },
  });
}

export default function (pi: ExtensionAPI) {
  register(pi);
}
