/**
 * Virtual Model Roles Core Library for Pi 1.7.0
 *
 * Maps OMP-style semantic roles (default, slow, plan, good, smol, fast,
 * review, judge, tiny, memory) to Pi `model-routing.json` tiers and fallback
 * chains for `pi.registerVirtualModel(...)`.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";

const MODULE_DIR =
  typeof import.meta.dir === "string"
    ? import.meta.dir
    : typeof __dirname === "string"
      ? __dirname
      : path.dirname(fileURLToPath(import.meta.url));

export type RoleName =
  | "default"
  | "slow"
  | "plan"
  | "good"
  | "smol"
  | "fast"
  | "review"
  | "judge"
  | "tiny"
  | "memory";

export type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";

export interface RoleRouteCandidate {
  provider: string;
  modelId: string;
  thinkingLevel: ThinkingLevel;
  trigger?: string;
}

export interface RoleDefinition {
  id: RoleName;
  name: string;
  tier: string;
  defaultEffort?: ThinkingLevel;
  preferLocal?: boolean;
}

export const ROLE_DEFINITIONS: readonly RoleDefinition[] = [
  { id: "default", name: "Role: Default (High Maker)", tier: "High" },
  { id: "slow", name: "Role: Slow (Max Deep Reasoning)", tier: "Max", defaultEffort: "xhigh" },
  { id: "plan", name: "Role: Plan (Max Architecture)", tier: "Max", defaultEffort: "high" },
  { id: "good", name: "Role: Good (High Coding)", tier: "High", defaultEffort: "high" },
  { id: "smol", name: "Role: Smol (Low Balanced)", tier: "Low", defaultEffort: "medium" },
  { id: "fast", name: "Role: Fast (Low Speed)", tier: "Low", defaultEffort: "low" },
  { id: "review", name: "Role: Review (XHigh Checker)", tier: "XHigh", defaultEffort: "xhigh" },
  { id: "judge", name: "Role: Judge (XHigh Verifier)", tier: "XHigh", defaultEffort: "xhigh" },
  { id: "tiny", name: "Role: Tiny (Local / Low Cost)", tier: "Low", defaultEffort: "low", preferLocal: true },
  { id: "memory", name: "Role: Memory (Local / Low Cost)", tier: "Low", defaultEffort: "low", preferLocal: true },
];

export interface RoutingFileShape {
  default_tier?: string;
  tiers?: Record<
    string,
    {
      provider?: string;
      model?: string;
      effort?: string;
      fallbacks?: Array<{ provider?: string; model?: string; effort?: string; trigger?: string }>;
    }
  >;
}

const VALID_THINKING = new Set<ThinkingLevel>(["off", "minimal", "low", "medium", "high", "xhigh", "max"]);

function normEffort(effort: unknown, fallback: ThinkingLevel = "medium"): ThinkingLevel {
  if (typeof effort === "string" && VALID_THINKING.has(effort as ThinkingLevel)) {
    return effort as ThinkingLevel;
  }
  return fallback;
}

export function splitQualifiedModel(ref: string, explicitProvider?: string): { provider: string; modelId: string } | null {
  if (!ref) return null;
  const idx = ref.indexOf("/");
  if (idx > 0 && idx < ref.length - 1) {
    return { provider: ref.slice(0, idx), modelId: ref.slice(idx + 1) };
  }
  if (explicitProvider) {
    return { provider: explicitProvider, modelId: ref };
  }
  return null;
}

export function loadModelRoutingJson(candidatePaths?: string[]): RoutingFileShape | null {
  const paths = candidatePaths ?? [
    path.join(os.homedir(), ".pi", "agent", "model-routing.json"),
    path.resolve(MODULE_DIR, "..", "..", "model-routing.json"),
  ];
  for (const p of paths) {
    try {
      if (fs.existsSync(p)) {
        return JSON.parse(fs.readFileSync(p, "utf-8")) as RoutingFileShape;
      }
    } catch {
      // Try next path.
    }
  }
  return null;
}

export function resolveRoleCandidateChain(
  routing: RoutingFileShape | null | undefined,
  role: RoleDefinition,
  requestedThinking?: ThinkingLevel,
): RoleRouteCandidate[] {
  const tierName = role.id === "default" ? routing?.default_tier || role.tier : role.tier;
  const tier = routing?.tiers?.[tierName];
  if (!tier) return [];

  const chain: RoleRouteCandidate[] = [];
  const pushEntry = (
    modelRef: string | undefined,
    provider: string | undefined,
    effort: string | undefined,
    trigger?: string,
  ) => {
    if (!modelRef) return;
    const split = splitQualifiedModel(modelRef, provider);
    if (!split) return;
    const effectiveEffort =
      requestedThinking && requestedThinking !== "off"
        ? requestedThinking
        : normEffort(effort, role.defaultEffort ?? "medium");
    if (!chain.some((c) => c.provider === split.provider && c.modelId === split.modelId)) {
      chain.push({
        provider: split.provider,
        modelId: split.modelId,
        thinkingLevel: effectiveEffort,
        trigger,
      });
    }
  };

  if (role.preferLocal && Array.isArray(tier.fallbacks)) {
    for (const fb of tier.fallbacks) {
      if (fb.provider === "ollama" || (fb.model && fb.model.startsWith("ollama/"))) {
        pushEntry(fb.model, fb.provider, fb.effort, fb.trigger);
      }
    }
  }

  pushEntry(tier.model, tier.provider, tier.effort);
  for (const fb of tier.fallbacks ?? []) {
    pushEntry(fb.model, fb.provider, fb.effort, fb.trigger);
  }
  return chain;
}

export interface RouteModelLookup<TModel> {
  find(provider: string, modelId: string): TModel | undefined;
  isAvailable?(model: TModel): boolean;
}

export function selectPhysicalCandidate<TModel>(
  candidates: RoleRouteCandidate[],
  request: {
    reason: string;
    thinkingLevel?: ThinkingLevel;
    previous?: { model: TModel; thinkingLevel?: ThinkingLevel };
    failed?: { model: TModel & { provider?: string; id?: string }; thinkingLevel?: ThinkingLevel };
  },
  lookup: RouteModelLookup<TModel>,
): { model: TModel; thinkingLevel: ThinkingLevel } | null {
  const sticky = request.failed ?? request.previous;
  if (request.reason !== "user" && !request.failed && sticky) {
    return {
      model: sticky.model,
      thinkingLevel: sticky.thinkingLevel ?? request.thinkingLevel ?? "medium",
    };
  }

  let startIndex = 0;
  if (request.failed?.model?.provider && request.failed?.model?.id) {
    const failedIdx = candidates.findIndex(
      (c) => c.provider === request.failed!.model.provider && c.modelId === request.failed!.model.id,
    );
    if (failedIdx >= 0 && failedIdx + 1 < candidates.length) {
      startIndex = failedIdx + 1;
    }
  }

  for (let i = startIndex; i < candidates.length; i++) {
    const cand = candidates[i];
    const found = lookup.find(cand.provider, cand.modelId);
    if (!found) continue;
    if (lookup.isAvailable && !lookup.isAvailable(found)) continue;
    return {
      model: found,
      thinkingLevel: cand.thinkingLevel,
    };
  }

  // Last resort: ignore availability filter so caller receives the first registered model.
  for (let i = 0; i < candidates.length; i++) {
    const cand = candidates[i];
    const found = lookup.find(cand.provider, cand.modelId);
    if (found) {
      return { model: found, thinkingLevel: cand.thinkingLevel };
    }
  }
  return null;
}
