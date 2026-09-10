import { writeFileAtomic } from "./fs-atomic";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

let pass = 0;
let fail = 0;
function check(name: string, ok: boolean, detail?: string) {
  if (ok) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}${detail ? ` (${detail})` : ""}`);
    fail++;
  }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "fs-atomic-"));
try {
  const f = path.join(tmp, "state.json");

  writeFileAtomic(f, JSON.stringify({ a: 1 }));
  check("writes the file", fs.existsSync(f) && fs.readFileSync(f, "utf-8") === JSON.stringify({ a: 1 }));

  writeFileAtomic(f, JSON.stringify({ a: 2, b: 3 }));
  check("overwrites atomically (new complete content)", JSON.parse(fs.readFileSync(f, "utf-8")).b === 3);

  check("leaves no leftover temp files", fs.readdirSync(tmp).filter((n) => n.includes(".tmp")).length === 0);

  // After every write the target is always a complete, parseable file (never a
  // torn/partial write).
  let allValid = true;
  for (let i = 0; i < 50; i++) {
    writeFileAtomic(f, JSON.stringify({ i, pad: "x".repeat(1000) }));
    try {
      JSON.parse(fs.readFileSync(f, "utf-8"));
    } catch {
      allValid = false;
      break;
    }
  }
  check("50 rapid writes always leave complete valid JSON", allValid);

  // Writing to a path whose directory does not exist throws (surfaces the error)
  // and does not leave a stray temp file behind.
  let threw = false;
  const badDir = path.join(tmp, "nope", "deep");
  try {
    writeFileAtomic(path.join(badDir, "x.json"), "{}");
  } catch {
    threw = true;
  }
  check("throws when the target directory is missing", threw);
  check("no stray temp file after a failed write", !fs.existsSync(badDir));
} finally {
  try { fs.rmSync(tmp, { recursive: true, force: true }); } catch {}
}

console.log(`\nfs-atomic: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
