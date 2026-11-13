import { getActiveTierInfo } from "../status-line";

let pass = 0;
let fail = 0;

function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

const tierStr = getActiveTierInfo();
check("getActiveTierInfo returns non-empty string", typeof tierStr === "string" && tierStr.length > 0);
check("getActiveTierInfo contains High", tierStr.includes("High"));
check("getActiveTierInfo contains model identifier", tierStr.includes("claude-sonnet-5") || tierStr.includes("Sonnet"));

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
