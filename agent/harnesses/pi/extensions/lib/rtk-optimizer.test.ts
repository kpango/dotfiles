import { spawnSync } from "node:child_process";
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import * as path from "node:path";
import { isWhitelistedForRtk } from "../../../../hooks/pi/rtk-optimizer";

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

// Same input table drives BOTH the TS whitelist and the canonical claude hook
// (agent/hooks/claude/rtk-rewrite.sh). `expect` = should rtk be invoked.
const CLAUDE_HOOK = path.resolve(import.meta.dir, "../../../../hooks/claude/rtk-rewrite.sh");
const table: Array<[string, boolean]> = [
  // every whitelist entry (positive)
  ["go test ./...", true],
  ["go test", true],
  ["cargo test", true],
  ["cargo check --all", true],
  ["cargo clippy -- -D warnings", true],
  ["cargo build --release", true],
  ["pytest -q", true],
  ["npm test", true],
  ["pnpm test", true],
  ["bun test", true],
  ["make build", true],
  ["make", true],
  ["git status", true],
  ["git log --oneline", true],
  ["git diff HEAD", true],
  ["docker ps -a", true],
  ["docker logs foo", true],
  ["kubectl get pods", true],
  ["kubectl logs foo", true],
  ["gh pr checks 12", true],
  // non-targets (Issue #582)
  ["cat README.md", false],
  ["head -n 5 x", false],
  ["tail -f x", false],
  ["ls -la", false],
  ["grep -rn foo .", false],
  ["echo hi", false],
  ["rtk go test", false],
  ["", false],
  // compound commands: only a whitelisted PREFIX of the raw string counts
  ["go test ./... && cat x", true],
  ["go test ./... ; cat x", true],
  ["go test ./... | tail", true],
  ["cat x && go test ./...", false],
  ["cd /tmp && go test", false],
  ["echo a; make", false],
  // leading env assignment / sudo / whitespace are NOT stripped
  ["FOO=1 go test ./...", false],
  ["sudo make install", false],
  [" go test", false],
  ["\tgo test", false],
  ["\ngo test", false],
  // newline / quotes inside a matching prefix
  ["go test ./...\ncat x", true],
  ['go test -run "A B"', true],
  ["go test 'x'", true],
  // no word boundary (claude glob `"go test"*` semantics, intentionally mirrored)
  ["go testing", true],
  ["makefile", true],
  ["pytest-x", true],
  // case sensitive
  ["Go Test", false],
  ["GIT STATUS", false],
  ["Make build", false],
  // near misses (different command)
  ["go tes", false],
  ["cargo run", false],
  ["docker run x", false],
  ["kubectl apply -f x", false],
  ["gh pr view 1", false],
  ["git push", false],
];

// 1. TS function against the table
for (const [cmd, want] of table) {
  check(`ts isWhitelistedForRtk(${JSON.stringify(cmd)}) === ${want}`, isWhitelistedForRtk(cmd) === want);
}
check("ts isWhitelistedForRtk(undefined-ish) is false", isWhitelistedForRtk(undefined as unknown as string) === false);

// 2. Parity: canonical claude hook decides identically (stub rtk echoes `rtk <cmd>`)
const tmp = mkdtempSync(path.join(tmpdir(), "rtk-parity-"));
try {
  const stub = path.join(tmp, "rtk");
  writeFileSync(stub, '#!/bin/sh\nprintf "rtk %s\\n" "$2"\n');
  chmodSync(stub, 0o755);
  const env = { ...process.env, PATH: `${tmp}:${process.env.PATH}` };
  for (const [cmd, want] of table) {
    if (cmd === "") continue; // jq `// empty` path, covered separately
    const r = spawnSync("bash", [CLAUDE_HOOK], {
      input: JSON.stringify({ tool_input: { command: cmd } }),
      env,
      encoding: "utf-8",
    });
    const claudeInvoked = r.status === 0 && r.stdout.includes("updatedInput");
    check(`parity claude-hook vs table ${JSON.stringify(cmd)}`, claudeInvoked === want, `claude=${claudeInvoked} want=${want} rc=${r.status}`);
  }
} finally {
  rmSync(tmp, { recursive: true, force: true });
}

// 3. Handler: non-whitelisted commands must NOT spawn rtk at all; whitelisted are rewritten.
const tmp2 = mkdtempSync(path.join(tmpdir(), "rtk-handler-"));
try {
  const log = path.join(tmp2, "calls.log");
  const stub = path.join(tmp2, "rtk");
  writeFileSync(stub, `#!/bin/sh\necho "$@" >> "${log}"\nprintf "rtk %s\\n" "$2"\n`);
  chmodSync(stub, 0o755);
  process.env.PATH = `${tmp2}:${process.env.PATH}`;
  const mod = await import("../../../../hooks/pi/rtk-optimizer");
  let handler: any;
  mod.default({ on: (_ev: string, h: any) => (handler = h) } as any);

  const cat = { toolName: "bash", input: { command: "cat README.md" } };
  await handler(cat, {});
  check("handler: cat is untouched", cat.input.command === "cat README.md");
  check("handler: cat does not spawn rtk rewrite", !existsSync(log), existsSync(log) ? readFileSync(log, "utf-8") : "");

  const gt = { toolName: "bash", input: { command: "go test ./..." } };
  await handler(gt, {});
  check("handler: go test is rewritten via rtk", gt.input.command === "rtk go test ./...", gt.input.command);
  check("handler: go test spawned rtk rewrite once", existsSync(log) && readFileSync(log, "utf-8").trim().split("\n").length === 1);

  // command substitution must not be shell-expanded by the rewrite call
  const marker = path.join(tmp2, "pwned");
  const inj = { toolName: "bash", input: { command: `go test $(touch ${marker})` } };
  await handler(inj, {});
  check("handler: no shell expansion of command in rtk rewrite call", !existsSync(marker));

  const other = { toolName: "read", input: { command: "go test" } };
  await handler(other, {});
  check("handler: non-bash tool ignored", other.input.command === "go test");
} finally {
  rmSync(tmp2, { recursive: true, force: true });
}

console.log(`\nrtk-optimizer: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
