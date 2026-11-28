import { readFileSync } from "node:fs";
import * as path from "node:path";

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

const file = path.resolve(import.meta.dir, "../../../../rules/vald-law-ttsr.md");
const text = readFileSync(file, "utf-8");
const fm = text.split(/^---\s*$/m)[1] ?? "";

// condition: block of `  - "<yaml double-quoted>"` lines. YAML double-quoted escapes
// used here (\\ and \") coincide with JSON, so JSON.parse yields the real regex source.
const m = fm.match(/^condition:\n((?:\s+- ".*"\n)+)/m);
check("frontmatter has condition list", !!m);
const conds = (m?.[1] ?? "")
  .trim()
  .split("\n")
  .map((l) => JSON.parse(l.trim().slice(2)) as string);
const res = conds.map((c) => new RegExp(c));
const hit = (s: string) => res.some((r) => r.test(s));

// Existing laws unchanged
check("conds keep Law1 errors.New regex", conds.includes("\\berrors\\.New\\s*\\("));
check("conds keep budget_tokens regex", conds.includes('"budget_tokens"\\s*:'));
check("errors.New( detected", hit('return errors.New("x")'));
check("budget_tokens detected", hit('{"budget_tokens": 10}'));

// Law 3: panic
check("conds include Law3 panic regex (exact)", conds.includes("\\bpanic\\s*\\("));
check("panic( detected", hit('panic("x")'));
check("panic ( with space detected", hit("panic  (err)"));
check("recover() alone not a hit", !hit("recover()"));
check("word 'nopanic(' not a hit (boundary)", !hit("nopanic(x)"));

// Law 4: log.Fatal / Fatalf / Fatalln
check("conds include Law4 log.Fatal regex (exact)", conds.includes("\\blog\\.Fatal(?:f|ln)?\\s*\\("));
check("log.Fatal( detected", hit("log.Fatal(err)"));
check("log.Fatalf( detected", hit('log.Fatalf("x %v", err)'));
check("log.Fatalln( detected", hit("log.Fatalln(err)"));
check("log.Fatalx( not a hit", !hit("log.Fatalx(err)"));
check("log.Error( not a hit", !hit("log.Error(err)"));
check("mylog.Fatal( not a hit (boundary)", !hit("mylog.Fatal(err)"));

// Frontmatter structure kept
for (const k of ["name: vald-law-ttsr", "globs:", "scope:", "interruptMode:", "repeatMode:"]) {
  check(`frontmatter keeps ${k}`, fm.includes(k));
}
check("exactly 4 conditions", conds.length === 4, String(conds.length));

console.log(`\nvald-law-ttsr: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
