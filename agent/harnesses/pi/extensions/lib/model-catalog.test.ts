import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  getBareModelAliases,
  getConsensusModels,
  getLowFallbackEntry,
  getPiDefaultModel,
  getPiRoleToTier,
  getPiTierModel,
  loadModelCatalog,
  lookupCompactionThreshold,
} from "./model-catalog";

let pass = 0;
let fail = 0;

function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}${msg ? `: ${msg}` : ""}`);
    fail++;
  }
}

// 1. Live repo catalog loads cleanly
const catalog = loadModelCatalog();
check("loadModelCatalog loads canonical catalog.json", Boolean(catalog?.harnesses?.pi?.tiers));

// 2. Dynamic tier & role helpers match live catalog values
const expectedLow = catalog?.harnesses?.pi?.tiers?.Low?.model;
const expectedHigh = catalog?.harnesses?.pi?.tiers?.High?.model;
const expectedXHigh = catalog?.harnesses?.pi?.tiers?.XHigh?.model;
const expectedMax = catalog?.harnesses?.pi?.tiers?.Max?.model;

check("getPiTierModel Low matches catalog", getPiTierModel("Low") === expectedLow);
check("getPiDefaultModel matches default tier High", getPiDefaultModel() === expectedHigh);
check("getPiRoleToTier contains @smol -> Low", getPiRoleToTier()["@smol"] === "Low");
check("getPiRoleToTier contains @review -> XHigh", getPiRoleToTier()["@review"] === "XHigh");

const bare = getBareModelAliases();
check("getBareModelAliases sonnet resolves via catalog", bare.sonnet === expectedHigh);
check("getBareModelAliases haiku resolves via catalog", bare.haiku === expectedLow);
check("getBareModelAliases opus resolves via catalog", bare.opus === expectedXHigh);
check("getBareModelAliases fable resolves via catalog", bare.fable === expectedMax);

const consensus = getConsensusModels();
check("getConsensusModels returns >= 3 distinct models", consensus.length >= 3);
check(
  "getLowFallbackEntry matches omp Low tier",
  getLowFallbackEntry().model === expectedLow && Boolean(getLowFallbackEntry().provider)
);

// 3. Synthetic isolated temp repo catalog verifies true dynamic resolution (no hardcodes)
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pi-model-cat-"));
try {
  const catDir = path.join(tmp, "agent", "models");
  fs.mkdirSync(catDir, { recursive: true });
  fs.writeFileSync(
    path.join(catDir, "catalog.json"),
    JSON.stringify(
      {
        role_aliases: { "@smol": "Low", "@good": "High", "@review": "XHigh" },
        legacy_aliases: { haiku: "Low", sonnet: "High", opus: "XHigh" },
        consensus_models: [
          { id: "vendor-a/m1", label: "Vendor A M1" },
          { id: "vendor-b/m2", label: "Vendor B M2" },
          { id: "vendor-c/m3", label: "Vendor C M3" },
        ],
        harnesses: {
          pi: {
            default_tier: "High",
            tiers: {
              Low: { provider: "vendor-x", model: "vendor-x/fast-v9", effort: "low" },
              High: { provider: "vendor-a", model: "vendor-a/maker-v9", effort: "high" },
              XHigh: { provider: "vendor-b", model: "vendor-b/checker-v9", effort: "xhigh" },
            },
          },
        },
      },
      null,
      2
    )
  );

  check("synthetic repo getPiTierModel Low", getPiTierModel("Low", tmp) === "vendor-x/fast-v9");
  check("synthetic repo getPiDefaultModel", getPiDefaultModel(tmp) === "vendor-a/maker-v9");
  check("synthetic repo getBareModelAliases sonnet", getBareModelAliases(tmp).sonnet === "vendor-a/maker-v9");
  check("synthetic repo getConsensusModels", getConsensusModels(tmp)[0]?.id === "vendor-a/m1");
  check("synthetic repo getLowFallbackEntry", getLowFallbackEntry(tmp).provider === "vendor-x");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(`\nmodel-catalog: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);

// lookupCompactionThreshold: Pricing Cliff single source (catalog.json models.*.compaction_threshold)
{
  const cat = { models: { "anthropic/claude-haiku-5-5": { model_id: "claude-haiku-5-5", compaction_threshold: 90000 }, "x/none": { model_id: "none-1", compaction_threshold: null } } };
  check("lookupCompactionThreshold: provider-prefixed id", lookupCompactionThreshold(cat, "anthropic/claude-haiku-5-5") === 90000);
  check("lookupCompactionThreshold: dotted id and date suffix", lookupCompactionThreshold(cat, "claude-haiku-5.5") === 90000 && lookupCompactionThreshold(cat, "claude-haiku-5-5-20261101") === 90000);
  check("lookupCompactionThreshold: no prefix match (5-50, xhaiku)", lookupCompactionThreshold(cat, "claude-haiku-5-50") === undefined && lookupCompactionThreshold(cat, "xclaude-haiku-5-5") === undefined);
  check("lookupCompactionThreshold: null threshold / missing catalog -> undefined", lookupCompactionThreshold(cat, "none-1") === undefined && lookupCompactionThreshold(null, "claude-haiku-5-5") === undefined);
}
