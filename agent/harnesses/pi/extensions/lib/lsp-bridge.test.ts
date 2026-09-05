import { detectLanguage, runSymbols, runDiagnostics } from "../lsp-bridge";

let pass = 0;
let fail = 0;

function eq<T>(name: string, actual: T, expected: T) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}`);
    console.error(`  actual:   ${JSON.stringify(actual)}`);
    console.error(`  expected: ${JSON.stringify(expected)}`);
    fail++;
  }
}

function check(name: string, ok: boolean, msg?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}: ${msg || ""}`);
    fail++;
  }
}

// 1. Language detection tests
eq("detectLanguage: go", detectLanguage("main.go"), "go");
eq("detectLanguage: rust", detectLanguage("src/lib.rs"), "rust");
eq("detectLanguage: ts", detectLanguage("extension.ts"), "typescript");
eq("detectLanguage: python", detectLanguage("script.py"), "python");
eq("detectLanguage: cpp", detectLanguage("main.cpp"), "cpp");
eq("detectLanguage: nix", detectLanguage("default.nix"), "nix");
eq("detectLanguage: unknown", detectLanguage("notes.txt"), "unknown");

// 2. Symbol extraction tests
const symbols = runSymbols("agent/harnesses/pi/extensions/lsp-bridge.ts", process.cwd());
check("runSymbols extracts functions/types", symbols.length > 0, `Got ${symbols.length} symbols`);
check("runSymbols finds detectLanguage", symbols.some(s => s.includes("detectLanguage")));
check("runSymbols finds DiagnosticItem", symbols.some(s => s.includes("DiagnosticItem")));

// 3. Diagnostics sanity test
const diag = runDiagnostics("agent/harnesses/pi/extensions/lsp-bridge.ts", process.cwd());
check("runDiagnostics executes without crashing", Array.isArray(diag.diagnostics));

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
