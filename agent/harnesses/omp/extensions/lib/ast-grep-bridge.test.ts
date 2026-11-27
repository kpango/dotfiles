import { buildSearchCommand, parseAstGrepJson, detectAstGrepBinary } from "../ast-grep-bridge";

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

// 1. buildSearchCommand tests
const cmdInfo = buildSearchCommand("ast-grep", "if ($A) { $B }", "typescript", "src/");
check("buildSearchCommand sets binary", cmdInfo.cmd === "ast-grep");
check("buildSearchCommand includes pattern", cmdInfo.args.includes("if ($A) { $B }"));
check("buildSearchCommand includes language", cmdInfo.args.includes("typescript"));
check("buildSearchCommand includes path", cmdInfo.args.includes("src/"));

// 2. parseAstGrepJson tests
const sampleJson = JSON.stringify([
  {
    file: "main.go",
    range: { start: { line: 10, column: 5 } },
    text: "if err != nil { return err }",
  },
]);
const parsed = parseAstGrepJson(sampleJson);
check("parseAstGrepJson parses match count", parsed.length === 1);
check("parseAstGrepJson parses file", parsed[0].file === "main.go");
check("parseAstGrepJson parses line", parsed[0].line === 10);
check("parseAstGrepJson parses text", parsed[0].text.includes("if err != nil"));

// 3. Fallback on invalid JSON
const emptyParsed = parseAstGrepJson("invalid json");
check("parseAstGrepJson handles syntax error gracefully", Array.isArray(emptyParsed) && emptyParsed.length === 0);

console.log(`\nast-grep-bridge: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
