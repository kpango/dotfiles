/**
 * Main-Session Model Limit Failover Extension for Oh My Pi (OMP)
 *
 * Hooks the moment the *active session model* hits a provider limit and switches
 * the session to an available alternate model resolved from model-routing.json.
 *
 * Detection:
 *  - rate_limit       : `after_provider_response` HTTP status 429 / 529 / 503
 *  - token_exhaustion : `session_compact_failed` with reason "overflow" and not
 *                       aborted (OMP's own auto-compaction recovery already failed,
 *                       i.e. the context/token limit is genuinely exceeded).
 *
 * Fallback source of truth is model-routing.json (`tiers[].model` +
 * `tiers[].fallbacks[].trigger`). The active model is a *concrete* id
 * (e.g. "anthropic/claude-sonnet-5-5"), so we reverse-look it up inside a tier's
 * ordered `[primary, ...fallbacks]` chain and advance *forward* to the next entry
 * whose `trigger` matches — forward-only progression guarantees no switch loop
 * and lets repeated limits walk down the chain across turns (each hook re-reads
 * `ctx.model`, which reflects the previous switch). Forward-only progression is
 * loop-free for the current acyclic routing config; a config that made two tiers
 * reference each other as mutual primary/fallback could still oscillate across
 * turns (not the case today).
 *
 * subagent (`pi -p` child) failover already exists in subagents.ts and is out of
 * scope here — this extension only covers the main interactive/print session model.
 */

import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import { contextTokensFromUsage, type TurnUsage } from "./context-economy";
import { evaluateOnlineCompaction, loadSolPiConfig, pricingCliffFor, type SolPiConfig } from "./lib/sol-pi-core";
import { resolveCatalogPath } from "./lib/model-catalog";
import { refreshVerifiedModels } from "./lib/verified-models";

export type FailoverTrigger = "rate_limit" | "token_exhaustion";

export interface RoutingFallback {
  model?: string;
  trigger?: string;
}

export interface RoutingTier {
  model?: string;
  fallbacks?: RoutingFallback[];
}

/** schema.json RoutingPolicy.openCodeGoQuotaGuard (single source: agent/models/catalog.json routing_policy). */
export interface QuotaGuardPolicy {
  enabled: boolean;
  fiveHourMaxPct: number;
  weeklyMaxPct: number;
  highVolumeSubagentDefault: string;
}

export interface ModelRoutingConfig {
  tiers?: Record<string, RoutingTier>;
  routingPolicy?: { openCodeGoQuotaGuard?: QuotaGuardPolicy };
}

export interface QuotaUsage {
  fiveHourPct: number | null;
  weeklyPct: number | null;
}

export interface QuotaGuardResult {
  enabled: boolean;
  /** true: a known figure reached its limit; null: enabled but no usable figure (unknown, never reported as fine). */
  over: boolean | null;
  reasons: string[];
  recommend: string | null;
}

/** A usage figure: a number (or numeric text) in [0, 100], else null. Never guessed. */
function pctFrom(raw: unknown): number | null {
  const n = typeof raw === "number" ? raw : typeof raw === "string" && raw.trim() !== "" ? Number(raw) : Number.NaN;
  return Number.isFinite(n) && n >= 0 && n <= 100 ? n : null;
}

/**
 * Measured OpenCode Go usage: env OPENCODE_GO_USAGE_5H_PCT / OPENCODE_GO_USAGE_WEEK_PCT, else
 * ~/.omp/agent/quota/opencode-go.json ({"fiveHourPct": n, "weeklyPct": n}). Nothing in this repo measures the usage;
 * whatever does must write one of those. Same rule as `resolve-model-tier.py --quota-guard`.
 */
export function loadQuotaUsage(env: NodeJS.ProcessEnv = process.env, home: string = os.homedir()): QuotaUsage {
  let fiveHourPct = pctFrom(env.OPENCODE_GO_USAGE_5H_PCT);
  let weeklyPct = pctFrom(env.OPENCODE_GO_USAGE_WEEK_PCT);
  if (fiveHourPct === null && weeklyPct === null) {
    try {
      const data = JSON.parse(fs.readFileSync(path.join(home, ".omp", "agent", "quota", "opencode-go.json"), "utf-8"));
      if (data && typeof data === "object") {
        fiveHourPct = pctFrom((data as Record<string, unknown>).fiveHourPct);
        weeklyPct = pctFrom((data as Record<string, unknown>).weeklyPct);
      }
    } catch {
      // no usage file: both stay null (unknown)
    }
  }
  return { fiveHourPct, weeklyPct };
}

/** Pure decision. Advisory only: nothing here switches a model. */
export function evaluateQuotaGuard(policy: QuotaGuardPolicy | undefined, usage: QuotaUsage): QuotaGuardResult {
  if (!policy || policy.enabled !== true) return { enabled: false, over: false, reasons: [], recommend: null };
  const reasons: string[] = [];
  if (usage.fiveHourPct !== null && usage.fiveHourPct >= policy.fiveHourMaxPct) {
    reasons.push(`5h usage ${usage.fiveHourPct}% >= ${policy.fiveHourMaxPct}%`);
  }
  if (usage.weeklyPct !== null && usage.weeklyPct >= policy.weeklyMaxPct) {
    reasons.push(`weekly usage ${usage.weeklyPct}% >= ${policy.weeklyMaxPct}%`);
  }
  const over = reasons.length > 0 ? true : usage.fiveHourPct === null && usage.weeklyPct === null ? null : false;
  return { enabled: true, over, reasons, recommend: over ? policy.highVolumeSubagentDefault : null };
}

/** The notice for an over-quota result; undefined when there is nothing to say (under the limits, disabled, or unknown). */
export function buildQuotaAdvice(r: QuotaGuardResult): string | undefined {
  if (!r.enabled || r.over !== true) return undefined;
  return (
    `[model-failover] OpenCode Go quota guard: ${r.reasons.join(", ")}. ` +
    `高頻度の subagent fan-out は ${r.recommend} に寄せ、opencode-go の並列バッチを新たに起動しないでください。自動切替はしません。`
  );
}

/**
 * Reverse-lookup the current concrete model id inside model-routing.json and
 * return the ordered, forward-only list of candidate fallback model ids whose
 * `trigger` matches. Home-tier preference: a tier whose `.model === currentModelId`
 * (the model's "home") is preferred over tiers where it only appears as a fallback.
 *
 * Returns an ordered list (not a single value) so the caller can skip candidates
 * without configured auth and pick the first usable one. Empty list means the
 * chain is exhausted for this trigger (caller should stop and notify).
 */
export function resolveFailoverCandidates(
  routing: ModelRoutingConfig | undefined,
  currentModelId: string,
  trigger: FailoverTrigger
): string[] {
  const tiers = routing?.tiers;
  if (!tiers || !currentModelId) return [];

  const tierNames = Object.keys(tiers);
  // Two passes: prefer the tier where the current model is the primary (its home),
  // then fall back to any tier where it appears as a fallback entry.
  const homeTiers = tierNames.filter((n) => tiers[n]?.model === currentModelId);
  const otherTiers = tierNames.filter((n) => tiers[n]?.model !== currentModelId);

  for (const tierName of [...homeTiers, ...otherTiers]) {
    const tier = tiers[tierName];
    if (!tier) continue;
    const chain: RoutingFallback[] = [
      { model: tier.model },
      ...((tier.fallbacks ?? []) as RoutingFallback[]),
    ];
    const idx = chain.findIndex((e) => e.model === currentModelId);
    if (idx === -1) continue;

    const candidates: string[] = [];
    for (let i = idx + 1; i < chain.length; i++) {
      const entry = chain[i];
      if (
        entry.trigger === trigger &&
        typeof entry.model === "string" &&
        entry.model &&
        entry.model !== currentModelId
      ) {
        candidates.push(entry.model);
      }
    }
    // Only commit to this tier if it actually yields a match. When the current
    // model sits at a dead-end position in the first tier it is found in (e.g. a
    // model shared as a terminal cost_saver fallback in one tier but a mid-chain
    // rate_limit fallback in another), fall through to the remaining tiers so a
    // valid downstream trigger match is not missed. Home tiers are still tried
    // first, preserving home-tier preference.
    if (candidates.length > 0) return candidates;
  }
  return [];
}

/** Split a canonical "provider/modelId" routing string into its two parts. */
export function splitModelRef(ref: string): { provider: string; modelId: string } | undefined {
  const slash = ref.indexOf("/");
  if (slash <= 0 || slash >= ref.length - 1) return undefined;
  return { provider: ref.slice(0, slash), modelId: ref.slice(slash + 1) };
}

/**
 * Load model-routing.json. Primary path is the installed `~/.omp/agent/`
 * location (a symlink to the dotfiles canonical file, always present in a
 * deployed environment); the hardcoded repo path is a best-effort secondary
 * for running directly from a checkout.
 */
export function loadRoutingConfig(): ModelRoutingConfig | undefined {
  const candidatePaths = [
    path.join(os.homedir(), ".omp", "agent", "model-routing.json"),
    path.join(os.homedir(), "go", "src", "github.com", "kpango", "dotfiles", "agent", "harnesses", "omp", "model-routing.json"),
  ];
  for (const p of candidatePaths) {
    try {
      if (fs.existsSync(p)) {
        return JSON.parse(fs.readFileSync(p, "utf-8")) as ModelRoutingConfig;
      }
    } catch {
      // ignore parse/read error and try next path
    }
  }
  return undefined;
}

/**
 * Advisory text for a context-pressure crossing, focused on the *candidates* (the
 * generic /compact guidance and the transition toast belong to sol-pi.ts, so it is
 * not repeated here). Each token_exhaustion candidate is classified against its own
 * pricing cliff from sol-pi-core (single source: agent/models/catalog.json compaction_threshold). Returns undefined when
 * there is nothing candidate-specific to say (level ok, or no candidates).
 * Never switches models (grill D3).
 */
export function buildFailoverAdvice(
  tokens: number,
  currentId: string,
  routing: ModelRoutingConfig | undefined,
  config: SolPiConfig
): { level: "warn" | "exceeded"; message: string } | undefined {
  const adv = evaluateOnlineCompaction(tokens, currentId, config.cacheWriteReadRatio, config);
  if (adv.level === "ok") return undefined;
  const candidates = resolveFailoverCandidates(routing, currentId, "token_exhaustion");
  if (candidates.length === 0) return undefined;
  const rows = candidates.map((c) => {
    const cliff = pricingCliffFor(c, config);
    return cliff > tokens
      ? `${c} (cliff ${cliff}: 余裕あり)`
      : `${c} (cliff ${cliff} <= 現在 ${tokens}: 切替先でも即超過。先に /compact)`;
  });
  const head = adv.level === "exceeded" ? "Pricing Cliff 到達" : "Pricing Cliff 接近";
  return {
    level: adv.level,
    message:
      `[model-failover] ${head}: 手動で切り替える場合の候補 → ${rows.join(", ")}。` +
      `切替直後は cache が cold で全文脈が cache write (read の ${config.cacheWriteReadRatio}x) になります。自動切替はしません。`,
  };
}

export default function (
  pi: ExtensionAPI,
  deps: {
    loadConfig?: () => SolPiConfig;
    loadRouting?: () => ModelRoutingConfig | undefined;
    loadQuota?: () => QuotaUsage;
    refreshModels?: () => void;
  } = {}
) {
  const config: SolPiConfig = (deps.loadConfig ?? loadSolPiConfig)();
  const loadRouting = deps.loadRouting ?? loadRoutingConfig;
  const loadQuota = deps.loadQuota ?? (() => loadQuotaUsage());
  // Re-fetch the CLI-reported model lists each session so selection is limited to models verified right now.
  const refreshModels =
    deps.refreshModels ??
    (() => {
      const catalog = resolveCatalogPath();
      if (catalog) refreshVerifiedModels(path.resolve(path.dirname(catalog), "..", "scripts", "fetch-harness-models.py"));
    });
  let lastAdviceKey = "";
  let lastQuotaKey = "";
  pi.on("session_start", async () => {
    refreshModels();
    lastAdviceKey = "";
    lastQuotaKey = "";
  });
  // OpenCode Go quota guard: advisory, once per distinct over-limit state (independent of the Pricing Cliff flag).
  pi.on("turn_end", async (_event: unknown, ctx: any) => {
    const policy = loadRouting()?.routingPolicy?.openCodeGoQuotaGuard;
    if (!policy?.enabled) return;
    const advice = buildQuotaAdvice(evaluateQuotaGuard(policy, loadQuota()));
    const key = advice ?? "";
    if (advice && key !== lastQuotaKey) ctx?.ui?.notify?.(advice, "warning");
    lastQuotaKey = key;
  });
  // Advisory only: notify once per (model, level) crossing. No setModel here.
  pi.on("turn_end", async (event: { message?: { model?: string; usage?: TurnUsage } }, ctx: any) => {
    if (!config.pricingCliffAdvisoryConfig.enabled) return;
    const usage = event?.message?.usage;
    if (!usage) return;
    const cur = ctx?.model;
    const currentId = cur?.provider && cur?.id ? `${cur.provider}/${cur.id}` : String(event.message?.model ?? "");
    if (!currentId) return;
    const a = buildFailoverAdvice(contextTokensFromUsage(usage), currentId, loadRouting(), config);
    const key = a ? `${currentId}:${a.level}` : "";
    if (a && key !== lastAdviceKey) ctx?.ui?.notify?.(a.message, "warning");
    lastAdviceKey = key;
  });

  // Reentrancy guard: `after_provider_response` can fire rapidly; a single
  // in-flight switch at a time is enough (chain progression happens across turns
  // via ctx.model, not within one burst).
  let switching = false;

  async function attemptFailover(
    trigger: FailoverTrigger,
    ctx: any,
    reasonLabel: string
  ): Promise<void> {
    if (switching) return;
    const current = ctx?.model;
    if (!current || !current.provider || !current.id) return;
    const currentId = `${current.provider}/${current.id}`;

    const routing = loadRoutingConfig();
    const candidates = resolveFailoverCandidates(routing, currentId, trigger);
    if (candidates.length === 0) {
      ctx?.ui?.notify?.(
        `[model-failover] ${reasonLabel}: no available fallback for ${currentId}`,
        "warning"
      );
      return;
    }

    switching = true;
    try {
      for (const target of candidates) {
        if (target === currentId) continue;
        const parts = splitModelRef(target);
        if (!parts) continue;
        const model = ctx.modelRegistry?.find?.(parts.provider, parts.modelId);
        if (!model) continue;
        // Skip fallbacks with no configured API key so we advance to a usable one.
        if (ctx.modelRegistry?.hasConfiguredAuth && !ctx.modelRegistry.hasConfiguredAuth(model)) {
          continue;
        }
        let ok = false;
        try {
          ok = await pi.setModel(model);
        } catch {
          // setModel threw (transient auth/registry error) — treat as failure
          // and advance to the next candidate rather than escaping the handler.
          ok = false;
        }
        if (ok) {
          ctx?.ui?.notify?.(
            `[model-failover] ${reasonLabel}: ${currentId} -> ${target}`,
            "info"
          );
          return;
        }
        // setModel returned false (no API key resolvable) — try the next candidate.
      }
      ctx?.ui?.notify?.(
        `[model-failover] ${reasonLabel}: fallback chain exhausted for ${currentId}`,
        "warning"
      );
    } finally {
      switching = false;
    }
  }

  // rate_limit: detect provider throttling / overload from the response status.
  // We rely on Pi's built-in retry (settings.retry) to re-issue the turn; switching
  // the active model here means the retry (and any subsequent turn) uses the fallback.
  pi.on("after_provider_response", async (event: any, ctx: any) => {
    const status = event?.status;
    if (status === 429 || status === 529 || status === 503) {
      await attemptFailover("rate_limit", ctx, `rate limit (HTTP ${status})`);
    }
  });

  // token_exhaustion: only switch once Pi's own overflow recovery (auto-compaction)
  // has failed — that is the genuine "context/token limit reached" moment.
  pi.on("session_compact_failed", async (event: any, ctx: any) => {
    if (event?.reason === "overflow" && !event?.aborted) {
      await attemptFailover(
        "token_exhaustion",
        ctx,
        "context/token exhaustion (compaction failed)"
      );
    }
  });
}
