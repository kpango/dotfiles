/**
 * Tests for Continual Harness Refinement Core Library
 *
 * Verifies session error scanning, failure signature aggregation,
 * proposal generation, syntax validation, and safe proposal application.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  scanSessionErrors,
  generateRefinements,
  validateProposalSyntax,
  applyProposal,
  type FailureSignature,
} from "./continual-harness-core";

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
    JSON.stringify({ type: "turn", model: "anthropic/claude-sonnet-5", error: "429 Too Many Requests: rate_limit_exceeded" }),
    JSON.stringify({ type: "turn", model: "anthropic/claude-sonnet-5", error: "rate limit reached on provider anthropic" }),
    JSON.stringify({ type: "error", model: "anthropic/claude-sonnet-5", error: "token_exhaustion: context window maximum context length exceeded" }),
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
  check("Rate limit identified model anthropic/claude-sonnet-5", rateLimitSig?.model === "anthropic/claude-sonnet-5");

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
        model: "anthropic/claude-sonnet-5",
        effort: "high",
        fallbacks: [
          { provider: "anthropic", model: "anthropic/claude-sonnet-4-6", effort: "high", trigger: "rate_limit" },
        ],
      },
      Low: {
        provider: "antigravity",
        model: "antigravity/gemini-3.8-flash-low",
        effort: "low",
        fallbacks: [],
      },
    },
  };

  const mockSettings = {
    defaultProvider: "anthropic",
    defaultModel: "anthropic/claude-sonnet-5",
    defaultThinkingLevel: "high",
    modelThinkingLevels: {
      "anthropic/claude-sonnet-5": "high",
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

  // Check token exhaustion refinement in settings.json
  const tokenProp = proposals.find((p) => p.diffType === "thinking_budget");
  check("Token budget proposal generated", Boolean(tokenProp));
  check(
    "Token proposal lowers model thinking level to medium",
    tokenProp?.proposedPatch.modelThinkingLevels["anthropic/claude-sonnet-5"] === "medium"
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

  const settingsFile = path.join(configDir, "settings.json");
  fs.writeFileSync(settingsFile, JSON.stringify(mockSettings, null, 2), "utf-8");

  const applyRes = applyProposal(repoMockRoot, tokenProp!);
  check("applyProposal succeeds", applyRes.success === true);
  check("applyProposal returns modifiedPath", applyRes.modifiedPath === settingsFile);
  check("applyProposal created backup file", Boolean(applyRes.backupPath && fs.existsSync(applyRes.backupPath)));

  // Verify backup contains original settings
  const backupContent = fs.readFileSync(applyRes.backupPath!, "utf-8");
  const backupObj = JSON.parse(backupContent);
  check("Backup retains original high thinking level", backupObj.modelThinkingLevels["anthropic/claude-sonnet-5"] === "high");

  // Verify modified file contains applied patch
  const modifiedContent = fs.readFileSync(settingsFile, "utf-8");
  const modifiedObj = JSON.parse(modifiedContent);
  check("Applied file has updated medium thinking level", modifiedObj.modelThinkingLevels["anthropic/claude-sonnet-5"] === "medium");

} finally {
  // Clean up temporary directory
  try {
    fs.rmSync(tempDir, { recursive: true, force: true });
  } catch {
    // ignore
  }
}

// --------------------------------------------------------------------------
// Summary
// --------------------------------------------------------------------------
console.log(`\ncontinual-harness-core: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
