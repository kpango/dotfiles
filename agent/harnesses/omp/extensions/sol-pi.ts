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
 *    into an upstream-contract receipt (schema + source hash + status + verified
 *    evidence) whose every quote must occur byte for byte in the archived log;
 *    failures fall back to the deterministic excerpt (never a fabricated receipt).
 *    Receipts are journalled so a restart never pays twice.
 * 4. Online compaction — Upstream economics (breakeven vs. the plan-boundary request
 *    horizon, cache-debt repayment, post-compaction cooldown, absolute window
 *    protection). At a settle boundary the decision is priced; window protection
 *    stays absolute, everything else is deferred while cooldown/debt forbid it. An
 *    unneeded native compaction (usage below window−reserve) is cancelled.
 *
 * The `/sol-pi` command reports status; nothing here switches models.
 */
import { createHash } from "node:crypto";
import * as fs from "node:fs/promises";
import * as path from "node:path";
import { completeSimple } from "@oh-my-pi/pi-ai";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
  ONLINE_STATE_ENTRY,
  PLAN_STATUSES,
  ReducerJournal,
  analyzePlanTransition,
  archiveObservation,
  archiveTokensFor,
  COMPACTION_FAILED_RESUME_REMINDER,
  POST_COMPACTION_PLAN_REMINDER,
  RECOVERABLE_COMPACTION_ERRORS,
  SKIPPED_COMPACTION_REMINDER,
  DIAGNOSTIC_COMMAND,
  estimateMessageTokens,
  isObj,
  parsePlanSteps,
  parseProgressSummary,
  restoreOnlineState,
  MAX_PLAN_STEPS,
  type CompactionDecision,
  type ProgressSummary,
  evidenceReceiptText,
  EXIT_STATUS_LINE,
  LIKELY_SECRET,
  reducerInput,
  reducerInstructions,
  reducerPromptBody,
  sha256hex,
  validateEvidenceReceipt,
  type ReceiptProvider,
  compactionInstructions,
  decideCompaction,
  DEFAULT_NATIVE_SUMMARY_TOKEN_ESTIMATE,
  detectEditThenBash,
  parseThenRun,
  runThenRun,
  evaluateOnlineCompaction,
  formatPlanSnapshot,
  initialOnlineState,
  isEditTool,
  loadSolPiConfig,
  packProjectionMessages,
  recordBoundary,
  recordCompaction,
  recordCompletedPlanHandoff,
  recordCorrection,
  recordProviderRequest,
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
  THEN_RUN_SUCCEEDED,
  THEN_RUN_SKIPPED,
  type SolPiConfig,
  type ThenRunSpec,
} from "./lib/sol-pi-core";
import { extractWrittenPaths } from "./stop-verify";

interface TextPart {
  type?: string;
  text?: string;
}
interface ToolDetails {
  exitCode?: number;
  timedOut?: boolean;
  meta?: { truncation?: { artifactId?: string } };
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
  details?: ToolDetails;
}
interface Reducible {
  command: string;
  body: string;
  /** undefined = the result carried no exit signal (never rendered as 0) */
  exitFailed: boolean | undefined;
  apply: (receipt: string) => void;
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
  model?: { id?: string; contextWindow?: number };
  ui?: { notify?: (msg: string, level: "info" | "warning" | "error") => void };
  getContextUsage?: () => { tokens: number; contextWindow: number; percent: number } | undefined;
  getSystemPrompt?: () => string[];
  isIdle?: () => boolean;
  abort?: () => void;
  compact?: (opts?: { internalGuidance?: string; customInstructions?: string }) => Promise<void>;
  sessionManager?: {
    getSessionDir?: () => string;
    getSessionId?: () => string;
    getBranch?: () => { type?: string; customType?: string; data?: unknown }[];
    getArtifactPath?: (id: string) => Promise<string | null>;
  };
  modelRegistry?: {
    find: (provider: string, modelId: string) => unknown;
    resolver: (model: unknown, sessionId?: string) => unknown;
  };
}
interface TurnEvent {
  message?: { model?: string; usage?: UsageLike; role?: string; stopReason?: string };
  toolResults?: { toolName?: string; toolCallId?: string; isError?: boolean }[];
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
  let lastUsage: { tokens: number; contextWindow: number } | undefined;
  let reducerCalls = 0;
  // Upstream online-context-compact runtime (session-scoped, never persisted).
  // `pendingBoundary` is armed by update_plan, `selected` holds the priced
  // boundary compaction that runs once the run settles.
  let pendingBoundary: { toolCallId: string } | undefined;
  let selected: { decision: CompactionDecision } | undefined;
  let activeDebt: { debtTokens: number; repaymentTokens: number } | undefined;
  let compactionInFlight = false;
  let requestPending = false;
  let compactionRefused = false;
  let observedMessages: unknown[] = [];
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
  const resetOnlineRuntime = () => {
    observedMessages = [];
    pendingBoundary = undefined;
    selected = undefined;
    activeDebt = undefined;
    compactionInFlight = false;
    requestPending = false;
    compactionRefused = false;
  };
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
    lastValidatorFailed = false;
    postFailureBash = 0;
    lastLevel = "ok";
    lastAdvice = "";
    stats.packed = stats.rawBytes = stats.savedBytes = stats.reduced = stats.reducedFallback = stats.recalled = stats.compactions = 0;
    resetOnlineRuntime();
    state = restoreOnlineState(ctx.sessionManager?.getBranch?.() ?? []);
    const sessionDir = ctx.sessionManager?.getSessionDir?.() ?? undefined;
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
    let thenRunFailed = false;
    if (thenRun) {
      const fused = await fuseThenRun(ctx, cwd, name, thenRun, files, failed);
      extras.push(fused.text);
      thenRunFailed = fused.failed;
    }
    if (extras.length === 0) return undefined;
    const result: { content: { type: string; text: string }[]; isError?: boolean } = {
      content: [...(Array.isArray(event.content) ? event.content : []), ...extras.map((text) => ({ type: "text", text }))],
    };
    // Upstream marks a failed/skipped fused command as a failed tool result, so the model
    // cannot mistake the mutation's success for the command's outcome.
    if (thenRunFailed) result.isError = true;
    return result;
  });

  /**
   * Run the edit call's `then_run` in the same observation as the mutation.
   * A failed mutation never reaches the command (`[then_run:skipped]`); the
   * mutation stays applied either way, and the marker is always present.
   * `failed` mirrors upstream, which reports a failed or skipped fused command as
   * a failed tool result (`isError`).
   */
  const fuseThenRun = async (
    ctx: Ctx,
    cwd: string,
    toolName: string,
    spec: ThenRunSpec,
    files: string[],
    mutationFailed: boolean,
  ): Promise<{ text: string; failed: boolean }> => {
    if (mutationFailed) return { text: `${THEN_RUN_SKIPPED} ${toolName} did not complete successfully; the command was not run.`, failed: true };
    if (files.length === 0) return { text: `${THEN_RUN_SKIPPED} no edited file was recorded for this call; the command was not run.`, failed: true };
    const target = path.resolve(cwd, files[0]);
    try {
      const r = await runThenRun({
        filePath: target,
        cwd,
        spec,
        timeoutMs: config.actionFusionConfig.thenRun.timeoutSec * 1000,
        maxOutputChars: config.actionFusionConfig.thenRun.maxOutputChars,
      });
      if (r.status === "succeeded") {
        return { text: r.output ? `${r.marker}\n$ ${spec.command}\n${r.output}` : `${r.marker}\n$ ${spec.command}`, failed: false };
      }
      if (r.status === "skipped") return { text: `${r.marker} ${r.output}`, failed: true };
      const exit = r.exitCode !== undefined ? ` (exit code ${r.exitCode})` : r.timedOut ? " (timeout)" : "";
      return { text: `${r.marker}${exit}\n$ ${spec.command}\n${r.output}`, failed: true };
    } catch (e) {
      notify(ctx, `[SoL-Pi Action Fusion] then_run error: ${(e as Error).message}`);
      return { text: `${THEN_RUN_FAILED}\n$ ${spec.command}\n${(e as Error).message}`, failed: true };
    }
  };

  // -------------------------------------------------------------------------
  // Evidence-Preserving Reducer: large build/test logs -> verified receipt.
  //
  // Candidate = a bash result whose command is a build/test invocation, or an
  // edit/write result whose fused `then_run` appended a marker. The body is the
  // exact command output (the session artifact when the tool spilled it), the
  // receipt follows the upstream contract (schema, source hash, status,
  // uncertain, verified evidence), and a rejected receipt falls back to the
  // deterministic excerpt.
  // -------------------------------------------------------------------------
  const exactBody = async (inline: string, details: ToolDetails | undefined, ctx: Ctx): Promise<string> => {
    const id = details?.meta?.truncation?.artifactId ?? inline.match(/local:\/\/(\d+)\.log/u)?.[1];
    if (!id || !ctx.sessionManager?.getArtifactPath) return inline;
    try {
      const file = await ctx.sessionManager.getArtifactPath(id);
      return file ? await fs.readFile(file, "utf8") : inline;
    } catch {
      return inline;
    }
  };

  const inlineExitFailed = (inline: string): boolean | undefined => {
    const match = inline.match(EXIT_STATUS_LINE);
    return match ? Number(match[1]) !== 0 : undefined;
  };

  const reducibleResult = async (event: ToolEvent, details: ToolDetails | undefined, ctx: Ctx): Promise<Reducible | undefined> => {
    const name = String(event.toolName ?? event.tool ?? "tool");
    if (name === "bash") {
      const command = typeof event.input?.command === "string" ? event.input.command : "";
      const slot = textSlots(event)[0];
      if (!command || !slot) return undefined;
      const inline = slot.get();
      const exitCode = typeof details?.exitCode === "number" ? details.exitCode : undefined;
      return {
        command,
        body: await exactBody(inline, details, ctx),
        exitFailed: exitCode !== undefined ? exitCode !== 0 : inlineExitFailed(inline),
        apply: (receipt) => slot.set(receipt),
      };
    }
    if (name !== "write" && name !== "edit") return undefined;
    const spec = parseThenRun(event.input?.then_run);
    if (!spec?.command) return undefined;
    for (const slot of textSlots(event)) {
      const text = slot.get();
      // The first marker in the block is the one action fusion wrote; the
      // command's own output may quote either marker later on.
      const succeeded = text.indexOf(THEN_RUN_SUCCEEDED);
      const failed = text.indexOf(THEN_RUN_FAILED);
      const markerIndex = succeeded < 0 ? failed : failed < 0 ? succeeded : Math.min(succeeded, failed);
      if (markerIndex < 0) continue;
      const marker = text.startsWith(THEN_RUN_FAILED, markerIndex) ? THEN_RUN_FAILED : THEN_RUN_SUCCEEDED;
      const suffixStart = markerIndex + marker.length;
      const suffix = text.slice(suffixStart);
      const separator = suffix.match(/^(?:\r?\n)+/u)?.[0] ?? "\n";
      const inline = suffix.slice(separator.length);
      return {
        command: spec.command,
        body: await exactBody(inline, details, ctx),
        // Fused results carry no structured exit code, so a failed marker or
        // pi's own status line decides; a passing command whose last line reads
        // like a status notice is left unreduced (conservative).
        exitFailed: marker === THEN_RUN_FAILED || inlineExitFailed(inline) === true,
        apply: (receipt) => slot.set(`${text.slice(0, suffixStart)}${separator}${receipt}`),
      };
    }
    return undefined;
  };

  pi.on("tool_result", async (event: ToolEvent, ctx: Ctx) => {
    const rc = config.evidencePreservingReducerConfig;
    if (!rc.enabled) return undefined;
    const details = event.details;
    const reducible = await reducibleResult(event, details, ctx);
    if (!reducible || !DIAGNOSTIC_COMMAND.test(reducible.command)) return undefined;
    const { command, body, exitFailed, apply } = reducible;
    if (Buffer.byteLength(body) < rc.minBytesThreshold) return undefined;
    const isError = Boolean(event.isError);
    const key = event.toolCallId || createHash("sha256").update(reducible.command).update("\0").update(body).digest("hex").slice(0, 24);
    const logFallback = (reason: string, extra: Record<string, unknown> = {}) => journal?.record({ key, status: "fallback", reason, ...extra });

    if (exitFailed !== undefined && exitFailed !== isError) {
      logFallback("exit-state-mismatch", { isError, exitFailed });
      return undefined;
    }
    if (body.length > rc.maxInputBytes) {
      logFallback("source-over-max-chars", { sourceChars: body.length, maxChars: rc.maxInputBytes });
      return undefined;
    }
    if (LIKELY_SECRET.test(body)) {
      logFallback("likely-secret");
      return undefined;
    }

    const cached = journal?.entries.get(key);
    if (cached?.status === "applied" && cached.receipt) {
      apply(cached.receipt);
      stats.reduced++;
      return undefined;
    }
    if (!rc.provider || !rc.model || !ctx.modelRegistry) return undefined; // nothing to call; leave the raw log intact
    if (reducerCalls >= rc.maxCallsPerSession) {
      logFallback("call-budget");
      return undefined;
    }
    const model = ctx.modelRegistry.find(rc.provider, rc.model);
    if (!model) {
      notify(ctx, `[SoL-Pi Reducer] model ${rc.provider}/${rc.model} is not available; log left unreduced.`);
      logFallback("reducer-model-unavailable");
      return undefined;
    }

    // The body the model and the receipt both refer to is the masked log.
    const masked = redactSecrets(body);
    let archive: { archivePath: string };
    try {
      archive = archiveObservation(String(event.toolName ?? "bash"), body, config, masked, ctx.sessionManager?.getSessionDir?.());
    } catch (e) {
      logFallback("archive-failed", { error: (e as Error).message.slice(0, 120) });
      notify(ctx, `[SoL-Pi Reducer] reducer could not archive; output left untouched: ${(e as Error).message}`);
      return undefined;
    }
    const source = {
      hash: sha256hex(masked),
      bytes: Buffer.byteLength(masked),
      lines: masked === "" ? 0 : masked.split("\n").length,
      path: archive.archivePath,
    };
    reducerCalls++;
    let providerText = "";
    let provider: ReceiptProvider = { provider: rc.provider, model: rc.model, totalTokens: 0 };
    try {
      const prompt = reducerInput(command, isError, source, promptBody(masked, rc.maxProviderChars));
      const res = await completeSimple(
        model as Parameters<typeof completeSimple>[0],
        { systemPrompt: [reducerInstructions()], messages: [{ role: "user", content: prompt, timestamp: Date.now() }] },
        {
          apiKey: ctx.modelRegistry.resolver(model, ctx.sessionManager?.getSessionId?.()) as string,
          maxTokens: 2048,
          temperature: 0,
          disableReasoning: true,
          signal: AbortSignal.timeout(rc.timeoutMs),
        },
      );
      providerText = res.content
        .filter((c: { type: string }) => c.type === "text")
        .map((c: { type: string; text?: string }) => c.text ?? "")
        .join("");
      provider = {
        provider: typeof res.provider === "string" ? res.provider : rc.provider,
        model: typeof res.model === "string" ? res.model : rc.model,
        totalTokens: typeof res.usage?.totalTokens === "number" ? res.usage.totalTokens : 0,
      };
      if (res.stopReason !== "stop" && res.stopReason !== "length") {
        logFallback("model-response-error", { stopReason: res.stopReason, errorMessage: res.errorMessage });
        stats.reducedFallback++;
        deterministicFallback(ctx, apply, command, body, resolveExitCode(event));
        return undefined;
      }
    } catch (e) {
      const name = (e as Error).name;
      logFallback(name === "AbortError" || name === "TimeoutError" ? "model-call-timeout" : "model-call-exception", {
        error: (e as Error).message.slice(0, 120),
      });
      stats.reducedFallback++;
      notify(ctx, `[SoL-Pi Reducer] provider reduction failed; deterministic fallback used: ${(e as Error).message}`);
      deterministicFallback(ctx, apply, command, body, resolveExitCode(event));
      return undefined;
    }

    const checked = validateEvidenceReceipt(providerText, source, masked, isError);
    if (!checked.ok) {
      journal(checked.reason, { archivePath: archive.archivePath });
      stats.reducedFallback++;
      notify(ctx, `[SoL-Pi Reducer] provider reduction failed; deterministic fallback used: ${checked.reason}`);
      deterministicFallback(ctx, apply, command, body, resolveExitCode(event));
      return undefined;
    }
    const receipt = evidenceReceiptText(command, source, checked.value, provider);
    const receiptBytes = Buffer.byteLength(receipt);
    if (receiptBytes >= source.bytes * (rc.minAcceptedRatio || 1)) {
      logFallback("receipt-not-smaller", { receiptBytes, archiveBytes: source.bytes });
      stats.reducedFallback++;
      deterministicFallback(ctx, apply, command, body, resolveExitCode(event));
      return undefined;
    }
    journal?.record({
      key,
      status: "applied",
      receipt,
      archivePath: archive.archivePath,
      receiptBytes,
      archiveBytes: source.bytes,
    });
    apply(receipt);
    stats.reduced++;
    return undefined;
  });

  /** Deterministic excerpt path; a failure here leaves the raw log in place and is reported. */
  const deterministicFallback = (
    ctx: Ctx,
    apply: (text: string) => void,
    command: string,
    raw: string,
    exitCode: number | undefined,
  ) => {
    try {
      const det = reduceAndArchive(command, raw, exitCode, config);
      if (det.reduced) apply(det.text);
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
    observedMessages = messages;
    requestPending = true;
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
    observedMessages = packed.messages;
    stats.packed += packed.packed.length;
    stats.rawBytes += packed.packed.reduce((s, p) => s + p.bytes, 0);
    stats.savedBytes += packed.savedBytes;
    const next: ContextEvent = { messages: packed.messages };
    return { messages: next.messages };
  });

  // -------------------------------------------------------------------------
  // Provider-request accounting (upstream records one request at every
  // before_provider_request, with the context size the request actually sent).
  // -------------------------------------------------------------------------
  const requestContextTokens = (ctx: Ctx): number => {
    const system = (ctx.getSystemPrompt?.() ?? []).join("\n");
    const estimated =
      observedMessages.reduce((sum, message) => sum + estimateMessageTokens(message), 0) + Math.ceil(system.length / 4);
    const reported = ctx.getContextUsage?.()?.tokens;
    if (typeof reported === "number" && Number.isSafeInteger(reported) && reported > 0) return Math.max(reported, estimated);
    return estimated;
  };

  pi.on("before_provider_request", async (_event: unknown, ctx: Ctx) => {
    if (!requestPending) return undefined;
    requestPending = false;
    state = recordProviderRequest(state, requestContextTokens(ctx));
    persist();
    return undefined;
  });

  // A completed assistant turn carries the provider usage, so the next request
  // is not counted again when a retry replays an aborted response.
  pi.on("message_end", async (event: { message?: { role?: string } }) => {
    if (event.message?.role === "assistant") requestPending = false;
    return undefined;
  });

  // Branch navigation restores that branch's newest state entry; a session
  // switch or clear starts with nothing carried over.
  pi.on("session_tree", async (_event: unknown, ctx: Ctx) => {
    resetOnlineRuntime();
    state = restoreOnlineState(ctx.sessionManager?.getBranch?.() ?? []);
    persist();
    return undefined;
  });

  pi.on("session_switch", async () => {
    resetOnlineRuntime();
    state = initialOnlineState();
    return undefined;
  });

  pi.on("session_clear", async () => {
    resetOnlineRuntime();
    state = initialOnlineState();
    return undefined;
  });

  // -------------------------------------------------------------------------
  // Usage accounting + Pricing Cliff advisory (unchanged).
  // -------------------------------------------------------------------------
  pi.on("turn_end", async (event: TurnEvent, ctx: Ctx) => {
    const usage = event.message?.usage;
    if (usage) {
      state.outputTokens += Math.max(0, usage.output ?? usage.outputTokens ?? 0);
      lastUsage = lastUsage ?? (ctx.getContextUsage?.() ?? undefined);
    }
    if (usage && config.pricingCliffAdvisoryConfig.enabled) {
      const tokens = usageContextTokens(usage);
      if (tokens !== undefined) {
        const modelId = String(event.message?.model ?? ctx.model?.id ?? "");
        const advice = evaluateOnlineCompaction(tokens, modelId, config.cacheWriteReadRatio, config);
        lastAdvice = advice.message;
        if (advice.level !== lastLevel && advice.level !== "ok") notify(ctx, `[SoL-Pi] ${advice.message}`);
        lastLevel = advice.level;
      }
    }

    // A rejected boundary must not become feasible from plan chatter alone:
    // require real tool work or new user input before pricing another one.
    const toolResults = event.toolResults ?? [];
    if (toolResults.some((result) => result.toolName !== "update_plan" && !result.isError)) compactionRefused = false;

    const subtask = config.onlineContextCompactConfig.compactOnSubtaskBoundary
      ? toolResults.find((result) => result.toolName === "task" && !result.isError)
      : undefined;
    const boundary = pendingBoundary ?? (subtask ? { toolCallId: String(subtask.toolCallId ?? "") } : undefined);
    pendingBoundary = undefined;

    const oc = config.onlineContextCompactConfig;
    if (!boundary || selected || compactionRefused || !oc.enabled || !ctx.compact) return;
    if (oc.maxCompactionsPerSession > 0 && state.nativeCompactionCount >= oc.maxCompactionsPerSession) return;
    const toolResult = toolResults.find((result) => result.toolCallId === boundary.toolCallId);
    if (event.message?.stopReason === "error" || event.message?.stopReason === "aborted") return;
    if (!toolResult || toolResult.isError) return;

    const decision = priceBoundaryCompaction(ctx);
    if (!decision?.compact) return;
    // Stop the run at this boundary; the compaction itself runs once the run
    // settles, so the summary is not written into a live turn.
    selected = { decision };
    ctx.abort?.();
  });

  // -------------------------------------------------------------------------
  // Boundary compaction (upstream online-context-compact index.ts).
  //
  // Price the pending boundary from the request the provider actually served:
  // its context size is the cache-write cost, and the archive (everything the
  // keep-tail drops) less the memo is what the compaction repays.
  // -------------------------------------------------------------------------
  const priceBoundaryCompaction = (ctx: Ctx): CompactionDecision | undefined => {
    const oc = config.onlineContextCompactConfig;
    const usage = ctx.getContextUsage?.() ?? lastUsage;
    const contextTokens = usage?.tokens ?? requestContextTokens(ctx);
    const archiveTokens = archiveTokensFor(observedMessages, oc.keepRecentTokens);
    const averageContextTokenIncrement =
      state.positiveContextDeltaCount === 0 ? null : state.positiveContextDeltaTotal / state.positiveContextDeltaCount;
    const priced = decideCompaction({
      writeTokens: contextTokens,
      archiveTokens,
      memoTokens: DEFAULT_NATIVE_SUMMARY_TOKEN_ESTIMATE,
      contextTokens,
      completedBoundaryRequestCounts: state.completedBoundaryRequestCounts,
      remainingBoundaries: state.plan.filter((step) => step.status !== "completed").length,
      averageContextTokenIncrement,
      contextWindowTokens:
        usage && usage.contextWindow > 0 ? usage.contextWindow : (ctx.model?.contextWindow ?? null),
      priorCompactionCount: state.nativeCompactionCount,
      requestsSinceLastCompaction:
        state.lastCompactionRequestCount === null ? null : state.requestCount - state.lastCompactionRequestCount,
      carriedDebtTokens: state.cacheDebtTokens,
      cacheDebtRepaymentTokens: state.cacheDebtRepaymentTokens,
      cacheWriteReadRatio: config.cacheWriteReadRatio,
      economics: { ...oc.economics, windowReserveTokens: oc.outputReserveTokens },
    });
    // A settled session has nothing to summarize: never compact without an archive.
    return priced.compact && archiveTokens === 0
      ? { ...priced, compact: false, reason: "native_not_compactable" as const }
      : priced;
  };

  const isUserAbort = (error: Error): boolean =>
    error.name === "AbortError" || error.name === "CompactionCancelledError" || error.message === "Compaction cancelled";
  const isRecoverableCompactionError = (error: Error): boolean =>
    error.name === "ManualCompactionNoOpError" || RECOVERABLE_COMPACTION_ERRORS.has(error.message);

  const continueParentTask = (ctx: Ctx, content: string): void => {
    try {
      pi.sendMessage({ customType: "sol-pi-online-context-compact", content, display: false }, { triggerTurn: true });
    } catch (e) {
      notify(ctx, `[SoL-Pi] could not resume the parent task: ${(e as Error).message}`);
    }
  };

  /**
   * Run the selected boundary compaction once the run has settled.
   *
   * A successful compaction resumes the parent task with the plan reminder (the
   * run was stopped at a safe point, so silence would look like a finished task).
   * A recoverable refusal is reported and the task resumes with the skipped
   * reminder; any other failure resumes once and is then rethrown so the real
   * error is not swallowed.
   */
  const flushSelectedCompaction = async (ctx: Ctx): Promise<void> => {
    const pending = selected;
    if (!pending || compactionInFlight || !ctx.compact) return;
    if (ctx.isIdle && !ctx.isIdle()) return;
    selected = undefined;
    activeDebt = {
      debtTokens: pending.decision.postCompactionTokens * (pending.decision.incrementalCacheCostRatio ?? 0),
      repaymentTokens: Math.max(0, pending.decision.archiveTokens - pending.decision.memoTokens),
    };
    let compacted = false;
    let compactionError: Error | undefined;
    compactionInFlight = true;
    try {
      // We dispatch our own resume turn after the compaction; without this the
      // harness would also auto-continue and double-prompt.
      await ctx.compact({ internalGuidance: compactionInstructions(state), suppressContinuation: true });
      compacted = true;
    } catch (e) {
      compactionError = e as Error;
      activeDebt = undefined;
    } finally {
      compactionInFlight = false;
    }
    const failure = compactionError && !isUserAbort(compactionError) ? compactionError : undefined;
    const recoverable = failure !== undefined && isRecoverableCompactionError(failure);
    if (recoverable) {
      compactionRefused = true;
      try {
        pi.appendEntry("sol-pi-online-context-compact-skipped", { reason: failure.message });
      } catch {
        // A banner-only session may not accept entries; the notice below still lands.
      }
      notify(ctx, `[SoL-Pi] online compaction skipped: ${failure.message}`, "warning");
    }
    const resume = compacted
      ? POST_COMPACTION_PLAN_REMINDER
      : recoverable
        ? SKIPPED_COMPACTION_REMINDER
        : failure
          ? COMPACTION_FAILED_RESUME_REMINDER
          : undefined;
    activeDebt = undefined;
    if (resume) continueParentTask(ctx, resume);
    if (failure && !recoverable) throw failure;
  };

  // `agent_end` is the run's terminal signal in OMP (willContinue covers an
  // automatic continuation), and `session_stop` catches a settle that skipped it.
  pi.on("agent_end", async (event: AgentEndEvent, ctx: Ctx) => {
    if (event.willContinue || event.awaitingAsyncWork) return;
    await flushSelectedCompaction(ctx);
  });

  pi.on("session_stop", async (_event: unknown, ctx: Ctx) => {
    await flushSelectedCompaction(ctx);
    return undefined;
  });

  // A compaction is deferred to the selected boundary: consuming it here would
  // leave the stopped run with no continuation.
  pi.on("session_before_compact", async (event: { customInstructions?: string }, ctx: Ctx) => {
    if (compactionInFlight) return undefined;
    // An explicit request (user/plan mode) carries instructions and is honored.
    if (event?.customInstructions) return undefined;
    if (selected) return { cancel: true };
    const usage = ctx.getContextUsage?.() ?? lastUsage;
    if (!usage || usage.contextWindow <= 0) return undefined;
    const reserve = config.onlineContextCompactConfig.outputReserveTokens;
    if (usage.tokens < usage.contextWindow - reserve) {
      notify(ctx, "[SoL-Pi] skipped a compaction: context is below window - reserve.", "info");
      return { cancel: true };
    }
    return undefined;
  });

  // Every committed compaction advances the epoch (the context representation
  // changed, so request spacing is measured anew); the debt carried for a
  // compaction we initiated applies to exactly that one.
  pi.on("session_compact", async (event: { fromExtension?: boolean }) => {
    const debt = event?.fromExtension || !activeDebt ? { debtTokens: 0, repaymentTokens: 0 } : activeDebt;
    state = recordCompaction(state, debt);
    stats.compactions++;
    pendingBoundary = undefined;
    selected = undefined;
    activeDebt = undefined;
    requestPending = false;
    observedMessages = [];
    persist();
    return undefined;
  });

  pi.on("session_before_tree", async () => {
    if (!compactionInFlight) return undefined;
    return { cancel: true };
  });

  // -------------------------------------------------------------------------
  // Correction tracking + completed-plan handoff (upstream index.ts).
  // -------------------------------------------------------------------------
  pi.on("input", async (event: InputEvent) => {
    // New input is a fresh start: a boundary rejected earlier may be priced again.
    compactionRefused = false;
    if (event.source && event.source !== "interactive") return undefined;
    const text = event.text ?? "";
    if (CORRECTION_RE.test(text) || text.startsWith("CORRECTION:")) {
      // A correction invalidates the boundary, its selection, and any debt.
      pendingBoundary = undefined;
      selected = undefined;
      activeDebt = undefined;
      state = recordCorrection(state);
      persist();
      return undefined;
    }
    // A new task must not inherit the completed plan's request horizon.
    const handedOff = recordCompletedPlanHandoff(state);
    if (handedOff !== state) {
      state = handedOff;
      persist();
    }
    return undefined;
  });

  // -------------------------------------------------------------------------
  // update_plan tool (upstream online-context-compact plan.ts schema).
  //
  // Steps carry a stable id, so a completed step is a boundary the compaction
  // economics can trust even after the goal text was folded into a summary.
  // -------------------------------------------------------------------------
  const stringList = (value: unknown): string[] =>
    Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];

  pi.registerTool({
    name: "update_plan",
    label: "Update Plan",
    loadMode: "essential",
    approval: "read",
    description:
      "Replace the complete working plan. Steps move pending -> in_progress -> completed; completed steps are terminal, so plan them one at a time and update as you go. Completing a previously registered unfinished step is a safe boundary where SoL-Pi may compact context when that is economical; a newly introduced completed step is recorded as history, not a boundary. Returns the plan snapshot plus diagnostics.",
    parameters: {
      type: "object",
      properties: {
        steps: {
          type: "array",
          minItems: 1,
          maxItems: MAX_PLAN_STEPS,
          description: "The complete plan, in order. Replaces the previous plan.",
          items: {
            type: "object",
            properties: {
              id: { type: "string", minLength: 1, description: "Stable step id; reuse it for the same goal." },
              goal: { type: "string", minLength: 1, description: "One concrete step." },
              status: { type: "string", enum: [...PLAN_STATUSES] },
            },
            required: ["id", "goal", "status"],
            additionalProperties: false,
          },
        },
        progress: {
          type: "object",
          description: "Evidence for the step completed in this update (files changed, verification, decisions).",
          properties: {
            files_changed: { type: "array", items: { type: "string" } },
            verification: { type: "array", items: { type: "string" } },
            decisions: { type: "array", items: { type: "string" } },
          },
          required: ["files_changed", "verification", "decisions"],
          additionalProperties: false,
        },
      },
      required: ["steps"],
      additionalProperties: false,
    },
    async execute(
      toolCallId: string,
      params: { steps?: unknown; progress?: unknown },
      signal?: InterruptSignal,
    ) {
      if (signal?.aborted) throw new Error("Plan update was aborted");
      const steps = parsePlanSteps(params?.steps);
      if (!steps || steps.length === 0) throw new Error("Plan must contain at least one valid step");
      const transition = analyzePlanTransition(state.plan, steps);
      const completedIds = transition.completedSteps.map((step) => step.id);
      const rawProgress = isObj(params?.progress) ? params.progress : undefined;
      const progress: ProgressSummary | undefined =
        completedIds.length > 0 && rawProgress
          ? parseProgressSummary({
              stepId: completedIds[0],
              goal: transition.completedSteps[0]?.goal ?? "",
              filesChanged: stringList(rawProgress.files_changed),
              verification: stringList(rawProgress.verification),
              decisions: stringList(rawProgress.decisions),
              nextWork: steps.filter((step) => step.status !== "completed").map((step) => step.goal),
            })
          : undefined;
      if (completedIds.length > 0) {
        state = recordBoundary(state, steps, progress);
        // Armed for the turn that carries this result; the run stops there.
        if (!pendingBoundary) pendingBoundary = { toolCallId };
      } else {
        state = { ...state, plan: [...steps] };
      }
      persist();
      const text = [formatPlanSnapshot(steps), ...transition.advice].join("\n");
      return {
        content: [{ type: "text", text }],
        details: {
          task_status: "active",
          plan: steps,
          boundary: completedIds.length > 0,
          completed_step_ids: completedIds,
          progress_recorded: progress !== undefined,
        },
      };
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
          `• Compaction: ${c.onlineContextCompactConfig.enabled} (economics, cooldown ${c.onlineContextCompactConfig.economics.minimumRequestsSinceCompaction} req, mean output ${mean}, committed ${state.nativeCompactionCount}, boundary pending ${selected ? "yes" : "no"})`,
          `• Cliff advisory: level=${lastLevel}${lastAdvice ? ` — ${lastAdvice}` : ""}`,
          `• Plan: epoch ${state.epoch}, ${state.plan.length} steps, ${state.pendingProgress.length} pending progress, ${state.completedBoundaryRequestCounts.length} boundary samples`,
        ].join("\n");
      }
      ctx.ui?.notify?.(msg, "info");
    },
  });
}

export default function (pi: ExtensionAPI) {
  register(pi);
}
