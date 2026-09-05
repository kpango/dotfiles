/**
 * pi/extensions/subagents.ts の tools: フロントマター変換テスト。
 *
 * agent-hooks-and-pi-agents-unification ミッション(2026-09-03)で、pi/agents/*.md の生成器
 * (agent/scripts/gen-pi-agents.sh、廃止済み)が持っていた PascalCase(Claude Code式) →
 * lowercase(pi-coding-agent式)変換ロジックを subagents.ts 側(実行時)へ移植した際の回帰テスト。
 * `bun run agent/harnesses/pi/extensions/lib/subagents.test.ts` で実行(他テストスクリプトと同じ「PASS/FAILカウンタ +
 * 非ゼロexit」スタイル、bun:testフレームワークは使わない — pi/extensions/lib/cli-bridge.test.ts参照)。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  loadAgentsFromDirForTest,
  mapToolNames,
  resolveModelTier,
  inferTaskCategory,
  calculateEffectiveConcurrency,
  runTasksInParallelPool,
  CATEGORY_CONCURRENCY_LIMITS,
} from "../subagents";

let pass = 0;
let fail = 0;
function check(desc: string, ok: boolean, detail?: string) {
  if (ok) {
    console.log(`ok: ${desc}`);
    pass++;
  } else {
    console.log(`FAIL: ${desc}${detail ? ` (${detail})` : ""}`);
    fail++;
  }
}
function eq(desc: string, actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  check(desc, a === e, `got ${a}, want ${e}`);
}

// 1. agent/agents/*.md で実際に使われている全6トークン(Read/Write/Edit/Bash/Grep/Glob、
// 2026-09-03時点でAgent/Workflow/Skillは未使用だがMAPPING表には含める)の変換
eq(
  "mapToolNames: 実使用中の6トークン",
  mapToolNames("Read, Write, Edit, Bash, Grep, Glob"),
  ["read", "write", "edit", "bash", "grep", "find", "ls"],
);

// 2. Glob は find,ls の2トークンへ展開される(gen-pi-agents.sh MAPPING と同一契約)
eq("mapToolNames: Glob単体は[find, ls]へ展開", mapToolNames("Glob"), ["find", "ls"]);

// 3. Agent/Workflow/Skill(将来agent/agents/*.mdで使われた場合に備えた契約)
eq(
  "mapToolNames: Agent/Workflow/Skillは小文字化のみ",
  mapToolNames("Agent, Workflow, Skill"),
  ["agent", "workflow", "skill"],
);

// 4. MAPPING表に無い未知トークンは.toLowerCase()フォールバック(gen-pi-agents.shの
// `MAPPING.get(t, [t.lower()])` と同一契約)
eq("mapToolNames: 未知トークンはlowercaseフォールバック", mapToolNames("SomeFutureTool"), ["somefuturetool"]);

// 5. 配列入力(bracket構文 `tools: [Read, Write]` 経由でparseFrontmatterがarrayを返すケース)も
// 同じ変換を通ること
eq("mapToolNames: 配列入力も変換される", mapToolNames(["Read", "Glob"]), ["read", "find", "ls"]);

// 6. 空文字列・空配列は空配列を返す(fall through, agent.tools=[]でも subagents.ts 側の
// `if (agent.tools && agent.tools.length > 0)` により --tools フラグ自体が付与されない)
eq("mapToolNames: 空文字列は空配列", mapToolNames(""), []);

// 7. loadAgentsFromDir end-to-end: 一時ディレクトリに agent/agents/*.md 実物と同じ書式の
// フロントマターを持つ .md を置き、実際に変換された AgentConfig.tools を確認する
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "subagents-test-"));
fs.writeFileSync(
  path.join(tmpDir, "go-expert.md"),
  `---
name: go-expert
description: Go language specialist.
tools: Read, Write, Edit, Bash, Grep, Glob
model: sonnet
---

Go implementation specialist.
`,
);
const loaded = loadAgentsFromDirForTest(tmpDir, "user");
check("loadAgentsFromDir: 1件読み込み", loaded.length === 1, `got ${loaded.length}`);
if (loaded.length === 1) {
  eq("loadAgentsFromDir: name", loaded[0].name, "go-expert");
  eq("loadAgentsFromDir: tools変換結果", loaded[0].tools, ["read", "write", "edit", "bash", "grep", "find", "ls"]);
}
fs.rmSync(tmpDir, { recursive: true, force: true });

// 8. 実際のagent/agents/*.md(25件、正典)を全件Readし、パースエラー無く変換できることを確認する
// (mission worktreeのrepoRootから相対解決。CIやworktree環境でも動くようimport.meta.urlから解決)
{
  const filePath = fs.realpathSync(new URL(import.meta.url).pathname);
  const repoRoot = path.resolve(path.dirname(filePath), "..", "..", "..", "..", "..");
  const realAgentsDir = path.join(repoRoot, "agent", "agents");
  const realLoaded = loadAgentsFromDirForTest(realAgentsDir, "user");
  const expectedCount = fs.readdirSync(realAgentsDir).filter((f) => f.endsWith(".md")).length;
  check(
    `実agent/agents/*.md 全${expectedCount}件がパース成功`,
    realLoaded.length === expectedCount,
    `got ${realLoaded.length}, want ${expectedCount}`,
  );
  const badTools = realLoaded.filter((a) => a.tools && a.tools.some((t) => /[A-Z]/.test(t)));
  check("実agent/agents/*.md 全件でtools:に大文字が残っていない", badTools.length === 0, JSON.stringify(badTools.map((a) => a.name)));
  const knownLower = new Set(["read", "write", "edit", "bash", "grep", "find", "ls", "agent", "workflow", "skill"]);
  const unknownTools = realLoaded.flatMap((a) => (a.tools ?? []).filter((t) => !knownLower.has(t)));
  check("実agent/agents/*.md 全件でtools:がpi既知語彙に収まる", unknownTools.length === 0, JSON.stringify(unknownTools));
}

// 9. resolveModelTier 抽象モデルTierマッピングテスト
eq("resolveModelTier: inherit -> undefined", resolveModelTier("inherit"), undefined);
eq("resolveModelTier: Inherit -> undefined", resolveModelTier("Inherit"), undefined);
eq("resolveModelTier: Low -> gemini-3.8-flash-low (default)", resolveModelTier("Low"), "antigravity/gemini-3.8-flash-low");
eq("resolveModelTier: Low (context: code_research) -> qwen3.8-flash", resolveModelTier("Low", { type: "code_research" }), "opencode-go/qwen3.8-flash");
eq("resolveModelTier: Low (context: code tools + task) -> qwen3.8-flash", resolveModelTier("Low", { tools: ["read", "grep", "find"], task: "shard scan codebase" }), "opencode-go/qwen3.8-flash");
eq("resolveModelTier: Low (context: web_research) -> gemini-3.8-flash-low", resolveModelTier("Low", { type: "web_research" }), "antigravity/gemini-3.8-flash-low");
eq("resolveModelTier: Low (context: web tools + doc task) -> gemini-3.8-flash-low", resolveModelTier("Low", { tools: ["fetch"], task: "research documentation" }), "antigravity/gemini-3.8-flash-low");
eq("resolveModelTier: Low-Code -> qwen3.8-flash", resolveModelTier("Low-Code"), "opencode-go/qwen3.8-flash");
eq("resolveModelTier: Low-Web -> gemini-3.8-flash-low", resolveModelTier("Low-Web"), "antigravity/gemini-3.8-flash-low");
eq("resolveModelTier: Medium -> kimi-k3", resolveModelTier("Medium"), "opencode-go/kimi-k3");
eq("resolveModelTier: High -> claude-sonnet-5 (primary)", resolveModelTier("High"), "anthropic/claude-sonnet-5");
eq("resolveModelTier: High (trigger: rate_limit) -> claude-sonnet-4-6", resolveModelTier("High", { trigger: "rate_limit" }), "anthropic/claude-sonnet-4-6");
eq("resolveModelTier: High (trigger: token_exhaustion) -> deepseek-v4-pro", resolveModelTier("High", { trigger: "token_exhaustion" }), "opencode-go/deepseek-v4-pro");
eq("resolveModelTier: High (trigger: cost_saver) -> gemini-3.8-flash-high", resolveModelTier("High", { trigger: "cost_saver" }), "antigravity/gemini-3.8-flash-high");
eq("resolveModelTier: High (fallbackIndex: 1) -> deepseek-v4-pro", resolveModelTier("High", { fallbackIndex: 1 }), "opencode-go/deepseek-v4-pro");
eq("resolveModelTier: XHigh (trigger: rate_limit) -> gemini-3.8-flash-high", resolveModelTier("XHigh", { trigger: "rate_limit" }), "antigravity/gemini-3.8-flash-high");
eq("resolveModelTier: XHigh (trigger: token_exhaustion) -> kimi-k3", resolveModelTier("XHigh", { trigger: "token_exhaustion" }), "opencode-go/kimi-k3");
eq("resolveModelTier: XHigh -> gpt-6-astra", resolveModelTier("XHigh"), "codex/gpt-6-astra");
eq("resolveModelTier: Max -> claude-fable-5-1", resolveModelTier("Max"), "anthropic/claude-fable-5-1");
eq("resolveModelTier: Max (trigger: token_exhaustion) -> claude-fable-5", resolveModelTier("Max", { trigger: "token_exhaustion" }), "anthropic/claude-fable-5");
eq("resolveModelTier: custom-model passthrough", resolveModelTier("custom-model"), "custom-model");

// 10. inferTaskCategory tests
eq("inferTaskCategory: go-expert -> coding", inferTaskCategory("go-expert"), "coding");
eq("inferTaskCategory: teamwork_preview_worker -> coding", inferTaskCategory("teamwork_preview_worker"), "coding");
eq("inferTaskCategory: task with implement -> coding", inferTaskCategory("general", "implement cache layer"), "coding");
eq("inferTaskCategory: research -> research", inferTaskCategory("research"), "research");
eq("inferTaskCategory: task with survey -> research", inferTaskCategory("unknown", "survey documentation"), "research");
eq("inferTaskCategory: perf-analyzer -> benchmark", inferTaskCategory("perf-analyzer"), "benchmark");
eq("inferTaskCategory: ann-perf-engineer -> benchmark", inferTaskCategory("ann-perf-engineer"), "benchmark");
eq("inferTaskCategory: task with criterion -> benchmark", inferTaskCategory("unknown", "run criterion benchmark"), "benchmark");
eq("inferTaskCategory: debugger -> debugging", inferTaskCategory("debugger"), "debugging");
eq("inferTaskCategory: ci-investigator -> debugging", inferTaskCategory("ci-investigator"), "debugging");
eq("inferTaskCategory: teamwork_preview_test_writer -> testing", inferTaskCategory("teamwork_preview_test_writer"), "testing");
eq("inferTaskCategory: task with go test -> testing", inferTaskCategory("unknown", "run go test ./..."), "testing");
eq("inferTaskCategory: security-adversarial-reviewer -> review", inferTaskCategory("security-adversarial-reviewer"), "review");

// 11. Concurrency limits & calculateEffectiveConcurrency tests
eq("CATEGORY_CONCURRENCY_LIMITS: coding=16", CATEGORY_CONCURRENCY_LIMITS.coding, 16);
eq("CATEGORY_CONCURRENCY_LIMITS: research=100", CATEGORY_CONCURRENCY_LIMITS.research, 100);
eq("CATEGORY_CONCURRENCY_LIMITS: benchmark=4", CATEGORY_CONCURRENCY_LIMITS.benchmark, 4);
eq("CATEGORY_CONCURRENCY_LIMITS: testing=50", CATEGORY_CONCURRENCY_LIMITS.testing, 50);
eq("CATEGORY_CONCURRENCY_LIMITS: debugging=4", CATEGORY_CONCURRENCY_LIMITS.debugging, 4);

eq(
  "calculateEffectiveConcurrency: homogeneous research -> 100",
  calculateEffectiveConcurrency([
    { agent: "research", task: "scan 1" },
    { agent: "research", task: "scan 2" },
  ]),
  100
);

eq(
  "calculateEffectiveConcurrency: homogeneous coding -> 16",
  calculateEffectiveConcurrency([
    { agent: "go-expert", task: "code" },
    { agent: "rust-expert", task: "code" },
  ]),
  16
);

eq(
  "calculateEffectiveConcurrency: homogeneous testing -> 50",
  calculateEffectiveConcurrency([
    { agent: "teamwork_preview_test_writer", task: "author test" },
    { agent: "general", task: "run unit test" },
  ]),
  50
);

eq(
  "calculateEffectiveConcurrency: mixed coding + benchmark -> 4 (most constrained)",
  calculateEffectiveConcurrency([
    { agent: "go-expert", task: "code" },
    { agent: "perf-analyzer", task: "benchmark" },
  ]),
  4
);

// 12. runTasksInParallelPool tests
{
  const items = Array.from({ length: 25 }, (_, i) => i);
  let activeConcurrency = 0;
  let maxObservedConcurrency = 0;

  const results = await runTasksInParallelPool(items, 8, async (item) => {
    activeConcurrency++;
    if (activeConcurrency > maxObservedConcurrency) {
      maxObservedConcurrency = activeConcurrency;
    }
    // Simulate brief asynchronous tick
    await new Promise((r) => setTimeout(r, 5));
    activeConcurrency--;
    return item * 2;
  });

  check("runTasksInParallelPool: completes all 25 items", results.length === 25);
  check("runTasksInParallelPool: preserves item ordering", results[10] === 20 && results[24] === 48);
  check(
    "runTasksInParallelPool: respects max concurrency 8",
    maxObservedConcurrency <= 8 && maxObservedConcurrency > 1,
    `max observed was ${maxObservedConcurrency}`
  );
}

console.log(`\n${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
