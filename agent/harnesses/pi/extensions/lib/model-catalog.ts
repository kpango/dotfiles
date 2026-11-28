import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export interface ConsensusModelEntry {
  id: string;
  label: string;
  tier?: string;
}

export interface LowFallbackEntry {
  provider: string;
  model: string;
  effort: string;
}

export interface ModelCatalogData {
  schema_version?: number;
  updated_at?: string;
  role_aliases?: Record<string, string>;
  legacy_aliases?: Record<string, string>;
  consensus_models?: ConsensusModelEntry[];
  models?: Record<string, { model_id?: string; compaction_threshold?: number | null }>;
  harnesses?: Record<
    string,
    {
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
  >;
}

const DEFAULT_ROLE_TO_TIER: Record<string, string> = {
  "@smol": "Low",
  "@fast": "Low",
  "@good": "High",
  "@review": "XHigh",
  "@slow": "Max",
  "@plan": "Max",
};

const DEFAULT_LEGACY_ALIASES: Record<string, string> = {
  haiku: "Low",
  sonnet: "High",
  opus: "XHigh",
  fable: "Max",
};

const DEFAULT_TIER_MODELS: Record<string, string> = {
  Low: "opencode-go/deepseek-v4.1-flash",
  Medium: "opencode-go/kimi-k3.1-pro",
  High: "anthropic/claude-sonnet-5-5",
  XHigh: "openai/gpt-6.2-astra",
  Max: "anthropic/claude-fable-5-2",
};

const DEFAULT_CONSENSUS: ConsensusModelEntry[] = [
  { id: "anthropic/claude-sonnet-5-5", label: "Claude Sonnet 5.5 (Anthropic)", tier: "High" },
  { id: "antigravity-cli/gemini-4-argon", label: "Gemini 4 Argon (Google DeepMind)", tier: "XHigh" },
  { id: "openai/gpt-6.2-astra", label: "GPT-6.2 Astra (OpenAI)", tier: "XHigh" },
];

function walkUpForCatalog(startDir: string): string | null {
  let dir = path.resolve(startDir);
  while (true) {
    const candidate = path.join(dir, "agent", "models", "catalog.json");
    if (fs.existsSync(candidate)) {
      return candidate;
    }
    const parent = path.dirname(dir);
    if (parent === dir) {
      break;
    }
    dir = parent;
  }
  return null;
}

export function resolveCatalogPath(repoRoot?: string): string | null {
  const roots = [repoRoot, process.cwd(), __dirname];
  for (const r of roots) {
    if (!r) continue;
    const found = walkUpForCatalog(r);
    if (found) return found;
  }

  // Follow ~/.pi/agent/model-routing.json symlink back to dotfiles repo if installed
  const liveRouting = path.join(os.homedir(), ".pi", "agent", "model-routing.json");
  if (fs.existsSync(liveRouting)) {
    try {
      const realRouting = fs.realpathSync(liveRouting);
      const found = walkUpForCatalog(path.dirname(realRouting));
      if (found) return found;
    } catch {
      // ignore dangling symlink errors
    }
  }

  const canonical = path.join(os.homedir(), "go", "src", "github.com", "kpango", "dotfiles", "agent", "models", "catalog.json");
  if (fs.existsSync(canonical)) {
    return canonical;
  }
  return null;
}

export function loadModelCatalog(repoRoot?: string): ModelCatalogData | null {
  const p = resolveCatalogPath(repoRoot);
  if (!p) return null;
  try {
    return JSON.parse(fs.readFileSync(p, "utf-8")) as ModelCatalogData;
  } catch {
    return null;
  }
}

export function getPiTierModel(tier: string, repoRoot?: string): string {
  const catalog = loadModelCatalog(repoRoot);
  const tiers = catalog?.harnesses?.pi?.tiers;
  if (tiers) {
    const entry = Object.entries(tiers).find(([k]) => k.toLowerCase() === tier.toLowerCase());
    if (entry?.[1]?.model) {
      return entry[1].model;
    }
  }
  const fallbackEntry = Object.entries(DEFAULT_TIER_MODELS).find(([k]) => k.toLowerCase() === tier.toLowerCase());
  return fallbackEntry ? fallbackEntry[1] : DEFAULT_TIER_MODELS.High;
}

export function getPiDefaultModel(repoRoot?: string): string {
  const catalog = loadModelCatalog(repoRoot);
  const omp = catalog?.harnesses?.pi;
  const defaultTier = omp?.default_tier || "High";
  return omp?.tiers?.[defaultTier]?.model || getPiTierModel(defaultTier, repoRoot);
}

export function getPiRoleToTier(repoRoot?: string): Record<string, string> {
  const catalog = loadModelCatalog(repoRoot);
  const out: Record<string, string> = {};
  const src = catalog?.role_aliases || DEFAULT_ROLE_TO_TIER;
  for (const [k, v] of Object.entries(src)) {
    if (typeof v === "string") {
      out[k.toLowerCase()] = v;
    }
  }
  return out;
}

export function getBareModelAliases(repoRoot?: string): Record<string, string> {
  const catalog = loadModelCatalog(repoRoot);
  const legacy = catalog?.legacy_aliases || DEFAULT_LEGACY_ALIASES;
  const out: Record<string, string> = {};
  for (const [alias, tier] of Object.entries(legacy)) {
    if (typeof tier === "string") {
      out[alias.toLowerCase()] = getPiTierModel(tier, repoRoot);
    }
  }
  return out;
}

export function getConsensusModels(repoRoot?: string): Array<{ id: string; label: string }> {
  const catalog = loadModelCatalog(repoRoot);
  const entries = catalog?.consensus_models;
  if (Array.isArray(entries) && entries.length > 0) {
    return entries
      .filter((m) => Boolean(m?.id && m?.label))
      .map((m) => ({ id: m.id, label: m.label }));
  }
  return DEFAULT_CONSENSUS.map((m) => ({ id: m.id, label: m.label }));
}

export function getLowFallbackEntry(repoRoot?: string): LowFallbackEntry {
  const catalog = loadModelCatalog(repoRoot);
  const lowTier = catalog?.harnesses?.pi?.tiers?.Low;
  const model = lowTier?.model || getPiTierModel("Low", repoRoot);
  const provider = lowTier?.provider || (model.includes("/") ? model.split("/", 1)[0] : "opencode-go");
  const effort = lowTier?.effort || "low";
  return { provider, model, effort };
}

function normalizeModelId(id: string): string {
  const bare = id.includes("/") ? id.slice(id.lastIndexOf("/") + 1) : id;
  return bare.toLowerCase().replace(/\./g, "-");
}

/**
 * Pricing Cliff (compaction_threshold) for a model id, from catalog.json `models` (single source of truth).
 * `modelId` may carry a provider prefix and use '.' or '-' (claude-haiku-5.5 == claude-haiku-5-5). It matches a
 * catalog model_id exactly, or that id followed by a date suffix (-YYYYMMDD / @YYYYMMDD); anything else
 * (claude-haiku-5-50, gpt-6.2-mini) does NOT match. Returns undefined when no entry has a positive threshold.
 */
export function lookupCompactionThreshold(catalog: ModelCatalogData | null | undefined, modelId: string): number | undefined {
  if (!catalog?.models || !modelId) return undefined;
  const want = normalizeModelId(modelId);
  for (const m of Object.values(catalog.models)) {
    const t = m?.compaction_threshold;
    if (typeof m?.model_id !== "string" || typeof t !== "number" || !Number.isFinite(t) || t <= 0) continue;
    const have = normalizeModelId(m.model_id);
    if (want === have || (want.startsWith(have) && /^[-@]\d{6,8}$/.test(want.slice(have.length)))) return t;
  }
  return undefined;
}
