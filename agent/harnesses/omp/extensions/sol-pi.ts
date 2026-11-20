/**
 * SoL-Pi Runtime Enforcement Extension for Oh My Pi (OMP) — arXiv:2609.20519
 *
 * Wires lib/sol-pi-core.ts into the OMP lifecycle: Action Fusion after edits,
 * ObservationPack / Evidence-Preserving Reducer on tool results (rewritten in
 * place, like repl-context.ts), and advisory Pricing Cliff warnings.
 * Never auto-compacts or switches models.
 *
 * Interplay with repl-context.ts: repl-context (alphabetically earlier; load order is
 * unverified) first swaps outputs > 100 KiB for a small summary; this extension then only
 * sees the small text and handles the 4 KiB (reducer) / 10 KiB (pack) bands.
 */
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import {
  detectEditThenBash,
  evaluateOnlineCompaction,
  isBuildOrTestCommand,
  isEditTool,
  loadSolPiConfig,
  packObservation,
  reduceAndArchive,
  resolveExitCode,
  runActionFusionValidator,
  selectObservationReplay,
  type PackedObservation,
  type SolPiConfig,
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
  result?: unknown;
  content?: unknown;
}
interface Ctx {
  cwd?: string;
  model?: { id?: string };
  ui?: { notify?: (msg: string, level: "info" | "warning" | "error") => void };
}
interface TurnEvent {
  message?: {
    model?: string;
    usage?: {
      inputTokens?: number;
      promptTokens?: number;
      cacheReadInputTokens?: number;
      cacheReadTokens?: number;
      cacheCreationInputTokens?: number;
      cacheWriteTokens?: number;
    };
  };
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

export function register(pi: ExtensionAPI, loadConfig: () => SolPiConfig = loadSolPiConfig): void {
  let config: SolPiConfig = loadConfig();
  let turn = 0;
  const recentTools: string[] = [];
  const editedFiles = new Set<string>();
  let lastValidatorFailed = false;
  let postFailureBash = 0;
  let lastLevel: "ok" | "warn" | "exceeded" = "ok";
  let lastAdvice = "";
  const stats = { packed: 0, rawBytes: 0, compactBytes: 0, reduced: 0, reducedFallback: 0 };
  // Packed observations awaiting the fullReplayTurns expiry (best-effort in-place downgrade).
  const pending: { obs: PackedObservation; set: (v: string) => void }[] = [];

  pi.on("session_start", async () => {
    config = loadConfig();
    turn = 0;
    recentTools.length = 0;
    editedFiles.clear();
    pending.length = 0;
    lastValidatorFailed = false;
    postFailureBash = 0;
    lastLevel = "ok";
    lastAdvice = "";
    stats.packed = stats.rawBytes = stats.compactBytes = stats.reduced = stats.reducedFallback = 0;
  });

  pi.on("tool_call", async (event: ToolEvent, ctx: Ctx) => {
    recentTools.push(String(event.toolName ?? event.tool));
    if (recentTools.length > 8) recentTools.shift();
    // Only noisy when it matters: a bash right after an edit whose validator already failed.
    if (config.actionFusionConfig.enabled && lastValidatorFailed && detectEditThenBash(recentTools)) {
      postFailureBash++;
      ctx.ui?.notify?.("[SoL-Pi] Previous edit failed its validator; fix it before running further commands.", "warning");
    }
  });

  pi.on("tool_result", async (event: ToolEvent, ctx: Ctx) => {
    const name = String(event.toolName ?? event.tool ?? "tool");
    const cwd = ctx.cwd || process.cwd();
    const failed = Boolean(event.isError || event.error);
    const notify = (m: string, level: "info" | "warning" | "error" = "warning") => ctx.ui?.notify?.(m, level);

    // 1. Action Fusion: validate right after an edit, in the same turn.
    if (isEditTool(name) && !failed) {
      // write/edit は path、ast_edit と複数ヘッダの hashline edit は paths[](OMP が補う)。glob / ディレクトリは展開せず、
      // 明示的なファイルだけを検証する(1 回の編集につき上限 20)。
      const files = extractWrittenPaths(event.input).filter((p) => !/[*?[\]{}]/.test(p) && !p.endsWith("/")).slice(0, 20);
      let failedAny = false;
      for (const file of files) {
        editedFiles.add(file);
        try {
          const r = await runActionFusionValidator(file, cwd, config);
          // A timeout is inconclusive, not a failure.
          if (r.ran && !r.ok && !r.timedOut) failedAny = true;
          if (r.ran && !r.ok) {
            notify(`[SoL-Pi Action Fusion] validator ${r.timedOut ? "timed out" : "failed"} for ${file}:\n${r.output.slice(0, 1500)}`);
          }
        } catch (e) {
          notify(`[SoL-Pi Action Fusion] validator error for ${file}: ${(e as Error).message}`);
        }
      }
      if (files.length > 0) lastValidatorFailed = failedAny;
    }

    // 2. Reducer (build/test bash output) or ObservationPack (any large output): rewrite in place.
    const command = typeof event.input?.command === "string" ? event.input.command : "";
    const exitCode = resolveExitCode(event);
    const reducerApplies = name === "bash" && isBuildOrTestCommand(command);
    for (const slot of textSlots(event)) {
      const text = slot.get();
      if (reducerApplies) {
        try {
          const r = reduceAndArchive(command, text, exitCode, config);
          if (r.reduced) {
            slot.set(r.text);
            stats.reduced++;
            if (r.fallback) stats.reducedFallback++;
          }
        } catch (e) {
          notify(`[SoL-Pi] reducer could not archive the raw log; output left unreduced: ${(e as Error).message}`);
        }
        continue;
      }
      try {
        const p = packObservation(name, text, turn, config);
        if (p.packed && p.compactText) {
          stats.packed++;
          stats.rawBytes += p.bytes;
          stats.compactBytes += Buffer.byteLength(p.compactText);
          pending.push({ obs: p, set: slot.set });
        }
      } catch (e) {
        notify(`[SoL-Pi] observation pack skipped: ${(e as Error).message}`);
      }
    }
  });

  pi.on("turn_end", async (event: TurnEvent, ctx: Ctx) => {
    turn++;
    // Downgrade expired packed observations to their compact handle (fullReplayTurns elapsed).
    for (let i = pending.length - 1; i >= 0; i--) {
      const { obs, set } = pending[i];
      const replay = selectObservationReplay(obs, turn, config);
      if (replay !== obs.text) {
        set(replay);
        pending.splice(i, 1);
      }
    }
    const usage = event.message?.usage;
    if (!usage || !config.pricingCliffAdvisoryConfig.enabled) return;
    const tokens =
      (usage.inputTokens || usage.promptTokens || 0) +
      (usage.cacheReadInputTokens || usage.cacheReadTokens || 0) +
      (usage.cacheCreationInputTokens || usage.cacheWriteTokens || 0);
    const modelId = String(event.message?.model ?? ctx.model?.id ?? "");
    const advice = evaluateOnlineCompaction(tokens, modelId, config.cacheWriteReadRatio, config);
    lastAdvice = advice.message;
    if (advice.level !== lastLevel && advice.level !== "ok") ctx.ui?.notify?.(`[SoL-Pi] ${advice.message}`, "warning");
    lastLevel = advice.level;
  });

  pi.registerCommand("sol-pi", {
    description: "SoL-Pi enforcement: /sol-pi [status|verify|pack-stats]",
    handler: async (args: string, ctx: Ctx) => {
      const action = (args || "status").trim().toLowerCase();
      const cwd = ctx.cwd || process.cwd();
      let msg: string;
      if (action === "verify") {
        const files = [...editedFiles];
        const rows: string[] = [];
        for (const f of files) {
          try {
            const r = await runActionFusionValidator(f, cwd, config);
            rows.push(`• ${f}: ${r.ran ? (r.ok ? "ok" : `FAIL${r.timedOut ? " (timeout)" : ""}`) : `skipped (${r.reason})`}`);
          } catch (e) {
            rows.push(`• ${f}: error (${(e as Error).message})`);
          }
        }
        msg = files.length ? `Action Fusion re-verify:\n${rows.join("\n")}` : "No edited files tracked in this session.";
      } else if (action === "pack-stats") {
        msg =
          `ObservationPack: ${stats.packed} packed, ${stats.rawBytes} → ${stats.compactBytes} bytes (saved ${stats.rawBytes - stats.compactBytes}); ` +
          `Reducer: ${stats.reduced} reduced (${stats.reducedFallback} fail-closed fallbacks)`;
      } else {
        const c = config;
        msg = [
          "SoL-Pi status:",
          `• Action Fusion: ${c.actionFusionConfig.enabled} (timeout ${c.actionFusionConfig.timeoutMs}ms, post-failure bash ${postFailureBash})`,
          `• ObservationPack: ${c.observationPackConfig.enabled} (>${c.observationPackConfig.minBytesThreshold}B, replay ${c.observationPackConfig.fullReplayTurns} turns)`,
          `• Reducer: ${c.evidencePreservingReducerConfig.enabled} (>${c.evidencePreservingReducerConfig.minBytesThreshold}B, fail-closed ${c.evidencePreservingReducerConfig.failClosedOnQuoteMismatch})`,
          `• Cliff advisory: ${c.pricingCliffAdvisoryConfig.enabled} (online compaction action: ${c.onlineContextCompactConfig.enabled}) level=${lastLevel}${lastAdvice ? ` — ${lastAdvice}` : ""}`,
          `• Turn: ${turn}`,
        ].join("\n");
      }
      ctx.ui?.notify?.(msg, "info");
    },
  });
}

export default function (pi: ExtensionAPI) {
  register(pi);
}
