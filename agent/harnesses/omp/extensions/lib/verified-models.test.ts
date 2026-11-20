/**
 * lib/verified-models.ts のテスト。`bun test` の単一ファイル実行で動く PASS/FAIL カウンタ形式。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { loadVerifiedModels, pickVerified, toOmpSelector, verifiedModelDir, VERIFIED_MAX_AGE_MS } from "./verified-models";

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

fs.rmSync(tmp, { recursive: true, force: true });
console.log(`\nverified-models: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
