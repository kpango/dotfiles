import { detectLanguage, runSymbols, runDiagnostics } from "../lsp-bridge";
import * as path from "node:path";

// Resolve the target file relative to this test file, not process.cwd(), so the
// suite is invariant to the directory `bun test` is launched from. `import.meta.dir`
// is `<repo>/agent/harnesses/pi/extensions/lib`; the target sits one level up.
const EXT_DIR = path.resolve(import.meta.dir, "..");
const LSP_TARGET = path.join(EXT_DIR, "lsp-bridge.ts");

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
const symbols = runSymbols(LSP_TARGET, EXT_DIR);
check("runSymbols extracts functions/types", symbols.length > 0, `Got ${symbols.length} symbols`);
check("runSymbols finds detectLanguage", symbols.some(s => s.includes("detectLanguage")));
check("runSymbols finds DiagnosticItem", symbols.some(s => s.includes("DiagnosticItem")));

// 2b. L1 regression: the regex symbol reader must anchor func/fn/def at line
// start so mid-line keywords are NOT misreported, while real declarations
// (incl. Rust `pub fn`/`pub struct`, `async def`, Go receivers) are captured.
import * as fs from "node:fs";
import * as os from "node:os";
const fixDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-lsp-sym-"));
try {
  const fixture = [
    "// this func does important work",
    "function realFunc(a) { return a; }",
    "const x = myfunc call;",
    "return fn helper thing;",
    "export async function expFn(b) {}",
    "pub fn rustFunc() {}",
    "pub async fn asyncRust() {}",
    "async def pyAsync(): pass",
    "func (r *Recv) GoMethod() {}",
    "type TSType = string;",
    "pub struct RustStruct {}",
  ].join("\n");
  const fixPath = path.join(fixDir, "fixture.ts");
  fs.writeFileSync(fixPath, fixture, "utf-8");
  const syms = runSymbols(fixPath, fixDir);
  const names = syms.join(" | ");
  check("sym: comment 'func does' NOT reported", !/\bdoes\b/.test(names));
  check("sym: 'myfunc call' NOT reported", !/\] call \(/.test(names));
  check("sym: 'fn helper' NOT reported", !/\] helper \(/.test(names));
  check("sym: real function realFunc captured", names.includes("realFunc"));
  check("sym: export async function expFn captured", names.includes("expFn"));
  check("sym: Rust pub fn rustFunc captured", names.includes("rustFunc"));
  check("sym: Rust pub async fn asyncRust captured", names.includes("asyncRust"));
  check("sym: async def pyAsync captured", names.includes("pyAsync"));
  check("sym: Go receiver method GoMethod captured", names.includes("GoMethod"));
  check("sym: TS type captured", names.includes("TSType"));
  check("sym: Rust pub struct captured", names.includes("RustStruct"));
} finally {
  fs.rmSync(fixDir, { recursive: true, force: true });
}

// 3. Diagnostics sanity test
const diag = runDiagnostics(LSP_TARGET, EXT_DIR);
check("runDiagnostics executes without crashing", Array.isArray(diag.diagnostics));

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
