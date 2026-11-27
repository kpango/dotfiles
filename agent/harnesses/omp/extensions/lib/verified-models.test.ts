/**
 * lib/verified-models.ts のテスト。`bun test` の単一ファイル実行で動く PASS/FAIL カウンタ形式。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  loadVerifiedModels,
  pickVerified,
  toOmpSelector,
  verifiedModelDir,
  isVerifiedCacheFresh,
  refreshVerifiedModels,
  verifiedRefetchTargets,
  VERIFIED_MAX_AGE_MS,
  VERIFIED_REFRESH_INTERVAL_MS,
  VERIFIED_FAILURE_RETRY_MS,
} from "./verified-models";

let pass = 0;
let fail = 0;
function eq(name: string, actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) pass++;
  else {
    fail++;
    console.error(`FAIL: ${name}\n  actual:   ${JSON.stringify(actual)}\n  expected: ${JSON.stringify(expected)}`);
  }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "verified-models-"));
const NOW = 1_800_000_000_000;
const write = (cli: string, rec: object) => fs.writeFileSync(path.join(tmp, `${cli}.json`), JSON.stringify(rec));
const fresh = NOW / 1000 - 60;

eq("empty dir -> empty set (fail-closed)", [...loadVerifiedModels(NOW, tmp)], []);

write("omp", { status: "ok", fetched_at: fresh, models: ["anthropic/claude-opus-5-5", "openai-codex/gpt-6.2-astra"] });
write("agy", { status: "ok", fetched_at: fresh, models: ["antigravity-cli/gemini-4-hydrogen"] });
eq("ok lists are unioned", [...loadVerifiedModels(NOW, tmp)].sort(), [
  "anthropic/claude-opus-5-5",
  "antigravity-cli/gemini-4-hydrogen",
  "openai-codex/gpt-6.2-astra",
]);

write("agy", { status: "unavailable", fetched_at: fresh, models: ["antigravity-cli/gemini-4-hydrogen"] });
eq("unavailable status contributes nothing even if models are present", loadVerifiedModels(NOW, tmp).has("antigravity-cli/gemini-4-hydrogen"), false);

write("agy", { status: "ok", fetched_at: NOW / 1000 - VERIFIED_MAX_AGE_MS / 1000 - 1, models: ["antigravity-cli/gemini-4-hydrogen"] });
eq("stale list is ignored", loadVerifiedModels(NOW, tmp).has("antigravity-cli/gemini-4-hydrogen"), false);

fs.writeFileSync(path.join(tmp, "agy.json"), "{not json");
eq("corrupt cache is ignored, other CLI still counts", loadVerifiedModels(NOW, tmp).has("anthropic/claude-opus-5-5"), true);

eq("toOmpSelector: openai -> openai-codex", toOmpSelector("openai/gpt-6.2-sol"), "openai-codex/gpt-6.2-sol");
eq("toOmpSelector: effort suffix stripped", toOmpSelector("anthropic/claude-opus-5-5:xhigh"), "anthropic/claude-opus-5-5");
eq("toOmpSelector: other providers untouched", toOmpSelector("opencode-go/kimi-k3.1-pro"), "opencode-go/kimi-k3.1-pro");

const v = loadVerifiedModels(NOW, tmp);
eq("pickVerified: verified ref", pickVerified("anthropic/claude-opus-5-5:high", v), "anthropic/claude-opus-5-5");
eq("pickVerified: openai alias resolves to verified codex model", pickVerified("openai/gpt-6.2-astra", v), "openai-codex/gpt-6.2-astra");
eq("pickVerified: unlisted model rejected", pickVerified("anthropic/claude-haiku-5-5", v), undefined);
eq("pickVerified: undefined input", pickVerified(undefined, v), undefined);

eq("verifiedModelDir: AGENT_MODEL_LIST_DIR wins", verifiedModelDir({ AGENT_MODEL_LIST_DIR: "/x" }, "/h"), "/x");
eq("verifiedModelDir: XDG_CACHE_HOME", verifiedModelDir({ XDG_CACHE_HOME: "/c" }, "/h"), "/c/agent-model-lists");
eq("verifiedModelDir: home fallback", verifiedModelDir({}, "/h"), "/h/.cache/agent-model-lists");

// --- session_start 再取得ゲート -------------------------------------------------
const gate = fs.mkdtempSync(path.join(os.tmpdir(), "verified-gate-"));
const writeGate = (cli: string, rec: object) => fs.writeFileSync(path.join(gate, `${cli}.json`), JSON.stringify(rec));

eq("gate: empty dir is stale", isVerifiedCacheFresh(NOW, gate), false);
writeGate("omp", { status: "ok", fetched_at: fresh, models: [] });
eq("gate: one CLI missing is stale", isVerifiedCacheFresh(NOW, gate), false);
writeGate("agy", { status: "ok", fetched_at: fresh, models: [] });
eq("gate: both fresh is fresh", isVerifiedCacheFresh(NOW, gate), true);
writeGate("agy", { status: "ok", fetched_at: NOW / 1000 - VERIFIED_REFRESH_INTERVAL_MS / 1000 - 1, models: [] });
eq("gate: older than refresh interval is stale", isVerifiedCacheFresh(NOW, gate), false);
writeGate("agy", { status: "unavailable", fetched_at: fresh, models: [] });
eq("gate: unavailable is stale", isVerifiedCacheFresh(NOW, gate), false);
eq(
  "targets: one unavailable but recent CLI is not refetched",
  verifiedRefetchTargets(NOW, gate),
  [],
);
writeGate("agy", {
  status: "unavailable",
  fetched_at: NOW / 1000 - VERIFIED_FAILURE_RETRY_MS / 1000 - 1,
  models: [],
});
eq("targets: failed CLI retried after failure interval", verifiedRefetchTargets(NOW, gate), ["agy"]);
writeGate("agy", { status: "ok", fetched_at: fresh, models: [] });
eq("targets: fresh ok cache needs nothing", verifiedRefetchTargets(NOW, gate), []);
eq("targets: missing record is due", verifiedRefetchTargets(NOW, path.join(gate, "missing")), ["omp", "agy"]);

let runs = 0;
let fetched: string[] = [];
refreshVerifiedModels("/x/fetch-harness-models.py", {
  now: NOW,
  dir: gate,
  run: (_p, clis) => {
    runs++;
    fetched = clis;
  },
});
eq("refresh: fresh cache skips the CLI fetch", runs, 0);
writeGate("agy", {
  status: "unavailable",
  fetched_at: NOW / 1000 - VERIFIED_FAILURE_RETRY_MS / 1000 - 1,
  models: [],
});
refreshVerifiedModels("/x/fetch-harness-models.py", {
  now: NOW,
  dir: gate,
  run: (_p, clis) => {
    runs++;
    fetched = clis;
  },
});
eq("refresh: only the failing CLI is refetched", fetched, ["agy"]);
writeGate("agy", { status: "ok", fetched_at: NOW / 1000 - VERIFIED_REFRESH_INTERVAL_MS / 1000 - 1, models: [] });
refreshVerifiedModels("/x/fetch-harness-models.py", { now: NOW, dir: gate, run: () => runs++ });
eq("refresh: stale ok cache runs the CLI fetch", runs, 2);
// 上の run はキャッシュを書き換えないので、まだ stale のまま = 再度 fetch が走る。
refreshVerifiedModels("/x/fetch-harness-models.py", {
  now: NOW,
  dir: gate,
  run: () => {
    throw new Error("boom");
  },
});
eq("refresh: fetch errors are swallowed", runs, 2);
fs.rmSync(gate, { recursive: true, force: true });

fs.rmSync(tmp, { recursive: true, force: true });
console.log(`\nverified-models: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
