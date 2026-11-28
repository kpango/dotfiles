import * as path from "node:path";
import {
  ROLE_DEFINITIONS,
  loadModelRoutingJson,
  resolveRoleCandidateChain,
  selectPhysicalCandidate,
  type RoutingFileShape,
} from "./model-roles-core";

let pass = 0;
let fail = 0;
function check(name: string, cond: boolean, detail?: string) {
  if (cond) pass++;
  else {
    fail++;
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
  }
}

const repoRoutingPath = path.resolve(import.meta.dir, "..", "..", "model-routing.json");
const routing = loadModelRoutingJson([repoRoutingPath]);
check("loads repo pi/model-routing.json", routing !== null && Boolean(routing.tiers?.High));

const slowRole = ROLE_DEFINITIONS.find((r) => r.id === "slow")!;
const slowChain = resolveRoleCandidateChain(routing, slowRole);
check("slow role resolves Max tier primary first", slowChain.length >= 2 && slowChain[0].provider === "anthropic");

const tinyRole = ROLE_DEFINITIONS.find((r) => r.id === "tiny")!;
const tinyChain = resolveRoleCandidateChain(routing, tinyRole);
check("tiny role prioritizes local ollama fallback when present", tinyChain[0]?.provider === "ollama");

const syntheticRouting: RoutingFileShape = {
  default_tier: "High",
  tiers: {
    High: {
      model: "anthropic/claude-sonnet-5-5",
      effort: "high",
      fallbacks: [
        { model: "openai/gpt-6.2-sol", effort: "high", trigger: "rate_limit" },
        { model: "opencode-go/qwen4-max", effort: "high", trigger: "cost_saver" },
      ],
    },
  },
};

const goodRole = ROLE_DEFINITIONS.find((r) => r.id === "good")!;
const chain = resolveRoleCandidateChain(syntheticRouting, goodRole);
const models = new Map<string, { provider: string; id: string; authed: boolean }>([
  ["anthropic/claude-sonnet-5-5", { provider: "anthropic", id: "claude-sonnet-5-5", authed: true }],
  ["openai/gpt-6.2-sol", { provider: "openai", id: "gpt-6.2-sol", authed: false }],
  ["opencode-go/qwen4-max", { provider: "opencode-go", id: "qwen4-max", authed: true }],
]);

const lookup = {
  find: (p: string, id: string) => models.get(`${p}/${id}`),
  isAvailable: (m: { authed: boolean }) => m.authed,
};

const userPick = selectPhysicalCandidate(chain, { reason: "user" }, lookup);
check("user turn selects primary physical model", userPick?.model.id === "claude-sonnet-5-5");

const stickyPick = selectPhysicalCandidate(
  chain,
  { reason: "tool_result", previous: { model: models.get("opencode-go/qwen4-max")!, thinkingLevel: "high" } },
  lookup,
);
check("tool follow-up stays sticky on previous physical model", stickyPick?.model.id === "qwen4-max");

const failoverPick = selectPhysicalCandidate(
  chain,
  { reason: "retry", failed: { model: models.get("anthropic/claude-sonnet-5-5")!, thinkingLevel: "high" } },
  lookup,
);
check("failed primary skips unauthed fallback and picks next authed model", failoverPick?.model.id === "qwen4-max");

console.log(`model-roles-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
