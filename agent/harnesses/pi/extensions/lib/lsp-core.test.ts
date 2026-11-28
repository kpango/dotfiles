import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  LspMessageParser,
  applyNonOverlappingTextEdits,
  computeDeltaDiagnostics,
  encodeLspMessage,
  formatDeltaDiagnosticsReport,
  formatDiagnosticsReport,
  formatHonestyNotice,
  isGitCommitOrPushCommand,
  loadLspConfig,
  matchLspServerForFile,
  resolveServerCommandOverride,
} from "./lsp-core";

let pass = 0;
let fail = 0;
function check(name: string, cond: boolean, detail?: string) {
  if (cond) pass++;
  else {
    fail++;
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
  }
}

const repoLspPath = path.resolve(import.meta.dir, "..", "..", "lsp.json");
const cfg = loadLspConfig([repoLspPath]);
check("loads repo lsp.json with gopls and rust-analyzer", Boolean(cfg.servers.gopls && cfg.servers["rust-analyzer"]));

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "lsp-core-test-"));
try {
  fs.writeFileSync(path.join(tmp, "go.mod"), "module example.com/test\n");
  fs.mkdirSync(path.join(tmp, "pkg"), { recursive: true });
  const goFile = path.join(tmp, "pkg", "main.go");
  fs.writeFileSync(goFile, "package pkg\n");

  const m = matchLspServerForFile(cfg, goFile, tmp);
  check("matches gopls and finds go.mod root", m?.serverName === "gopls" && m.rootDir === tmp);
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

// Env override
const ov = resolveServerCommandOverride("rust-analyzer", {
  PI_RUST_ANALYZER_LSP_COMMAND: "rust-analyzer --custom-flag",
});
check("parses PI_<NAME>_LSP_COMMAND override", ov?.command === "rust-analyzer" && ov.args[0] === "--custom-flag");

// Framing encode/decode across split chunks
const msg1 = encodeLspMessage({ jsonrpc: "2.0", id: 1, result: { ok: true } });
const msg2 = encodeLspMessage({ jsonrpc: "2.0", method: "textDocument/publishDiagnostics", params: { uri: "file:///a.go" } });
const combined = Buffer.concat([msg1, msg2]);
const parser = new LspMessageParser();
const partA = parser.push(combined.subarray(0, 15));
const partB = parser.push(combined.subarray(15));
check("LspMessageParser handles split chunks", partA.length === 0 && partB.length === 2);

// Non-overlapping TextEdits
const edited = applyNonOverlappingTextEdits("hello world", [
  { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 5 } }, newText: "hi" },
  { range: { start: { line: 0, character: 6 }, end: { line: 0, character: 11 } }, newText: "pi" },
]);
check("applyNonOverlappingTextEdits applies multiple edits cleanly", edited === "hi pi");

let overlapThrew = false;
try {
  applyNonOverlappingTextEdits("hello world", [
    { range: { start: { line: 0, character: 0 }, end: { line: 0, character: 7 } }, newText: "x" },
    { range: { start: { line: 0, character: 4 }, end: { line: 0, character: 9 } }, newText: "y" },
  ]);
} catch {
  overlapThrew = true;
}
check("applyNonOverlappingTextEdits rejects overlapping edits", overlapThrew);

const diagText = formatDiagnosticsReport(
  "a.go",
  [
    { range: { start: { line: 3, character: 4 }, end: { line: 3, character: 8 } }, severity: 1, message: "undefined: x", source: "gopls" },
    { range: { start: { line: 5, character: 0 }, end: { line: 5, character: 1 } }, severity: 2, message: "unused var" },
  ],
  true,
);
check("formatDiagnosticsReport filters ERRORs when errorsOnly=true", diagText.includes("ERROR [gopls] undefined: x") && !diagText.includes("WARN"));

// Delta diagnostics + Honesty Contract + Commit Guard
const dOld = { range: { start: { line: 1, character: 0 }, end: { line: 1, character: 4 } }, severity: 1, message: "old err", source: "gopls" };
const dNew = { range: { start: { line: 9, character: 2 }, end: { line: 9, character: 5 } }, severity: 1, message: "new err", source: "gopls" };
const delta1 = computeDeltaDiagnostics([dOld], [dOld, dNew], true);
check("computeDeltaDiagnostics isolates newly introduced error", delta1.added.length === 1 && delta1.added[0].message === "new err" && delta1.persistedCount === 1);
const deltaReport = formatDeltaDiagnosticsReport("a.go", delta1, true);
check("formatDeltaDiagnosticsReport shows added + suppresses pre-existing noise", deltaReport.includes("new err") && !deltaReport.includes("old err") && deltaReport.includes("pre-existing"));
const deltaResolved = computeDeltaDiagnostics([dOld], [], true);
check("formatDeltaDiagnosticsReport notes resolved diagnostics", deltaResolved.resolvedCount === 1 && formatDeltaDiagnosticsReport("a.go", deltaResolved, true).includes("resolved 1"));
check("formatHonestyNotice emits unconfirmed tag", formatHonestyNotice("gopls", "cold").includes("unconfirmed (gopls: cold)"));
check("isGitCommitOrPushCommand matches git commit && push", isGitCommitOrPushCommand("git status && git commit -m 'x'") && isGitCommitOrPushCommand("git push origin main"));
check("isGitCommitOrPushCommand ignores git status", !isGitCommitOrPushCommand("git status"));

console.log(`lsp-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
