import * as fs from "node:fs";
import * as path from "node:path";
import {
  createTtsrState,
  evaluateTtsrText,
  evaluateTtsrToolCall,
  loadTtsrRules,
  matchesGlobList,
  parseTtsrRuleMarkdown,
} from "./ttsr-core";

let pass = 0;
let fail = 0;
function check(name: string, cond: boolean, detail?: string) {
  if (cond) pass++;
  else {
    fail++;
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
  }
}

const repoRoot = path.resolve(import.meta.dir, "../../../../..");
const rules = loadTtsrRules([path.join(repoRoot, "agent", "rules")]);
check("loads vald-law-ttsr.md from agent/rules", rules.some((r) => r.name === "vald-law-ttsr"));

const valdRule = rules.find((r) => r.name === "vald-law-ttsr")!;
check("parses 4 condition regexes", valdRule.conditions.length === 4);
check("parses 4 scopes", valdRule.scopes.length === 4);
check("matchesGlobList matches **/*.go", matchesGlobList("/repo/pkg/foo.go", ["**/*.go"]));
check("matchesGlobList rejects .py against **/*.go", !matchesGlobList("/repo/pkg/foo.py", ["**/*.go"]));

const state = createTtsrState();
const hit1 = evaluateTtsrToolCall(
  rules,
  "edit",
  "/home/kpango/go/src/github.com/vdaas/vald/pkg/x.go",
  'return errors.New("boom")',
  state,
  1,
);
check("triggers on errors.New in .go edit", hit1?.matched.name === "vald-law-ttsr");

// after-gap suppresses immediate consecutive turn (turn 2), fires again at turn 3
const hit2 = evaluateTtsrToolCall(
  rules,
  "edit",
  "/home/kpango/go/src/github.com/vdaas/vald/pkg/x.go",
  'return errors.New("boom")',
  state,
  2,
);
check("repeatMode after-gap suppresses immediate next turn", hit2 === null);

const hit3 = evaluateTtsrToolCall(
  rules,
  "edit",
  "/home/kpango/go/src/github.com/vdaas/vald/pkg/x.go",
  'return errors.New("boom")',
  state,
  3,
);
check("repeatMode after-gap fires again after gap", hit3?.matched.name === "vald-law-ttsr");

// Scope filtering: read tool or .ts file should not trigger
const nonMatch = evaluateTtsrToolCall(rules, "edit", "/repo/foo.ts", 'errors.New("x")', state, 10);
check("scope excludes non-matching extension .ts", nonMatch === null);

// Stream-and-tool rule check
const streamRule = parseTtsrRuleMarkdown(`---
name: stream-check
globs:
  - "**/*.ts"
condition:
  - "FORBIDDEN_TOKEN"
interruptMode: "stream-and-tool"
repeatMode: "once"
---
Do not emit FORBIDDEN_TOKEN.
`);
check("stream rule parses", streamRule !== null);
if (streamRule) {
  const s2 = createTtsrState();
  const sh1 = evaluateTtsrText([streamRule], "hello FORBIDDEN_TOKEN world", s2, 1);
  const sh2 = evaluateTtsrText([streamRule], "hello FORBIDDEN_TOKEN world", s2, 5);
  check("stream rule fires once and respects repeatMode=once", sh1 !== null && sh2 === null);
}

console.log(`ttsr-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
