import { buildHelixCommand } from "../helix-bridge";

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

// 1. Direct Helix command
const cmdDirect = buildHelixCommand("main.go", 42, false);
check("Direct cmd is hx", cmdDirect.cmd === "hx");
check("Direct target is main.go:42", cmdDirect.args[0] === "main.go:42");

// 2. Direct without line
const cmdDirectNoLine = buildHelixCommand("README.md", undefined, false);
check("Direct target without line", cmdDirectNoLine.args[0] === "README.md");

// 3. Tmux command
const cmdTmux = buildHelixCommand("main.go", 42, true);
check("Tmux cmd is tmux", cmdTmux.cmd === "tmux");
check("Tmux args has split-window", cmdTmux.args.includes("split-window"));
check("Tmux args includes single-quoted hx target", cmdTmux.args.some(a => a === "hx 'main.go:42'"));

// L2 regression: the tmux shell-command must single-quote the target so a file
// path with shell metacharacters cannot inject commands.
const evil = buildHelixCommand('foo"; touch /tmp/hx_pwn; "', 10, true, "h");
const shellStr = evil.args[2];
check("tmux target is single-quote wrapped", shellStr.startsWith("hx '") && shellStr.endsWith("'"));
// Safety invariant: the payload (which has no single quotes) is fully contained
// in ONE single-quoted word, so the injected `; touch` is inert. Verify the
// exact safe form rather than a substring (the `; touch` literal is PRESENT but
// harmless inside the quotes).
check("tmux shell string is the exact single-quoted-safe form",
  shellStr === "hx 'foo\"; touch /tmp/hx_pwn; \":10'");
// embedded single-quote in the path is escaped as '\'' (not left dangling).
const q = buildHelixCommand("it's.txt", undefined, true, "v");
check("single-quote in path is escaped", q.args[2] === "hx 'it'\\''s.txt'");

console.log(`\nhelix-bridge: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
