import { buildClaudeArgs } from "../bridge-claude";
import bridgeHermesExtension, { buildHermesArgs, HERMES_PROFILES } from "../bridge-hermes";

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

// L1 regression: the prompt must be separated from flags by `--` so a
// dash-leading prompt is not misparsed as a CLI option.

// --- claude ---
const c = buildClaudeArgs({ prompt: "--help me refactor", model: "sonnet" });
check("claude args start with --print", c[0] === "--print");
check("claude args include --model sonnet", c.includes("--model") && c[c.indexOf("--model") + 1] === "sonnet");
check("claude args end with -- then the prompt", c[c.length - 2] === "--" && c[c.length - 1] === "--help me refactor");
check("claude places exactly one -- separator immediately before the prompt",
  c.filter((a) => a === "--").length === 1 && c.indexOf("--") === c.length - 2);
// default skip-perms on
check("claude default includes --dangerously-skip-permissions", c.includes("--dangerously-skip-permissions"));
const cNoSkip = buildClaudeArgs({ prompt: "hi", dangerouslySkipPermissions: false });
check("claude skip-perms=false omits the flag", !cNoSkip.includes("--dangerously-skip-permissions"));
check("claude benign prompt still separated by --", cNoSkip[cNoSkip.length - 2] === "--" && cNoSkip[cNoSkip.length - 1] === "hi");

// --- hermes ---
const hDefault = buildHermesArgs({ prompt: "summarize RFC" });
check("hermes default profile is chief", hDefault[0] === "-p" && hDefault[1] === "chief");
check("hermes args invoke chat -q <prompt>", hDefault[2] === "chat" && hDefault[3] === "-q" && hDefault[4] === "summarize RFC");

const hSec = buildHermesArgs({ profile: "sec-reviewer", prompt: "--audit auth" });
check("hermes custom profile forwarded", hSec[1] === "sec-reviewer" && hSec[4] === "--audit auth");
check("hermes defines all 6 profiles", HERMES_PROFILES.length === 6 && HERMES_PROFILES.includes("ops"));

// verify bridgeHermesExtension registers tool cleanly without calling runtime action methods at load time
let registeredToolName = "";
let setLabelCalled = false;
bridgeHermesExtension({
  setLabel(_label: string) {
    setLabelCalled = true;
  },
  registerTool(tool: { name: string }) {
    registeredToolName = tool.name;
  },
} as any);
check("hermes extension does not call setLabel during extension load", !setLabelCalled);
check("hermes extension registers hermes_query tool", registeredToolName === "hermes_query");

console.log(`\nbridge-args: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
