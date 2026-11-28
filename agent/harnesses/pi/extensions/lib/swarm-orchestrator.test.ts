import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import registerSwarm, { computeSwarmGateStatus } from "../swarm-orchestrator";

let pass = 0;
let fail = 0;
function check(desc: string, ok: boolean) {
  if (ok) {
    console.log(`ok: ${desc}`);
    pass++;
  } else {
    console.log(`FAIL: ${desc}`);
    fail++;
  }
}

// Truly clean: no findings + consensus approved -> APPROVED, "All 8 Lenses Clean".
const clean = computeSwarmGateStatus([], true);
check("clean+consensus -> overallPass", clean.overallPass === true);
check("clean header claims 'All 8 Lenses Clean'", clean.header.includes("All 8 Lenses Clean"));

// Blocker present -> REJECTED regardless of consensus.
const blocked = computeSwarmGateStatus([{ severity: "blocker" }], true);
check("blocker -> not overallPass", blocked.overallPass === false);
check("blocker header REJECTED", blocked.header.includes("REJECTED"));

// Consensus failed -> REJECTED even with no findings.
const noConsensus = computeSwarmGateStatus([], false);
check("no consensus -> not overallPass", noConsensus.overallPass === false);

// L2 regression: warnings present (no blockers) still PASS, but header must NOT
// claim "All 8 Lenses Clean".
const warned = computeSwarmGateStatus([{ severity: "warning" }, { severity: "warning" }], true);
check("warnings-only -> overallPass (warnings don't block)", warned.overallPass === true);
check("warnings header does NOT claim 'All 8 Lenses Clean'", !warned.header.includes("All 8 Lenses Clean"));
check("warnings header acknowledges advisory warnings", warned.header.includes("advisory warning"));
check("warnings header pluralizes (2 warnings)", warned.header.includes("2 advisory warnings"));

const oneWarn = computeSwarmGateStatus([{ severity: "warning" }], true);
check("single warning is singular", oneWarn.header.includes("1 advisory warning to verify") && !oneWarn.header.includes("warnings"));

// note-only (no blockers/warnings) still PASSes but must not claim fully clean
// (consistent with cycle6 formatAdversarialReport note handling).
const noteOnly = computeSwarmGateStatus([{ severity: "note" }], true);
check("note-only -> overallPass", noteOnly.overallPass === true);
check("note-only header does NOT claim 'All 8 Lenses Clean'", !noteOnly.header.includes("All 8 Lenses Clean"));
check("note-only header acknowledges advisory note", noteOnly.header.includes("1 advisory note"));

async function dispatch(idle: boolean, args: string) {
  let handler: Parameters<ExtensionAPI["registerCommand"]>[1]["handler"] | undefined;
  const messages: Array<{ text: string; deliverAs?: string }> = [];
  const api = {
    registerCommand(name, options) {
      if (name === "swarm") handler = options.handler;
    },
    async sendUserMessage(text, options) {
      if (typeof text !== "string") throw new Error("expected a text prompt");
      messages.push({ text, deliverAs: options?.deliverAs });
    },
  } satisfies Pick<ExtensionAPI, "registerCommand" | "sendUserMessage">;
  registerSwarm(api as ExtensionAPI);
  if (!handler) throw new Error("missing /swarm command");
  await handler(args, { isIdle: () => idle } as ExtensionCommandContext);
  return messages;
}

const idle = await dispatch(true, "--auto inspect harness settings");
check("idle /swarm starts a turn without a delivery override",
  idle.length === 1 && idle[0].deliverAs === undefined &&
  idle[0].text.startsWith("[SWARM ENTRY] mode=--auto") &&
  idle[0].text.endsWith("Goal:\ninspect harness settings"));

const busy = await dispatch(false, "--loop inspect harness settings");
check("busy /swarm queues behind the active turn",
  busy.length === 1 && busy[0].deliverAs === "followUp" &&
  busy[0].text.includes("/swarm-loop/SKILL.md"));

console.log(`\nswarm-orchestrator: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
