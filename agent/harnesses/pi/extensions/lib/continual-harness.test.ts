/**
 * Tests for Continual Harness Refinement Core Library
 *
 * Verifies session error scanning, failure signature aggregation,
 * proposal generation, syntax validation, and safe proposal application.
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  scanSessionErrors,
  generateRefinements,
  validateProposalSyntax,
  applyProposal,
  computeSessionFriction,
  evaluateRegressionStep,
  loadRefinementLedger,
  rollbackRefinementFromBackup,
  saveRefinementLedger,
  type AppliedRefinementRecord,
  type FailureSignature,
  ALWAYS_LOADED_COMPONENTS,
  HARNESS_MAX_INPUT_BYTES,
  classifyHarnessComponent,
  classifyHarnessScope,
  clusterHarnessTraces,
  countEvidenceQuoteMismatches,
  detectActionFusionMisses,
  detectPricingCliffCrossings,
  estimateHarnessTokens,
  evaluateTargetBudget,
  hasUnsafeHarnessChar,
  readFdBounded,
  readHarnessTextFile,
  validateHarnessTarget,
  validateNetTokenBudget,
} from "./continual-harness-core";
import { DEFAULT_CONFIG, setPricingCliffCatalog, type SolPiConfig } from "./sol-pi-core";

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

console.log("=== Running Continual Harness Refinement Tests ===\n");

// Setup temporary directory for test sessions and configs
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "continual-harness-test-"));
const testSessionsDir = path.join(tempDir, "sessions");
fs.mkdirSync(testSessionsDir, { recursive: true });

try {
  // --------------------------------------------------------------------------
  // Test 1: Log Scanning & Failure Signature Extraction
  // --------------------------------------------------------------------------
  // Create mock recent session file with various error events
  const session1 = path.join(testSessionsDir, "session_recent.jsonl");
  const lines = [
    JSON.stringify({ type: "tool_use", tool: "read", params: { file: "test.ts" } }),
    JSON.stringify({ type: "error", error: "Security Gate blocked modification to protected path: /etc/passwd" }),
    JSON.stringify({ type: "turn", model: "anthropic/claude-sonnet-5-5", error: "429 Too Many Requests: rate_limit_exceeded" }),
    JSON.stringify({ type: "turn", model: "anthropic/claude-sonnet-5-5", error: "rate limit reached on provider anthropic" }),
    JSON.stringify({ type: "error", model: "anthropic/claude-sonnet-5-5", error: "token_exhaustion: context window maximum context length exceeded" }),
    JSON.stringify({ type: "tool_result", tool: "bash", exitCode: 1, isError: true, output: "Command failed: exit code 1" }),
    JSON.stringify({ type: "tool_result", tool: "bash", exitCode: 2, isError: true, output: "Command failed: syntax error" }),
    JSON.stringify({ type: "tool_result", tool: "bash", exitCode: 1, isError: true, output: "Command failed: timeout" }),
  ];
  fs.writeFileSync(session1, lines.join("\n"), "utf-8");

  // Create an old session that should be excluded by daysWindow
  const sessionOld = path.join(testSessionsDir, "session_old.jsonl");
  fs.writeFileSync(sessionOld, JSON.stringify({ error: "old 429 rate limit" }), "utf-8");
  const oldTime = (Date.now() - 15 * 24 * 60 * 60 * 1000) / 1000;
  fs.utimesSync(sessionOld, oldTime, oldTime);

  const signatures = scanSessionErrors(testSessionsDir, 7);

  check("Scan finds failure signatures", signatures.length > 0);
  const hookSig = signatures.find((s) => s.category === "hook_rejection");
  check("Hook rejection signature detected", Boolean(hookSig && hookSig.occurrences === 1));

  const rateLimitSig = signatures.find((s) => s.category === "rate_limit");
  check("Rate limit signature detected", Boolean(rateLimitSig && rateLimitSig.occurrences === 2));
  check("Rate limit identified model anthropic/claude-sonnet-5-5", rateLimitSig?.model === "anthropic/claude-sonnet-5-5");

  const tokenSig = signatures.find((s) => s.category === "token_exhaustion");
  check("Token exhaustion signature detected", Boolean(tokenSig && tokenSig.occurrences === 1));

  const toolSig = signatures.find((s) => s.category === "tool_error");
  check("Tool error signature detected with 3 occurrences", Boolean(toolSig && toolSig.occurrences === 3));

  // Non-existent directory handling
  const emptyScan = scanSessionErrors(path.join(tempDir, "non_existent_dir"), 7);
  check("Missing sessions dir returns empty array gracefully", Array.isArray(emptyScan) && emptyScan.length === 0);

  // --------------------------------------------------------------------------
  // Test 2: Proposal Generation
  // --------------------------------------------------------------------------
  const mockRouting = {
    $schema: "../../models/schema.json",
    harness: "pi",
    default_tier: "High",
    tiers: {
      High: {
        provider: "anthropic",
        model: "anthropic/claude-sonnet-5-5",
        effort: "high",
        fallbacks: [
          { provider: "antigravity-cli", model: "antigravity-cli/claude-sonnet-5-5", effort: "high", trigger: "rate_limit" },
        ],
      },
      Low: {
        provider: "antigravity-cli",
        model: "antigravity-cli/gemini-4-hydrogen",
        effort: "low",
        fallbacks: [],
      },
    },
  };

  const mockSettings = {
    version: 1,
    defaultProvider: "anthropic",
    defaultModel: "anthropic/claude-sonnet-5-5",
    defaultThinkingLevel: "high",
    modelThinkingLevels: {
      "anthropic/claude-sonnet-5-5": "high",
    },
    compaction: {
      reserveTokens: 16384,
      keepRecentTokens: 32768,
    },
    retry: {
      enabled: true,
      maxRetries: 3,
      baseDelayMs: 2000,
    },
  };

  const proposals = generateRefinements(signatures, mockRouting, mockSettings);

  check("Proposals generated from signatures", proposals.length > 0);

  // Check token exhaustion refinement in sol-pi.json
  const tokenProp = proposals.find((p) => p.diffType === "thinking_budget");
  check("Token budget proposal generated", Boolean(tokenProp));
  check(
    "Token proposal lowers model thinking level to medium",
    tokenProp?.proposedPatch.modelThinkingLevels["anthropic/claude-sonnet-5-5"] === "medium"
  );
  check(
    "Token proposal increases compaction reserveTokens to 24576+",
    tokenProp?.proposedPatch.compaction.reserveTokens >= 24576
  );

  // Check retry tuning proposal
  const retryProp = proposals.find((p) => p.diffType === "retry_tuning");
  check("Retry tuning proposal generated", Boolean(retryProp));
  check("Retry tuning increases maxRetries to 5", retryProp?.proposedPatch.retry.maxRetries === 5);

  // --------------------------------------------------------------------------
  // Test 3: Proposal Syntax Validation
  // --------------------------------------------------------------------------
  const validCheck = validateProposalSyntax(tokenProp!, JSON.stringify(mockSettings, null, 2));
  check("Valid proposal passes validation", validCheck.valid === true);

  // Corrupted base content
  const badBaseCheck = validateProposalSyntax(tokenProp!, "{ invalid json content");
  check("Invalid base content fails validation", badBaseCheck.valid === false);

  // Corrupted proposal patch missing required tiers in model-routing
  const badRoutingProp = {
    id: "test_bad",
    targetFile: "model-routing.json",
    rationale: "bad test",
    diffType: "routing_fallback" as const,
    proposedPatch: { corrupted: true },
    confidence: 0.5,
  };
  const badRoutingCheck = validateProposalSyntax(badRoutingProp, JSON.stringify(mockRouting, null, 2));
  check("Malformed model-routing proposal fails schema validation", badRoutingCheck.valid === false);

  // --------------------------------------------------------------------------
  // Test 4: Proposal Application with Backup
  // --------------------------------------------------------------------------
  const repoMockRoot = path.join(tempDir, "repo");
  const configDir = path.join(repoMockRoot, "agent", "harnesses", "pi");
  fs.mkdirSync(configDir, { recursive: true });

  const solPiFile = path.join(configDir, "sol-pi.json");
  fs.writeFileSync(solPiFile, JSON.stringify(mockSettings, null, 2), "utf-8");

  const applyRes = applyProposal(repoMockRoot, tokenProp!);
  check("applyProposal succeeds", applyRes.success === true);
  check("applyProposal returns modifiedPath", applyRes.modifiedPath === solPiFile);
  check("applyProposal created backup file", Boolean(applyRes.backupPath && fs.existsSync(applyRes.backupPath)));

  // Verify backup contains original settings
  const backupContent = fs.readFileSync(applyRes.backupPath!, "utf-8");
  const backupObj = JSON.parse(backupContent);
  check("Backup retains original high thinking level", backupObj.modelThinkingLevels["anthropic/claude-sonnet-5-5"] === "high");

  // Verify modified file contains applied patch
  const modifiedContent = fs.readFileSync(solPiFile, "utf-8");
  const modifiedObj = JSON.parse(modifiedContent);
  check("Applied file has updated medium thinking level", modifiedObj.modelThinkingLevels["anthropic/claude-sonnet-5-5"] === "medium");


  // --------------------------------------------------------------------------
  // Test 5: Harness² C1-C8 mapping, INV/DOM tags, trace validation
  // --------------------------------------------------------------------------
  const COMPONENT_TABLE: Array<[string, string | null]> = [
    ["agent/harnesses/pi/SYSTEM.md", "C1"],
    ["agent/rules/impact-scope.md", "C2"],
    ["agent/rules/sub/dir/x.md", "C2"],
    ["a/./rules/b.md", "C2"],
    ["agent/rules/x.txt", null],
    ["agent/rules", null],
    ["agent/context/library/EXPERIENCE.md", "C3"],
    ["AGENTS.md", "C4"],
    ["agent/harnesses/claude/CLAUDE.md", "C4"],
    ["agent/agents/code-reviewer.md", "C5"],
    ["agent/agents/.md", null],
    ["agent/skills/swarm-evolve/SKILL.md", "C6"],
    ["agent/skills/a/b/SKILL.md", null],
    ["skills/SKILL.md", null],
    ["SKILL.md", null],
    ["agent/scripts/evolve/harness2-offline.py", "C7"],
    ["agent/scripts/x.sh", null],
    ["agent/other/x.py", null],
    ["agent/harnesses/pi/extensions/lib/x.ts", "C8"],
    ["agent/hooks/pi/security-gate.ts", "C8"],
    ["hooks/pi/x.ts", "C8"],
    ["pi/x.ts", null],
    ["agent/hooks/claude/x.sh", null],
    ["agent/other/x.ts", null],
    ["README.md", null],
  ];
  for (const [target, expected] of COMPONENT_TABLE) {
    check(`classify ${target} -> ${expected}`, classifyHarnessComponent(target) === expected, `got ${classifyHarnessComponent(target)}`);
  }
  check("classify rejects non-string", classifyHarnessComponent(42 as any) === null);
  check("scope: 1 task -> DOM", classifyHarnessScope(["t1", "t1"]) === "DOM");
  check("scope: 2 tasks -> INV", classifyHarnessScope(["t1", "t2"]) === "INV");

  const FULLWIDTH_A = String.fromCodePoint(0xff21); // code point order: below U+10400
  const DESERET = String.fromCodePoint(0x10400); // UTF-16 code unit order: below U+FF21
  const TRACES = [
    ...["t1", "t2", "t3"].map((task) => ({ signature: "Hook  Rejected", task, target: "agent/rules/x.md", manifest: ["agent/scripts/a.py", "agent/rules/x.md"] })),
    ...["t1", "t1", "t1"].map((task) => ({ signature: "dom failure", task, target: "agent/scripts/a.py" })),
    ...["t1", "t2"].map((task) => ({ signature: "noise", task, target: "agent/rules/x.md" })),
    ...["t1", "t2", "t3"].map((task) => ({ signature: "unclassified", task, target: "agent/other/x.ts" })),
    { signature: "tie", task: "t1", target: "agent/rules/b.md", manifest: ["agent/scripts/b.py", "agent/scripts/a.py"] },
    { signature: "tie", task: "t1", target: "agent/rules/a.md" },
    { signature: "tie", task: "t2", target: "agent/rules/a.md" },
    { signature: "tie", task: "t2", target: "agent/rules/b.md" },
    { signature: DESERET, task: "t1", target: "agent/rules/x.md" },
    { signature: FULLWIDTH_A, task: "t1", target: "agent/rules/x.md" },
    ...["t1", "t2", "t3"].map((task) => ({ signature: "normalized target", task, target: "agent//rules/./n.md" })),
  ];
  const clusters = clusterHarnessTraces(TRACES, 3);
  const bySig = (s: string) => clusters.find((c) => c.signature === s)!;
  check("cluster INV tag", bySig("hook rejected").scope === "INV" && bySig("hook rejected").tasks === 3);
  check("cluster DOM tag", bySig("dom failure").scope === "DOM" && bySig("dom failure").component === "C7");
  check("cluster below min occurrences is rejected", bySig("noise").status === "rejected" && bySig("noise").reason === "below_min_occurrences");
  check("cluster unclassified target is rejected", bySig("unclassified").reason === "unclassified_target");
  check("cluster tie on target picks the lexicographically first", bySig("tie").target === "agent/rules/a.md");
  check("cluster accepted keeps component", bySig("hook rejected").status === "accepted" && bySig("hook rejected").component === "C2");
  check("cluster manifests are sorted and deduplicated", JSON.stringify(bySig("hook rejected").manifests) === JSON.stringify(["agent/rules/x.md", "agent/scripts/a.py"]));
  check("cluster manifests union across traces", JSON.stringify(bySig("tie").manifests) === JSON.stringify(["agent/scripts/a.py", "agent/scripts/b.py"]));
  check("cluster target is normalized like PurePosixPath", bySig("normalized target").target === "agent/rules/n.md");
  check(
    "cluster order is by code point, not UTF-16 code unit",
    clusters.map((c) => c.signature).indexOf(FULLWIDTH_A.toLowerCase()) < clusters.map((c) => c.signature).indexOf(DESERET.toLowerCase()),
  );
  const throws = (fn: () => unknown) => {
    try {
      fn();
      return false;
    } catch {
      return true;
    }
  };
  const tr = (o: any) => [{ signature: "s", task: "t", target: "agent/rules/x.md", ...o }];
  check("cluster fails closed on non-string task", throws(() => clusterHarnessTraces(tr({ task: 1 }))));
  check("cluster fails closed on unsafe char in signature", throws(() => clusterHarnessTraces(tr({ signature: "a" + String.fromCodePoint(0x200b) + "b" }))));
  check("cluster fails closed on newline in task", throws(() => clusterHarnessTraces(tr({ task: "a\nb" }))));
  check("cluster fails closed on blank signature", throws(() => clusterHarnessTraces(tr({ signature: "   " }))));
  check("cluster fails closed on overlong signature (200 ok, 201 not)", !throws(() => clusterHarnessTraces(tr({ signature: "a".repeat(200) }))) && throws(() => clusterHarnessTraces(tr({ signature: "a".repeat(201) }))));
  check("cluster fails closed on '..' target", throws(() => clusterHarnessTraces(tr({ target: "../x.md" }))));
  check("cluster fails closed on absolute target", throws(() => clusterHarnessTraces(tr({ target: "/x.md" }))));
  check("cluster fails closed on target with a space", throws(() => clusterHarnessTraces(tr({ target: "a b.md" }))));
  check("cluster fails closed on non-object record", throws(() => clusterHarnessTraces([null as any])));

  const TARGET_OK = ["agent/rules/x.md", "a//b/./c.md", "a..b/c.md", "x@1+2/y_z-w.md"];
  const TARGET_BAD = ["", ".", "./", "/abs.md", "../x.md", "a/../b.md", "a b.md", "a;b.md", "a\nb.md", "a\0b.md", "あ.md", "a".repeat(301)];
  for (const t of TARGET_OK) check(`target ok: ${JSON.stringify(t)}`, !throws(() => validateHarnessTarget(t)));
  for (const t of TARGET_BAD) check(`target rejected: ${JSON.stringify(t).slice(0, 40)}`, throws(() => validateHarnessTarget(t)));
  check("target rejected: non-string", throws(() => validateHarnessTarget(7)));

  const cp = String.fromCodePoint;
  const UNSAFE_TABLE = [
    "abc", "あい", "a b", "tab\there", "x\ny", "z\0z", "a" + cp(0x200b), "a" + cp(0xa0), "a" + cp(0x2028), cp(0x3164), "a" + cp(0xfe0f),
    "a" + cp(0xe0100), "e" + cp(0x301), "😀", cp(0xfffe), cp(0xe000), String.fromCharCode(0xd800), cp(0x180b), cp(0x1d159), cp(0x34f),
    cp(0xad), cp(0x378), cp(0x1680), cp(0x2800), cp(0xfeff), "漢字",
  ];
  check("unsafe-char table has both verdicts", UNSAFE_TABLE.some(hasUnsafeHarnessChar) && UNSAFE_TABLE.some((s) => !hasUnsafeHarnessChar(s)));

  // --------------------------------------------------------------------------
  // Test 6: Net Token Budget (delta <= 0, UTF-8 byte estimate, fail-closed)
  // --------------------------------------------------------------------------
  check("tokens: ceil(bytes/4)", estimateHarnessTokens("") === 0 && estimateHarnessTokens("abcd") === 1 && estimateHarnessTokens("abcde") === 2);
  check("tokens: multibyte counted in bytes", estimateHarnessTokens("あ") === 1 && estimateHarnessTokens("あい") === 2);
  const eq = validateNetTokenBudget("abcd", "wxyz");
  check("budget: delta == 0 is ok", eq.ok && eq.delta === 0 && eq.before === 1 && eq.after === 1);
  const shrink = validateNetTokenBudget("abcdefgh", "abcd");
  check("budget: shrink is ok", shrink.ok && shrink.delta === -1);
  const grow = validateNetTokenBudget("abcd", "abcde");
  check("budget: delta == +1 is rejected", !grow.ok && grow.delta === 1 && grow.error === undefined);
  const cjk = validateNetTokenBudget("abcdefghijkl", "あいうえお");
  check("budget: CJK growth cannot hide behind a char count", !cjk.ok && cjk.delta === 1, JSON.stringify(cjk));
  const bad = (b: any, a: any) => {
    const r = validateNetTokenBudget(b, a);
    return !r.ok && typeof r.error === "string" && Number.isNaN(r.delta) && !(r.delta <= 0);
  };
  check("budget: non-string before fails closed (delta NaN)", bad(123, "a"));
  check("budget: undefined after fails closed", bad("a", undefined));
  check("budget: null fails closed", bad(null, null));
  check("budget: over 1 MiB (ASCII) fails closed", bad("a", "a".repeat(HARNESS_MAX_INPUT_BYTES + 1)));
  check("budget: over 1 MiB in bytes (multibyte, fewer chars) fails closed", bad("a", "あ".repeat(400000)));
  check("budget: exactly 1 MiB is accepted as input", validateNetTokenBudget("a", "a".repeat(HARNESS_MAX_INPUT_BYTES)).error === undefined);
  check("budget: lone surrogate fails closed", bad("a", String.fromCharCode(0xd800)));
  const c6 = evaluateTargetBudget("agent/skills/x/SKILL.md", "abcd", "abcde");
  check("target budget: always-loaded C6 growth is not accepted", c6.component === "C6" && c6.enforced && !c6.accepted && c6.reason === "net_token_budget");
  const c1 = evaluateTargetBudget("agent/harnesses/pi/SYSTEM.md", "abcd", "abcd");
  check("target budget: always-loaded C1 delta 0 accepted", c1.enforced && c1.accepted && c1.reason === undefined);
  const c8 = evaluateTargetBudget("agent/harnesses/pi/extensions/x.ts", "abcd", "abcdefgh");
  check("target budget: on-demand C8 growth is not enforced", c8.component === "C8" && !c8.enforced && c8.accepted);
  const c3 = evaluateTargetBudget("agent/context/library/EXPERIENCE.md", "", "abcdefgh");
  check("target budget: C3 growth is not enforced", !c3.enforced && c3.accepted);
  const un = evaluateTargetBudget("README.md", "abcd", "abcd");
  check("target budget: unclassified target is rejected (unclassified_target)", !un.accepted && un.reason === "unclassified_target" && un.component === null && !un.enforced);
  const inv1 = evaluateTargetBudget("agent/rules/x.md", 1 as any, "a");
  check("target budget: invalid input is never accepted (enforced target)", !inv1.accepted && inv1.reason === "invalid_input" && Number.isNaN(inv1.delta));
  const inv2 = evaluateTargetBudget("agent/scripts/x.py", 1 as any, "a");
  check("target budget: invalid input is never accepted (unenforced target)", !inv2.accepted && inv2.reason === "invalid_input");
  check("always-loaded set is exactly C1,C2,C4,C6", [...ALWAYS_LOADED_COMPONENTS].sort().join(",") === "C1,C2,C4,C6");

  // --------------------------------------------------------------------------
  // Test 7: Harness² detection patterns
  // --------------------------------------------------------------------------
  const use = (tool: string, extra: any = {}) => ({ type: "tool_use", tool, ...extra });
  const bash = (command: string, extra: any = {}) => use("bash", { params: { command }, ...extra });
  const misses = (events: any[], cfg: SolPiConfig = DEFAULT_CONFIG) => detectActionFusionMisses(events, cfg);
  check("action_fusion_miss: edit,edit -> 1", misses([use("edit"), use("edit")]) === 1);
  check("action_fusion_miss: write,write,write is one unvalidated batch -> 1", misses([use("write"), use("write"), use("write")]) === 1);
  check("action_fusion_miss: single edit -> 0", misses([use("edit"), use("read")]) === 0);
  check("action_fusion_miss: edit,bash(go test),edit -> 0", misses([use("edit"), bash("go test ./..."), use("edit")]) === 0);
  check("action_fusion_miss: batch of edits then one build -> 0", misses([use("edit"), use("edit"), use("write"), bash("make test")]) === 0);
  check("action_fusion_miss: edit,read,edit -> 1", misses([use("edit"), use("read"), use("edit")]) === 1);
  check("action_fusion_miss: edit,bash(ls),edit -> 1", misses([use("edit"), bash("ls"), use("edit")]) === 1);
  check("action_fusion_miss: validator output on the edits -> 0", misses([use("edit", { validator: { ok: true } }), use("edit", { validator: "ok" })]) === 0);
  check(
    "action_fusion_miss: validator output on a later event clears the run",
    misses([use("edit"), { type: "tool_result", tool: "edit", validator: { ok: true } }, use("edit")]) === 0,
  );
  check("action_fusion_miss: tool_result events are not edits", misses([use("edit"), { type: "tool_result", tool: "edit" }, { type: "tool_result", tool: "edit" }]) === 0);
  check("action_fusion_miss: ast_edit counts as edit", misses([use("ast_edit"), use("edit")]) === 1);
  check("action_fusion_miss: turn boundary closes a run (two unvalidated batches -> 2)", misses([use("edit"), use("edit"), { type: "turn" }, use("edit"), use("edit")]) === 2);
  check("action_fusion_miss: turn_end boundary closes a run", misses([use("edit"), use("edit"), { type: "turn_end" }]) === 1);
  check("action_fusion_miss: a lone edit per turn never counts", misses([use("edit"), { type: "turn" }, use("edit"), { type: "turn" }]) === 0);
  for (const validator of [
    "bash -n x.sh", "python3 -I -m py_compile x.py", "python3 -m py_compile x.py", "python3 -m json.tool x.json",
    "nix-instantiate --parse x.nix", "go vet ./...", "go vet ./pkg/...", "cargo check --quiet", "FOO=1 bash -n x.sh", "cd d && bash -n x.sh", "sudo bash -n x.sh",
    "/usr/bin/bash -n x.sh",
  ]) {
    check(`action_fusion_miss: validator command clears the run: ${validator}`, misses([use("edit"), use("edit"), bash(validator)]) === 0);
  }
  for (const notValidator of ["bash x.sh", "python3 x.py", "ls", "echo bash -n", "cat x.sh", "python3 -m http.server"]) {
    check(`action_fusion_miss: not a validator: ${notValidator}`, misses([use("edit"), use("edit"), bash(notValidator)]) === 1);
  }
  const customVal: SolPiConfig = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  customVal.actionFusionConfig.defaultValidators[".zz"] = "mycheck --strict";
  check(
    "action_fusion_miss: validators come from the sol-pi config (custom entry)",
    misses([use("edit"), use("edit"), bash("mycheck --strict f.zz")], customVal) === 0 && misses([use("edit"), use("edit"), bash("mycheck --strict f.zz")]) === 1,
  );
  const customPath: SolPiConfig = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  customPath.actionFusionConfig.defaultValidators[".zz"] = "mycheck --strict ./...";
  check("action_fusion_miss: trailing path-like args of a validator entry are ignored", misses([use("edit"), use("edit"), bash("mycheck --strict ./sub/...")], customPath) === 0);
  check(
    "action_fusion_miss: a call logged as tool_call and tool_use with the same id counts once",
    misses([use("edit", { id: "c1" }), { type: "tool_call", tool: "edit", id: "c1" }]) === 0,
  );
  check(
    "action_fusion_miss: duplicate without ids (same tool+args back to back, different type) counts once",
    misses([use("edit", { params: { path: "a" } }), { type: "tool_call", tool: "edit", params: { path: "a" } }]) === 0,
  );
  check(
    "action_fusion_miss: same type twice is two calls",
    misses([use("edit", { params: { path: "a" } }), use("edit", { params: { path: "a" } })]) === 1,
  );
  check("action_fusion_miss: different ids are different calls", misses([use("edit", { id: "c1" }), use("edit", { id: "c2" })]) === 1);

  const HAIKU = "anthropic/claude-haiku-5-5";
  const tok = (model: string, n: any) => ({ type: "turn", model, inputTokens: n });
  const cross = (events: any[], cfg: SolPiConfig = DEFAULT_CONFIG) => detectPricingCliffCrossings(events, cfg);
  const c1x = cross([tok(HAIKU, 50000), tok(HAIKU, 95000)]);
  check("pricing_cliff_crossed: 50K -> 95K crosses the 90K cliff", c1x.length === 1 && c1x[0].cliff === 90000 && c1x[0].from === 50000 && c1x[0].to === 95000 && c1x[0].model === HAIKU);
  check("pricing_cliff_crossed: staying below -> 0", cross([tok(HAIKU, 50000), tok(HAIKU, 60000)]).length === 0);
  check("pricing_cliff_crossed: first observation already above the cliff is not a crossing", cross([tok(HAIKU, 95000)]).length === 0);
  check("pricing_cliff_crossed: staying above after the first observation -> 0", cross([tok(HAIKU, 95000), tok(HAIKU, 96000)]).length === 0);
  check("pricing_cliff_crossed: re-crossing after compaction counts again", cross([tok(HAIKU, 50000), tok(HAIKU, 95000), tok(HAIKU, 40000), tok(HAIKU, 95000)]).length === 2);
  check("pricing_cliff_crossed: models are tracked independently", cross([tok(HAIKU, 50000), tok("other/x", 50000), tok(HAIKU, 95000), tok("other/x", 95000)]).length === 1);
  check("pricing_cliff_crossed: unknown model uses the token-pressure threshold", cross([tok("other/x", 170000), tok("other/x", 190000)]).length === 1);
  const cacheEv = (u: any) => ({ model: HAIKU, usage: u });
  const cc = cross([cacheEv({ input_tokens: 1000 }), cacheEv({ input_tokens: 1000, cache_read_input_tokens: 60000, cache_creation_input_tokens: 40000 })]);
  check("pricing_cliff_crossed: snake_case cache read/write tokens are summed", cc.length === 1 && cc[0].to === 101000, JSON.stringify(cc));
  const cc2 = cross([cacheEv({ inputTokens: 1000 }), cacheEv({ inputTokens: 1000, cacheReadInputTokens: 60000, cacheWriteTokens: 40000 })]);
  check("pricing_cliff_crossed: camelCase cache tokens are summed", cc2.length === 1 && cc2[0].to === 101000);
  const cc3 = cross([{ message: { model: HAIKU, usage: { input_tokens: 1000 } } }, { message: { model: HAIKU, usage: { input_tokens: 95000 } } }]);
  check("pricing_cliff_crossed: {message:{model,usage}} events are read", cc3.length === 1 && cc3[0].model === HAIKU);
  check("pricing_cliff_crossed: contextTokens is read", cross([{ model: HAIKU, contextTokens: 10 }, { model: HAIKU, contextTokens: 95000 }]).length === 1);
  for (const invalid of [-1, Number.NaN, "95000", Infinity, null]) {
    check(`pricing_cliff_crossed: invalid token value ${String(invalid)} is ignored`, cross([tok(HAIKU, 50000), tok(HAIKU, invalid)]).length === 0);
  }
  check("pricing_cliff_crossed: an invalid cache value invalidates the event", cross([cacheEv({ input_tokens: 1000 }), cacheEv({ input_tokens: 95000, cache_read_input_tokens: "x" })]).length === 0);
  const lowCliff: SolPiConfig = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  lowCliff.onlineContextCompactConfig.respectPricingCliffs = false;
  lowCliff.onlineContextCompactConfig.tokenPressureThreshold = 1000;
  check("pricing_cliff_crossed: cliff value comes from sol-pi-core (catalog compaction_threshold, else default threshold)", cross([tok(HAIKU, 500), tok(HAIKU, 5000)], lowCliff).length === 1 && cross([tok(HAIKU, 500), tok(HAIKU, 5000)]).length === 0);
  setPricingCliffCatalog({ models: { [HAIKU]: { model_id: "claude-haiku-5-5", compaction_threshold: 1000 } } });
  check("pricing_cliff_crossed: a catalog compaction_threshold change is honoured (single source)", cross([tok(HAIKU, 500), tok(HAIKU, 5000)]).length === 1);
  setPricingCliffCatalog(undefined);
  const offCfg: SolPiConfig = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  offCfg.pricingCliffAdvisoryConfig.enabled = false;
  check("pricing_cliff_crossed: pricingCliffAdvisoryConfig.enabled=false disables detection", cross([tok(HAIKU, 50000), tok(HAIKU, 95000)], offCfg).length === 0);
  const killCfg: SolPiConfig = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  killCfg.onlineContextCompactConfig.enabled = false; // shipped sol-pi.json state (onlineContextCompact kill switch)
  check("pricing_cliff_crossed: the onlineContextCompact kill switch does not disable detection", cross([tok(HAIKU, 50000), tok(HAIKU, 95000)], killCfg).length === 1);

  check("evidence_quote_mismatch: substring quote -> 0", countEvidenceQuoteMismatches([{ quotes: ["a b"], rawLog: "xx a b yy" }]) === 0);
  check("evidence_quote_mismatch: fabricated quote -> 1", countEvidenceQuoteMismatches([{ quotes: ["zzz"], rawLog: "xx a b yy" }]) === 1);
  check("evidence_quote_mismatch: blank quote -> 1", countEvidenceQuoteMismatches([{ quotes: ["  "], rawLog: "xx   yy" }]) === 1);
  check("evidence_quote_mismatch: non-string quote -> 1", countEvidenceQuoteMismatches([{ quotes: [1], rawLog: "1" }]) === 1);
  check("evidence_quote_mismatch: events without quotes/rawLog are ignored", countEvidenceQuoteMismatches([{ quotes: ["a"] }, { rawLog: "a" }, {}]) === 0);
  check("evidence_quote_mismatch: counts per violating event", countEvidenceQuoteMismatches([{ quotes: ["a"], rawLog: "a" }, { quotes: ["b"], rawLog: "a" }]) === 1);

  // Integration: the patterns surface as FailureSignatures through scanSessionErrors
  const harnessDir = path.join(tempDir, "harness-sessions");
  fs.mkdirSync(harnessDir, { recursive: true });
  fs.writeFileSync(
    path.join(harnessDir, "s.jsonl"),
    [use("edit"), use("edit"), tok(HAIKU, 50000), tok(HAIKU, 95000), { type: "reduce", quotes: ["fabricated"], rawLog: "real log" }]
      .map((e) => JSON.stringify(e))
      .join("\n"),
    "utf-8",
  );
  const hsigs = scanSessionErrors(harnessDir, 7, DEFAULT_CONFIG);
  const hsig = (id: string) => hsigs.find((s) => s.signatureId === id);
  check("scan: action_fusion_miss signature", hsig("action_fusion_miss:edit_without_validation")?.category === "action_fusion_miss" && hsig("action_fusion_miss:edit_without_validation")?.occurrences === 1);
  check("scan: pricing_cliff_crossed signature carries the model", hsig(`pricing_cliff_crossed:${HAIKU}`)?.model === HAIKU);
  check("scan: evidence_quote_mismatch signature", hsig("evidence_quote_mismatch:reducer")?.category === "evidence_quote_mismatch");
  const brokenCfg: SolPiConfig = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  (brokenCfg as any).pricingCliffAdvisoryConfig = null;
  const origErr = console.error;
  const logged: string[] = [];
  console.error = (...a: any[]) => void logged.push(a.join(" "));
  let brokenSigs: FailureSignature[] = [];
  let brokenThrew = false;
  try {
    brokenSigs = scanSessionErrors(harnessDir, 7, brokenCfg);
  } catch {
    brokenThrew = true;
  } finally {
    console.error = origErr;
  }
  check("scan: a malformed advisory config section does not break the scan", !brokenThrew && brokenSigs.some((s) => s.category === "evidence_quote_mismatch"));
  check("scan: the broken detector is reported, the others still run", logged.some((m) => m.includes("pricing_cliff_crossed")) && brokenSigs.some((s) => s.category === "action_fusion_miss") && !brokenSigs.some((s) => s.category === "pricing_cliff_crossed"));

  // --------------------------------------------------------------------------
  // Test 8: bounded file reads for the net-budget tool (each case runs in a child process with a timeout)
  // --------------------------------------------------------------------------
  const rdir = fs.realpathSync(fs.mkdtempSync(path.join(tempDir, "reader-")));
  const outside = path.join(tempDir, "escape.md");
  fs.writeFileSync(outside, "outside");
  fs.writeFileSync(path.join(rdir, "ok.md"), "hello");
  fs.writeFileSync(path.join(rdir, "exact.md"), "a".repeat(HARNESS_MAX_INPUT_BYTES));
  fs.writeFileSync(path.join(rdir, "big.md"), "a".repeat(HARNESS_MAX_INPUT_BYTES + 1));
  fs.writeFileSync(path.join(rdir, "bad.md"), Buffer.from([0x61, 0xff, 0xfe]));
  fs.writeFileSync(path.join(rdir, "bom.md"), Buffer.from([0xef, 0xbb, 0xbf, 0x61]));
  fs.mkdirSync(path.join(rdir, "dir"));
  const mkfifo = spawnSync("mkfifo", [path.join(rdir, "fifo.md")]);
  check("reader setup: mkfifo", mkfifo.status === 0, String(mkfifo.stderr));
  fs.symlinkSync("/dev/zero", path.join(rdir, "zero.md"));
  fs.symlinkSync("/etc/passwd", path.join(rdir, "passwd.md"));
  fs.symlinkSync("ok.md", path.join(rdir, "link-ok.md"));
  fs.symlinkSync("fifo.md", path.join(rdir, "link-fifo.md"));
  fs.symlinkSync(path.join("..", "escape.md"), path.join(rdir, "link-escape.md"));
  const corePath = path.join(__dirname, "continual-harness-core.ts");
  const READER = `
const m = await import(process.env.CORE_PATH);
try {
  const t = m.readHarnessTextFile(process.env.ROOT, process.env.P);
  console.log(JSON.stringify({ ok: true, len: t.length }));
} catch (e) {
  console.log(JSON.stringify({ ok: false, msg: String(e && e.message) }));
}
`;
  const readIn = (p: string) => {
    const r = spawnSync(process.execPath, ["-e", READER], { env: { ...process.env, CORE_PATH: corePath, ROOT: rdir, P: p }, timeout: 10000, encoding: "utf-8" });
    if (r.error || r.signal) return { ok: false, msg: `HUNG/KILLED ${r.error?.message ?? r.signal}`, hung: true } as any;
    try {
      return JSON.parse(r.stdout.trim().split("\n").pop()!);
    } catch {
      return { ok: false, msg: `bad child output: ${r.stdout} ${r.stderr}`, hung: false } as any;
    }
  };
  const rejects = (name: string, p: string, re: RegExp) => {
    const r = readIn(p);
    check(`reader: ${name}`, r.ok === false && !r.hung && re.test(r.msg), JSON.stringify(r));
  };
  const accepts = (name: string, p: string, len: number) => {
    const r = readIn(p);
    check(`reader: ${name}`, r.ok === true && r.len === len, JSON.stringify(r));
  };
  accepts("regular file inside the repo", "ok.md", 5);
  accepts("absolute path inside the repo", path.join(rdir, "ok.md"), 5);
  accepts("symlink to a file inside the repo", "link-ok.md", 5);
  accepts("exactly 1 MiB", "exact.md", HARNESS_MAX_INPUT_BYTES);
  accepts("UTF-8 BOM is kept like Python's decode", "bom.md", 2);
  rejects("1 MiB + 1 byte", "big.md", /exceeds/);
  rejects("FIFO does not hang", "fifo.md", /not a regular file/);
  rejects("symlink to a FIFO does not hang", "link-fifo.md", /not a regular file/);
  rejects("symlink to /dev/zero (outside) does not hang", "zero.md", /outside the repository/);
  rejects("symlink to /etc/passwd (outside)", "passwd.md", /outside the repository/);
  rejects("symlink escaping with ..", "link-escape.md", /outside the repository/);
  rejects("'..' path to an existing outside file", "../escape.md", /outside the repository/);
  rejects("absolute path outside the repo", outside, /outside the repository/);
  rejects("/etc/passwd", "/etc/passwd", /outside the repository/);
  rejects("/proc/self/maps", "/proc/self/maps", /outside the repository/);
  rejects("directory", "dir", /not a regular file/);
  rejects("invalid UTF-8", "bad.md", /UTF-8/);
  rejects("missing file", "missing.md", /ENOENT|no such file/i);
  check("reader: NUL in path is rejected before touching the filesystem", throws(() => readHarnessTextFile(rdir, "ok.md\0x")));
  rejects("empty path", "", /invalid file path/);
  const growPath = path.join(rdir, "grow.bin");
  fs.writeFileSync(growPath, Buffer.alloc(HARNESS_MAX_INPUT_BYTES + 5, 0x61));
  const gfd = fs.openSync(growPath, "r");
  let growMsg = "";
  try {
    readFdBounded(gfd);
  } catch (e: any) {
    growMsg = e.message;
  } finally {
    fs.closeSync(gfd);
  }
  check("reader: a file that is larger than its fstat size stops at the cap", /exceeds/.test(growMsg), growMsg);
  const sfd = fs.openSync(path.join(rdir, "exact.md"), "r");
  let smallMsg = "";
  try {
    readFdBounded(sfd, 10);
  } catch (e: any) {
    smallMsg = e.message;
  } finally {
    fs.closeSync(sfd);
  }
  check("reader: readFdBounded honours a smaller cap", /exceeds 10 bytes/.test(smallMsg), smallMsg);

  // --------------------------------------------------------------------------
  // Test 9: parity with agent/scripts/evolve/harness2-offline.py (same inputs through both)
  // --------------------------------------------------------------------------
  const repoRoot = path.resolve(__dirname, "..", "..", "..", "..", "..");
  const PY_PARITY = `
import importlib.util, json, sys, tempfile
from pathlib import Path
sys.stdin.reconfigure(encoding="utf-8")
root = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("h2", root / "agent/scripts/evolve/harness2-offline.py")
m = importlib.util.module_from_spec(spec)
sys.modules["h2"] = m
spec.loader.exec_module(m)
d = json.load(sys.stdin)
keys = ("signature", "count", "tasks", "scope", "target", "component", "status", "reason", "manifests")

def load_traces(rows):
    out = []
    for t in rows:
        where = "trace"
        out.append({"signature": m.norm_sig(m.req_str(t, "signature", where, 200)), "task": m.req_str(t, "task", where, 200),
                    "target": m.check_target(m.req_str(t, "target", where, m.MAX_TARGET_CHARS), where),
                    "message": "", "manifest": m.parse_manifest(t, where)})
    return out

def py_rejects(rows):
    try:
        load_traces(rows)
        return False
    except m.Fail:
        return True

out = {
    "components": [m.classify(t) for t in d["targets"]],
    "tokens": [m.est_tokens(t) for t in d["texts"]],
    "clusters": [{k: c[k] for k in keys} for c in m.cluster_traces(load_traces(d["traces"]), d["min_occ"])],
    "unsafe": [m.has_unsafe(s) for s in d["unsafe"]],
    "target_ok": [not py_rejects([{"signature": "s", "task": "t", "target": t}]) for t in d["target_cases"]],
    "trace_reject": [py_rejects([r]) for r in d["bad_traces"]],
    "budget": [],
}
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    for i, c in enumerate(d["budget"]):
        tgt = "c%d/%s" % (i, c["target"])
        if c["before"] is not None:
            p = base / tgt
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(c["before"], encoding="utf-8")
        cand = {"id": "c%d" % i, "signature": "s", "target": tgt, "new_text": c["after"],
                "probes": [{"name": "p", "before": False, "after": True}]}
        r = m.evaluate(cand, {"s": {"scope": "INV"}}, base, "0", lambda _c: None)
        out["budget"].append({"delta": r["delta_tokens"], "reasons": r["reasons"]})
print(json.dumps(out))
`;
  const TEXTS = ["", "a", "abcd", "abcde", "あ", "あい", "あいうえお", "😀", "x".repeat(4097), "line1\nline2\n\ttab"];
  const BUDGET_CASES: Array<{ target: string; before: string | null; after: string }> = [
    { target: "agent/harnesses/pi/SYSTEM.md", before: "abcd", after: "abcde" },
    { target: "agent/harnesses/pi/SYSTEM.md", before: "abcd", after: "wxyz" },
    { target: "agent/rules/x.md", before: "abcdefgh", after: "あいうえお" },
    { target: "agent/rules/x.md", before: "abcdefghijkl", after: "あいうえ" },
    { target: "agent/rules/x.md", before: null, after: "new rule" },
    { target: "CLAUDE.md", before: "abcd", after: "abcdefgh" },
    { target: "agent/context/library/EXPERIENCE.md", before: "abcd", after: "abcdefghijklmnop" },
    { target: "agent/agents/x.md", before: "abcd", after: "abcdefghijklmnop" },
    { target: "agent/scripts/x.py", before: "abcd", after: "abcdefghijklmnop" },
    { target: "agent/harnesses/pi/extensions/x.ts", before: "abcd", after: "abcdefghijklmnop" },
    { target: "agent/harnesses/pi/extensions/x.ts", before: "abcdefgh", after: "abcd" },
    { target: "README.md", before: "abcd", after: "abcd" },
    { target: "README.md", before: "abcd", after: "abcdefghijklmnop" },
    { target: "agent/other/x.ts", before: "abcd", after: "abcdefghijklmnop" },
  ];
  const BAD_TRACES = [
    { signature: "s", task: "t", target: "agent/rules/x.md" },
    { signature: "s", task: "t", target: "../x.md" },
    { signature: "s", task: "t", target: "/abs.md" },
    { signature: "s", task: "t", target: "a b.md" },
    { signature: "s", task: "a\nb", target: "x.md" },
    { signature: "   ", task: "t", target: "x.md" },
    { signature: "a" + cp(0x200b), task: "t", target: "x.md" },
    { signature: "a".repeat(200), task: "t", target: "x.md" },
    { signature: "a".repeat(201), task: "t", target: "x.md" },
    { signature: "s", task: "t".repeat(201), target: "x.md" },
    { signature: "s", task: "t", target: "a".repeat(301) },
    { signature: "s", task: "t", target: "x.md", manifest: "x" },
    { signature: "s", task: "t", target: "x.md", manifest: [1] },
    { signature: "s", task: "t", target: "x.md", manifest: ["../x.md"] },
    { signature: "s", task: "t", target: "x.md", manifest: ["a".repeat(301)] },
    { signature: "s", task: "t", target: "x.md", manifest: Array.from({ length: 33 }, () => "x.md") },
    { signature: "s", task: 1, target: "x.md" },
    { signature: "あ".repeat(200), task: "t", target: "x.md" },
    { signature: "あ".repeat(201), task: "t", target: "x.md" },
  ];
  const pyRun = spawnSync("python3", ["-I", "-B", "-c", PY_PARITY, repoRoot], {
    input: JSON.stringify({ targets: COMPONENT_TABLE.map(([t]) => t), texts: TEXTS, traces: TRACES, min_occ: 3, budget: BUDGET_CASES, unsafe: UNSAFE_TABLE, target_cases: [...TARGET_OK, ...TARGET_BAD], bad_traces: BAD_TRACES }),
    encoding: "utf-8",
  });
  check("parity: harness2-offline.py ran", pyRun.status === 0, pyRun.stderr);
  if (pyRun.status === 0) {
    const py = JSON.parse(pyRun.stdout);
    check("parity: C1-C8 classification matches Python", JSON.stringify(COMPONENT_TABLE.map(([t]) => classifyHarnessComponent(t))) === JSON.stringify(py.components));
    check("parity: token estimate matches Python", JSON.stringify(TEXTS.map(estimateHarnessTokens)) === JSON.stringify(py.tokens));
    check("parity: clusters (INV/DOM, component, status, order, target normalization) match Python", JSON.stringify(clusters) === JSON.stringify(py.clusters), `${JSON.stringify(clusters)} vs ${JSON.stringify(py.clusters)}`);
    check("parity: unsafe-character verdicts match Python has_unsafe", JSON.stringify(UNSAFE_TABLE.map(hasUnsafeHarnessChar)) === JSON.stringify(py.unsafe), `${JSON.stringify(UNSAFE_TABLE.map(hasUnsafeHarnessChar))} vs ${JSON.stringify(py.unsafe)}`);
    check(
      "parity: target validation matches Python check_target",
      JSON.stringify([...TARGET_OK, ...TARGET_BAD].map((t) => !throws(() => validateHarnessTarget(t)))) === JSON.stringify(py.target_ok),
    );
    check(
      "parity: trace validation (length, control chars, target, type) matches Python",
      JSON.stringify(BAD_TRACES.map((r) => throws(() => clusterHarnessTraces([r as any])))) === JSON.stringify(py.trace_reject),
      `${JSON.stringify(BAD_TRACES.map((r) => throws(() => clusterHarnessTraces([r as any]))))} vs ${JSON.stringify(py.trace_reject)}`,
    );
    BUDGET_CASES.forEach((c, i) => {
      const v = evaluateTargetBudget(c.target, c.before ?? "", c.after);
      const reasons: string[] = py.budget[i].reasons;
      const pyReason = reasons.includes("unclassified_target") ? "unclassified_target" : reasons.includes("net_token_budget") ? "net_token_budget" : undefined;
      const deltaOk = v.component === null ? py.budget[i].delta === null : v.delta === py.budget[i].delta;
      check(`parity: budget case ${i} (${c.target}) delta+verdict+reason match Python`, deltaOk && v.accepted === (pyReason === undefined) && v.reason === pyReason, `${JSON.stringify(v)} vs ${JSON.stringify(py.budget[i])}`);
    });
  }


  // --------------------------------------------------------------------------
  // Test 10: collect-evidence.sh --traces (JSONL for harness2-offline.py; bad rows are dropped, not fatal)
  // --------------------------------------------------------------------------
  const collectScript = path.join(repoRoot, "agent", "skills", "swarm-evolve", "scripts", "collect-evidence.sh");
  const cHome = fs.mkdtempSync(path.join(tempDir, "collect-home-"));
  const cRepo = fs.mkdtempSync(path.join(tempDir, "collect-repo-"));
  spawnSync("git", ["init", "-q", cRepo]);
  const cLogDir = path.join(cHome, ".claude", "session-data", "swarm");
  fs.mkdirSync(cLogDir, { recursive: true });
  const cLog = path.join(cLogDir, "evolve-log.jsonl");
  const repoName = path.basename(cRepo);
  const nowIso = new Date().toISOString().slice(0, 19) + "Z";
  const day = nowIso.slice(0, 10);
  const row = (o: any) => JSON.stringify({ ts: nowIso, repo: repoName, hook: "h", category: "c", ...o });
  const collectEnv: Record<string, string> = { ...(process.env as Record<string, string>), HOME: cHome };
  delete collectEnv.SWARM_STATE_DIR;
  const runCollect = (...args: string[]) => spawnSync("bash", [collectScript, cRepo, "30", "--traces", ...args], { env: collectEnv, encoding: "utf-8", timeout: 60000 });
  fs.writeFileSync(
    cLog,
    [
      row({}),
      row({ hook: "ok2" }),
      "{broken json",
      "[1,2]",
      "42",
      row({ ts: 12345 }),
      row({ hook: null }),
      row({ category: ["x"] }),
      row({ hook: "a" + cp(0x200b) + "b" }),
      row({ hook: "a" + cp(0xa0) + "b" }),
      row({ hook: "a" + cp(0x2028) + "b" }),
      row({ hook: "a" + cp(1) + "b" }),
      row({ hook: "a\tb" }),
      row({ hook: "a" + "x".repeat(250) }),
      row({ hook: "a" + cp(0xfe0f) }),
      row({ hook: "あいう", category: "漢字" }),
      row({ repo: "other" }),
      row({ ts: "2000-01-01T00:00:00Z" }),
      row({ ts: "short" }),
    ].join("\n") + "\n",
  );
  const tgt = "agent/skills/swarm-evolve/SKILL.md";
  const cr = runCollect(tgt);
  check("collect --traces: exit 0 despite broken/odd rows", cr.status === 0, String(cr.stderr));
  const crRows = cr.stdout.split("\n").filter(Boolean).map((l) => JSON.parse(l));
  check(
    "collect --traces: only valid rows survive, in trace format",
    JSON.stringify(crRows.map((r) => r.signature)) === JSON.stringify(["h:c", "ok2:c", "あいう:漢字"]) &&
      crRows.every((r) => r.task === day && r.target === tgt && typeof r.message === "string"),
    cr.stdout,
  );
  const PY_LOAD = `
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("h2", Path(sys.argv[1]) / "agent/scripts/evolve/harness2-offline.py")
m = importlib.util.module_from_spec(spec)
sys.modules["h2"] = m
spec.loader.exec_module(m)
rows, _ = m.load_traces(Path(sys.argv[2]))
print(len(rows))
`;
  const pyLoad = (file: string) => spawnSync("python3", ["-I", "-B", "-c", PY_LOAD, repoRoot, file], { encoding: "utf-8" });
  const trFile = path.join(tempDir, "collected.jsonl");
  fs.writeFileSync(trFile, cr.stdout);
  const pl = pyLoad(trFile);
  check("collect --traces: harness2-offline.py accepts the whole output", pl.status === 0 && pl.stdout.trim() === "3", String(pl.stderr));
  for (const bad of ["", "/abs.md", "a/../b.md", "a b.md", "a;b.md", "a".repeat(301)]) {
    const r = runCollect(bad);
    check(`collect --traces: bad target ${JSON.stringify(bad).slice(0, 24)} -> exit 2, no output`, r.status === 2 && r.stdout === "", `${r.status} ${r.stdout}`);
  }
  const rMissing = spawnSync("bash", [collectScript, cRepo, "30", "--traces"], { env: collectEnv, encoding: "utf-8" });
  check("collect --traces: missing target -> exit 2", rMissing.status === 2);
  fs.writeFileSync(cLog, Array.from({ length: 10500 }, (_, i) => row({ hook: `h${i % 7}` })).join("\n") + "\n");
  const capped = runCollect("x.md");
  check("collect --traces: output is capped at 10000 rows", capped.status === 0 && capped.stdout.split("\n").filter(Boolean).length === 10000);
  fs.writeFileSync(trFile, capped.stdout);
  const pl2 = pyLoad(trFile);
  check("collect --traces: the capped output is accepted by harness2-offline.py", pl2.status === 0 && pl2.stdout.trim() === "10000", String(pl2.stderr));
  fs.rmSync(cLog);
  const noLog = runCollect("x.md");
  check("collect --traces: no log -> empty output, exit 0", noLog.status === 0 && noLog.stdout === "");

} finally {
  // Clean up temporary directory
  try {
    fs.rmSync(tempDir, { recursive: true, force: true });
  } catch {
    // ignore
  }
}

// --------------------------------------------------------------------------
// Real OMP session layout and entry shape (@earendil-works/pi-coding-agent 19.0.1):
// sessions/<encoded-cwd>/<timestamp>_<id>.jsonl, entries {type:"message", message:{role, model, usage:{input,cacheRead,cacheWrite}, content:[toolCall blocks]}}
// --------------------------------------------------------------------------
{
  const HAIKU = "anthropic/claude-haiku-5-5";
  // The shared tempDir is already removed at this point, so this block owns its scratch dir.
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "ch-real-"));
  process.on("exit", () => fs.rmSync(tempDir, { recursive: true, force: true }));
  const root = fs.mkdtempSync(path.join(tempDir, "real-sessions-"));
  const proj = path.join(root, "--home-user-repo--");
  fs.mkdirSync(path.join(proj, "20261120T000000_abc"), { recursive: true });
  const call = (id: string, name: string, args: object) => ({ type: "toolCall", id, name, arguments: args });
  const asst = (content: object[], input: number) => ({ type: "message", message: { role: "assistant", model: HAIKU, usage: { input, output: 10, cacheRead: 0, cacheWrite: 0 }, content } });
  const lines = [
    { type: "message", message: { role: "user", content: "go" } },
    asst([call("c1", "edit", { path: "a.ts" }), call("c2", "write", { path: "b.ts" })], 1000),
    { type: "message", message: { role: "toolResult", toolCallId: "c1", toolName: "edit", isError: false, content: [] } },
    asst([], 95000),
  ];
  fs.writeFileSync(path.join(proj, "20261120T000000_abc.jsonl"), lines.map((l) => JSON.stringify(l)).join("\n") + "\n");
  // sub-agent session one level deeper
  fs.writeFileSync(path.join(proj, "20261120T000000_abc", "sub1.jsonl"), JSON.stringify({ type: "message", message: { role: "user", content: "x" } }) + "\n");
  setPricingCliffCatalog({ models: { [HAIKU]: { model_id: "claude-haiku-5-5", compaction_threshold: 90000 } } });
  const sigs = scanSessionErrors(root, 7, JSON.parse(JSON.stringify(DEFAULT_CONFIG)));
  setPricingCliffCatalog(undefined);
  const ids = sigs.map((s) => s.signatureId);
  check("real OMP layout: sessions/<cwd>/<ts>_<id>.jsonl is scanned (nested dir)", sigs.length > 0, JSON.stringify(ids));
  check("real OMP entry shape: action_fusion_miss from assistant toolCall blocks", ids.includes("action_fusion_miss:edit_without_validation"), JSON.stringify(ids));
  check("real OMP entry shape: pricing_cliff_crossed from message.usage {input,cacheRead,cacheWrite}", ids.includes(`pricing_cliff_crossed:${HAIKU}`), JSON.stringify(ids));
  // each case in its own sessions root so signatures cannot leak between cases
  const scanOne = (name: string, relFile: string, entries: object[]) => {
    const r = fs.mkdtempSync(path.join(tempDir, `${name}-`));
    const f = path.join(r, relFile);
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, entries.map((l) => JSON.stringify(l)).join("\n") + "\n");
    setPricingCliffCatalog({ models: { [HAIKU]: { model_id: "claude-haiku-5-5", compaction_threshold: 90000 } } });
    try {
      return scanSessionErrors(r, 7, JSON.parse(JSON.stringify(DEFAULT_CONFIG))).map((s) => s.signatureId);
    } finally {
      setPricingCliffCatalog(undefined);
    }
  };
  const user = (text: string) => ({ type: "message", message: { role: "user", content: text } });
  const twoEdits = [asst([call("e1", "edit", { path: "a.ts" }), call("e2", "edit", { path: "b.ts" })], 10)];
  // sub-agent sessions live two directories down: <cwd>/<ts>_<id>/<agentId>.jsonl
  check("real OMP layout: a sub-agent session two levels deep is scanned", scanOne("deep", "proj/20261120T000000_abc/sub1.jsonl", [user("go"), ...twoEdits]).includes("action_fusion_miss:edit_without_validation"));
  // context size = input + cacheRead + cacheWrite
  check("real OMP usage: cacheRead and cacheWrite are summed into the context size", scanOne("cache", "proj/a.jsonl", [
    asst([], 1000),
    { type: "message", message: { role: "assistant", model: HAIKU, usage: { input: 1000, output: 5, cacheRead: 60000, cacheWrite: 30000 }, content: [] } },
  ]).includes(`pricing_cliff_crossed:${HAIKU}`));
  // a user message starts a new turn: one edit per turn is not an unvalidated batch
  check("real OMP turn boundary: one edit in each of two user turns is not an action_fusion_miss", !scanOne("turns", "proj/b.jsonl", [
    user("one"), asst([call("t1", "edit", { path: "a.ts" })], 10),
    user("two"), asst([call("t2", "edit", { path: "b.ts" })], 10),
  ]).includes("action_fusion_miss:edit_without_validation"));
  check("real OMP turn boundary: two edits inside one turn are an action_fusion_miss (control)", scanOne("oneturn", "proj/c.jsonl", [
    user("one"), asst([call("t1", "edit", { path: "a.ts" }), call("t2", "write", { path: "b.ts" })], 10),
  ]).includes("action_fusion_miss:edit_without_validation"));
  // model_usage entries (auxiliary calls) and errored assistant messages (usage 0) are not context-size observations
  check("real OMP entries: a small model_usage entry between two large messages is not a Pricing Cliff crossing", !scanOne("mu", "proj/g.jsonl", [
    asst([], 95000), { type: "model_usage", model: HAIKU, usage: { input: 1000, output: 5 } }, asst([], 96000),
  ]).includes(`pricing_cliff_crossed:${HAIKU}`));
  check("real OMP entries: an errored assistant message with usage 0 does not reset the observed context size", !scanOne("err0", "proj/h.jsonl", [
    asst([], 95000),
    { type: "message", message: { role: "assistant", model: HAIKU, stopReason: "error", errorMessage: "aborted", usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, content: [] } },
    asst([], 96000),
  ]).includes(`pricing_cliff_crossed:${HAIKU}`));
  // conversational text and usage numbers must not look like failures
  const quiet = scanOne("quiet", "proj/d.jsonl", [
    user("please review security-gate and vald-guard, max_tokens, rate limit 429"),
    asst([], 14290),
    { type: "model_usage", model: HAIKU, usage: { input: 14290, output: 42429 } },
  ]);
  check("real OMP entries: token counts and prose do not create rate_limit / hook_rejection signatures", quiet.length === 0, JSON.stringify(quiet));
  check("real OMP entries: a file:line suffix (foo.go:429) in an error is not a rate_limit", !scanOne("fl", "proj/fl.jsonl", [
    { type: "message", message: { role: "toolResult", toolCallId: "x", toolName: "bash", isError: true, content: [{ type: "text", text: "pkg/foo.go:429:7: undefined: bar" }] } },
  ]).some((s) => s.startsWith("rate_limit")));
  check("real OMP entries: a real 429 in an error is still a rate_limit (control)", scanOne("fl2", "proj/fl2.jsonl", [
    { type: "message", message: { role: "toolResult", toolCallId: "x", toolName: "bash", isError: true, content: [{ type: "text", text: "HTTP 429 from the provider" }] } },
  ]).some((s) => s.startsWith("rate_limit")));
  check("real OMP entries: an isError toolResult from the gate is a hook_rejection", scanOne("rej", "proj/e.jsonl", [
    { type: "message", message: { role: "toolResult", toolCallId: "x", toolName: "write", isError: true, content: [{ type: "text", text: "Security Gate blocked write" }] } },
  ]).includes("hook_rejection:pretooluse_hook"));
  check("real OMP entries: an assistant stopReason:error with a 429 is a rate_limit", scanOne("rl", "proj/f.jsonl", [
    { type: "message", message: { role: "assistant", model: HAIKU, stopReason: "error", errorMessage: "429 Too Many Requests", usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 }, content: [] } },
  ]).includes(`rate_limit:${HAIKU}`));
  // a symlinked directory must not be followed
  const outside = fs.mkdtempSync(path.join(tempDir, "outside-"));
  fs.writeFileSync(path.join(outside, "x.jsonl"), JSON.stringify({ error: "hook rejected: security-gate" }) + "\n");
  const root2 = fs.mkdtempSync(path.join(tempDir, "symlink-sessions-"));
  fs.symlinkSync(outside, path.join(root2, "linked"));
  check("real OMP layout: a symlinked directory is not followed", scanSessionErrors(root2, 7).length === 0);

  // --------------------------------------------------------------------------
  // Harness² 2-consecutive-regression auto-rollback (pi-agent-improvement.pdf #21)
  // --------------------------------------------------------------------------
  const rbDir = fs.mkdtempSync(path.join(os.tmpdir(), "ch-rollback-test-"));
  const targetCfg = path.join(rbDir, "sol-pi.json");
  const backupCfg = `${targetCfg}.bak.100`;
  fs.writeFileSync(backupCfg, '{"version":1,"actionFusion":true}\n', "utf-8");
  fs.writeFileSync(targetCfg, '{"version":1,"actionFusion":false}\n', "utf-8");
  const ledgerFile = path.join(rbDir, "refinement-ledger.json");

  const friction = computeSessionFriction([
    { signatureId: "a", category: "tool_error", occurrences: 3, sampleErrorMessage: "x", lastSeen: 1 },
    { signatureId: "b", category: "rate_limit", occurrences: 2, sampleErrorMessage: "y", lastSeen: 1 },
  ]);
  check("computeSessionFriction sums occurrences", friction === 5);

  const rec0: AppliedRefinementRecord = {
    id: "ref-1",
    appliedAt: 100,
    modifiedPath: targetCfg,
    backupPath: backupCfg,
    baselineFriction: 5,
    consecutiveRegressions: 0,
  };
  const step1 = evaluateRegressionStep(rec0, 7, 2);
  check("1st regression increments count to 1 without rollback", step1.regressed && step1.next.consecutiveRegressions === 1 && !step1.shouldRollback);
  const recovered = evaluateRegressionStep(step1.next, 4, 2);
  check("improvement resets consecutiveRegressions to 0", !recovered.regressed && recovered.next.consecutiveRegressions === 0 && !recovered.shouldRollback);
  const r1 = evaluateRegressionStep(recovered.next, 6, 2);
  const r2 = evaluateRegressionStep(r1.next, 8, 2);
  check("2nd consecutive regression triggers rollback", r2.next.consecutiveRegressions === 2 && r2.shouldRollback);

  const rbRes = rollbackRefinementFromBackup(r2.next);
  check("rollbackRefinementFromBackup restores original backup", rbRes.success && fs.readFileSync(targetCfg, "utf-8").includes('"actionFusion":true'));

  saveRefinementLedger([{ ...r2.next, rolledBackAt: Date.now() }], ledgerFile);
  const reloadedLedger = loadRefinementLedger(ledgerFile);
  check("refinement ledger round-trips cleanly", reloadedLedger.length === 1 && Boolean(reloadedLedger[0].rolledBackAt));
  fs.rmSync(rbDir, { recursive: true, force: true });
}

// --------------------------------------------------------------------------
// Summary
// --------------------------------------------------------------------------
console.log(`\ncontinual-harness-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
