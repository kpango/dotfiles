import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  getBareModelAliases,
  getConsensusModels,
  getLowFallbackEntry,
  getOmpDefaultModel,
  getOmpRoleToTier,
  getOmpTierModel,
  loadModelCatalog,
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
check("loadModelCatalog loads canonical catalog.json", Boolean(catalog?.harnesses?.omp?.tiers));

// 2. Dynamic tier & role helpers match live catalog values
const expectedLow = catalog?.harnesses?.omp?.tiers?.Low?.model;
const expectedHigh = catalog?.harnesses?.omp?.tiers?.High?.model;
const expectedXHigh = catalog?.harnesses?.omp?.tiers?.XHigh?.model;
const expectedMax = catalog?.harnesses?.omp?.tiers?.Max?.model;

check("getOmpTierModel Low matches catalog", getOmpTierModel("Low") === expectedLow);
check("getOmpDefaultModel matches default tier High", getOmpDefaultModel() === expectedHigh);
check("getOmpRoleToTier contains @smol -> Low", getOmpRoleToTier()["@smol"] === "Low");
check("getOmpRoleToTier contains @review -> XHigh", getOmpRoleToTier()["@review"] === "XHigh");

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
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "omp-model-cat-"));
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
          omp: {
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

  check("synthetic repo getOmpTierModel Low", getOmpTierModel("Low", tmp) === "vendor-x/fast-v9");
  check("synthetic repo getOmpDefaultModel", getOmpDefaultModel(tmp) === "vendor-a/maker-v9");
  check("synthetic repo getBareModelAliases sonnet", getBareModelAliases(tmp).sonnet === "vendor-a/maker-v9");
  check("synthetic repo getConsensusModels", getConsensusModels(tmp)[0]?.id === "vendor-a/m1");
  check("synthetic repo getLowFallbackEntry", getLowFallbackEntry(tmp).provider === "vendor-x");
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(`\nmodel-catalog: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
