import { searchSessionFiles, formatSessionSearchResults } from "../session-search";
import * as fs from "node:fs";
import * as os from "node:os";
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

// 1. Create temporary sessions directory
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "pi-sessions-test-"));
fs.writeFileSync(
  path.join(tmpDir, "session-1.json"),
  JSON.stringify({
    messages: [{ role: "user", content: "How do I optimize AVX-512 distance kernels in Go?" }],
  })
);
fs.writeFileSync(
  path.join(tmpDir, "session-2.json"),
  JSON.stringify({
    messages: [{ role: "user", content: "Implement Vald Law 5 error propagation fix" }],
  })
);

// 2. Search session files
const avxResults = searchSessionFiles(tmpDir, "AVX-512");
check("searchSessionFiles matches session-1.json", avxResults.length === 1 && avxResults[0].sessionFile === "session-1.json");
check("searchSessionFiles includes matched snippet", avxResults[0].matchedText.includes("AVX-512"));

const valdResults = searchSessionFiles(tmpDir, "vald law");
check("searchSessionFiles is case-insensitive", valdResults.length === 1 && valdResults[0].sessionFile === "session-2.json");

// 3. Format results
const formatted = formatSessionSearchResults(avxResults, "AVX-512");
check("formatSessionSearchResults contains session title", formatted.includes("session-1.json"));
check("formatSessionSearchResults handles empty results", formatSessionSearchResults([], "missing").includes("No historical sessions"));

// 4. Newest-first ordering: make both files contain a common marker and give
//    the alphabetically-LATER file (session-2.json) a NEWER mtime, so
//    truncation at maxResults=1 must prefer session-2.json — a name-ascending
//    sort (the old behavior) would return session-1.json instead.
fs.appendFileSync(
  path.join(tmpDir, "session-1.json"),
  JSON.stringify({ marker: "shared-search-token" })
);
fs.appendFileSync(
  path.join(tmpDir, "session-2.json"),
  JSON.stringify({ marker: "shared-search-token" })
);
const now = Date.now();
fs.utimesSync(path.join(tmpDir, "session-1.json"), new Date(now), new Date(now));
fs.utimesSync(path.join(tmpDir, "session-2.json"), new Date(now), new Date(now + 10_000));
const ordered = searchSessionFiles(tmpDir, "shared-search-token", 1);
check(
  "searchSessionFiles prefers newest session on truncation",
  ordered.length === 1 && ordered[0].sessionFile === "session-2.json"
);
check("searchSessionFiles includes timestamp", typeof ordered[0]?.timestamp === "string" && ordered[0].timestamp.length > 0);

// Cleanup
fs.rmSync(tmpDir, { recursive: true, force: true });

console.log(`\nsession-search: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
