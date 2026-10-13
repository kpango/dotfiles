import { computeSwarmGateStatus } from "../swarm-orchestrator";

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

console.log(`\nswarm-orchestrator: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
