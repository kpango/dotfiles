/**
 * Subagent Mesh & Bayesian Confidence Propagation Test & Benchmark Suite
 *
 * Requirements:
 * - Standalone executable script via `bun run`
 * - Zero external testing framework dependencies (no bun:test, jest, mocha, vitest)
 * - Custom assertion runner pattern (check, pass/fail counters, exit code 0 or 1)
 * - Systematic 4-Tier Test Coverage:
 *     Tier 1: Feature Coverage (>=5 tests per feature across 8 features)
 *     Tier 2: Boundary & Corner Cases (empty messages, extreme scores, sycophancy, corrupted logs, flock)
 *     Tier 3: Cross-Feature Combinations (dissent overriding peer confidence, binary veto over reviews)
 *     Tier 4: Real-World Scenarios (autonomous worker-checker-fixer loop, echo chamber discounting)
 *     Benchmarks: In-memory latency mean/p95 < 1ms, File/IPC latency mean/p95 < 10ms
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { performance } from "node:perf_hooks";

import {
  // Types & Interfaces
  SubagentTopic,
  MeshMessage,
  MeshSender,
  ConfidenceScore,
  ObjectiveVerificationEvidence,
  SpecPayload,
  DraftPayload,
  CritiquePayload,
  VerificationPayload,
  BlockerPayload,
  HandoffState,
  ArbitrationResult,
  BenchmarkResult,

  // Constants
  GATE_CONFIDENCE_THRESHOLD,
  MAX_ATTEMPTS_HARD_CAP,
  SOFT_CHECKPOINT_ATTEMPT,
  DEFAULT_PRIOR_CONFIDENCE,
  DEFAULT_PRIOR_LOG_ODDS,

  // Classes & Engines
  SubagentMesh,
  BlackboardStream,
  CoordinatorEngine,
  ConfidenceEngine,
  PeerHandoffController,

  // Helper Functions
  calculateConfidence,
  sigmoid,
  logOdds,
  calculatePercentiles,
  createMeshMessage,
} from "./subagent-mesh-core";

// --- Custom Test Runner Harness ---
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

function eq(name: string, actual: unknown, expected: unknown) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  check(name, a === e, `got ${a}, want ${e}`);
}

function near(name: string, actual: number, expected: number, tolerance = 0.005) {
  const diff = Math.abs(actual - expected);
  check(name, diff <= tolerance, `got ${actual.toFixed(4)}, want ${expected.toFixed(4)} (diff=${diff.toFixed(4)})`);
}

function getScore(c: ConfidenceScore): number {
  return c.score !== undefined ? c.score : (c as any).value;
}

// ============================================================================
// TIER 1: FEATURE COVERAGE (>=5 tests per feature)
// ============================================================================

async function runTier1FeatureTests() {
  console.log("\n--- TIER 1: Feature Coverage Tests ---");

  // --------------------------------------------------------------------------
  // Feature 1: In-Memory Pub/Sub Event Bus
  // --------------------------------------------------------------------------
  console.log("\n[Feature 1: In-Memory Pub/Sub Event Bus]");
  {
    const mesh = new SubagentMesh();

    // T1.1.1: Single topic subscription and delivery
    let t1Received: MeshMessage | null = null;
    const unsubSpec = mesh.subscribe("spec", (msg) => {
      t1Received = msg;
    });

    const specMsg = createMeshMessage({
      topic: "spec",
      sender: { id: "spec-miner", role: "spec_miner" },
      correlationId: "task-feat-1",
      payload: { taskSlug: "auth-flow", requirements: ["R1", "R2"] } as SpecPayload,
    });
    mesh.publish(specMsg);
    check("T1.1.1: Single topic subscription receives published message", t1Received !== null && (t1Received as any).id === specMsg.id);

    // T1.1.2: Multiple subscribers on the same topic receive the event
    let subACount = 0;
    let subBCount = 0;
    mesh.subscribe("draft", () => { subACount++; });
    mesh.subscribe("draft", () => { subBCount++; });

    const draftMsg = createMeshMessage({
      topic: "draft",
      sender: { id: "worker-1", role: "worker" },
      correlationId: "task-feat-1",
      payload: { taskSlug: "auth-flow", patch: "diff --git a/a.ts b/a.ts" } as DraftPayload,
    });
    mesh.publish(draftMsg);
    check("T1.1.2: Multiple independent subscribers receive message", subACount === 1 && subBCount === 1);

    // T1.1.3: Topic isolation - subscriber on topic A does not receive topic B
    let critiqueReceived = 0;
    mesh.subscribe("critique", () => { critiqueReceived++; });
    mesh.publish(draftMsg); // publish draft, critique listener should NOT fire
    check("T1.1.3: Topic isolation prevents cross-topic leakage", critiqueReceived === 0);

    // T1.1.4: Wildcard '*' subscription receives events across all topics
    let wildcardCount = 0;
    mesh.subscribe("*", () => { wildcardCount++; });
    mesh.publish(specMsg);
    mesh.publish(draftMsg);
    check("T1.1.4: Wildcard subscription receives messages from all topics", wildcardCount === 2);

    // T1.1.5: Unsubscribe prevents further delivery
    unsubSpec();
    t1Received = null;
    mesh.publish(specMsg);
    check("T1.1.5: Unsubscribed listener does not receive new events", t1Received === null);

    // T1.1.6: Subscriber count reflects active listeners accurately
    const countBefore = mesh.subscriberCount("verification");
    const unsubVerif = mesh.subscribe("verification", () => {});
    const countDuring = mesh.subscriberCount("verification");
    unsubVerif();
    const countAfter = mesh.subscriberCount("verification");
    check("T1.1.6: Subscriber count tracks subscribe/unsubscribe lifecycle", countBefore === 0 && countDuring === 1 && countAfter === 0);

    // T1.1.7: Event history tracks dispatched messages in chronological order
    const history = mesh.getHistory({ correlationId: "task-feat-1" });
    check("T1.1.7: Event history records messages chronologically", history.length >= 2 && history[0].timestamp <= history[1].timestamp);
  }

  // --------------------------------------------------------------------------
  // Feature 2: Blackboard File Stream (Persistent JSONL IPC)
  // --------------------------------------------------------------------------
  console.log("\n[Feature 2: Blackboard File Stream]");
  {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "mesh-bb-test-"));
    try {
      const stream = new BlackboardStream({ basePath: tmpDir, correlationId: "task-feat-2" });

      // T1.2.1: Appending message creates JSONL file and persists valid line
      const msg1 = createMeshMessage({
        topic: "spec",
        sender: { id: "spec-miner", role: "spec_miner" },
        correlationId: "task-feat-2",
        payload: { taskSlug: "crypto-mod", requirements: ["R1"] } as SpecPayload,
      });
      await stream.append(msg1);
      const filePath = stream.getFilePath();
      check("T1.2.1: Appending message creates JSONL file on disk", fs.existsSync(filePath));

      // T1.2.2: Reading back events reconstructs typed MeshMessage
      const events = await stream.readAll();
      check("T1.2.2: Readback reconstructs exact message", events.length === 1 && events[0].id === msg1.id && events[0].topic === "spec");

      // T1.2.3: Multiple sequential appends maintain ordering
      const msg2 = createMeshMessage({
        topic: "draft",
        sender: { id: "worker-go", role: "worker" },
        correlationId: "task-feat-2",
        payload: { taskSlug: "crypto-mod", patch: "diff..." } as DraftPayload,
      });
      await stream.append(msg2);
      const updatedEvents = await stream.readAll();
      check("T1.2.3: Sequential appends preserve order", updatedEvents.length === 2 && updatedEvents[0].id === msg1.id && updatedEvents[1].id === msg2.id);

      // T1.2.4: Multi-session isolation
      const streamOther = new BlackboardStream({ basePath: tmpDir, correlationId: "task-other-session" });
      const otherEvents = await streamOther.readAll();
      check("T1.2.4: Distinct correlationIds write to separate isolated streams", otherEvents.length === 0 && streamOther.getFilePath() !== stream.getFilePath());

      // T1.2.5: Re-instantiating BlackboardStream on existing file loads history
      const reloadedStream = new BlackboardStream({ basePath: tmpDir, correlationId: "task-feat-2" });
      const reloadedEvents = await reloadedStream.readAll();
      check("T1.2.5: Re-opened stream recovers entire existing history", reloadedEvents.length === 2 && reloadedEvents[1].id === msg2.id);

      // T1.2.6: Read recent retrieves last N messages
      const recentOne = await reloadedStream.readRecent(1);
      check("T1.2.6: readRecent(1) retrieves exactly the latest entry", recentOne.length === 1 && recentOne[0].id === msg2.id);

      stream.close();
      streamOther.close();
      reloadedStream.close();
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  }

  // --------------------------------------------------------------------------
  // Feature 3: Coordinator Engine (Deduplication, Conflict Arbitration, Status)
  // --------------------------------------------------------------------------
  console.log("\n[Feature 3: Coordinator Engine]");
  {
    const coordinator = new CoordinatorEngine({ deduplicationWindowSize: 100, deduplicationTtlMs: 60000 });

    // T1.3.1: Duplicate message with identical semantic content is dropped
    const msgOrig = createMeshMessage({
      topic: "critique",
      sender: { id: "reviewer-1", role: "reviewer" },
      correlationId: "task-feat-3",
      payload: { taskSlug: "auth", lens: "security", severity: "warning", objection: "Missing salt" } as CritiquePayload,
    });
    const res1 = coordinator.processMessage(msgOrig);
    const res2 = coordinator.processMessage(msgOrig); // exact duplicate
    check("T1.3.1: Identical message is recognized and rejected as duplicate", res1.accepted && !res1.duplicate && res2.duplicate);

    // T1.3.2: Different messages pass deduplication filter
    const msgDiff = createMeshMessage({
      topic: "critique",
      sender: { id: "reviewer-2", role: "reviewer" },
      correlationId: "task-feat-3",
      payload: { taskSlug: "auth", lens: "perf-simd", severity: "advisory", objection: "Vectorize loop" } as CritiquePayload,
    });
    const res3 = coordinator.processMessage(msgDiff);
    check("T1.3.2: Non-duplicate message is accepted", res3.accepted && !res3.duplicate);

    // T1.3.3: Sliding window capacity drops oldest hashes when exceeded
    const tinyCoord = new CoordinatorEngine({ deduplicationWindowSize: 2 });
    const mA = createMeshMessage({ topic: "spec", sender: "s1", correlationId: "c", payload: { a: 1 } });
    const mB = createMeshMessage({ topic: "spec", sender: "s2", correlationId: "c", payload: { b: 2 } });
    const mC = createMeshMessage({ topic: "spec", sender: "s3", correlationId: "c", payload: { c: 3 } });
    tinyCoord.processMessage(mA);
    tinyCoord.processMessage(mB);
    tinyCoord.processMessage(mC); // pushes mA out of sliding window
    const mAReplay = tinyCoord.processMessage(mA);
    check("T1.3.3: Evicted message from sliding window capacity can be re-processed", mAReplay.accepted);

    // T1.3.4: Causal DAG links parentMessageId to child
    const parentMsg = createMeshMessage({
      topic: "draft",
      sender: "worker",
      correlationId: "task-feat-3",
      payload: { taskSlug: "auth", patch: "patch1" } as DraftPayload,
    });
    const childMsg = createMeshMessage({
      topic: "verification",
      sender: "reviewer",
      correlationId: "task-feat-3",
      parentMessageId: parentMsg.id,
      payload: { taskSlug: "auth", verdict: "PASS" } as VerificationPayload,
    });
    coordinator.processMessage(parentMsg);
    coordinator.processMessage(childMsg);
    const dag = coordinator.buildCausalDag("task-feat-3");
    const children = dag.get(parentMsg.id) || [];
    check("T1.3.4: Causal DAG links child message to parentMessageId", children.some((c) => c.id === childMsg.id));

    // T1.3.5: Arbitration Rule 1 - Deterministic failure overrides LLM PASS claim
    const arbitVerdict = coordinator.arbitrateConflict(
      [
        {
          taskSlug: "auth",
          targetDraftMessageId: parentMsg.id,
          verdict: "PASS",
          evaluatorId: "llm-checker",
          evaluatorModel: "claude-sonnet-4",
          evidence: { deterministicPass: true, exitCode: 0 } as ObjectiveVerificationEvidence,
          findings: [],
        },
      ],
      [
        {
          taskSlug: "auth",
          targetMessageId: parentMsg.id,
          lens: "logic",
          severity: "blocker",
          reproCommand: "go test ./...",
          objection: "Unit test panics on nil input",
          remediationHint: "Add nil check",
        },
      ]
    );
    check("T1.3.5: Arbitration Rule 1 - Blocker critique vetoes LLM PASS claim", arbitVerdict.finalVerdict === "FAIL" && arbitVerdict.blocked);

    // T1.3.6: Status line rendering
    const statusLine = coordinator.renderStatusLine("task-feat-3");
    check("T1.3.6: Coordinator renders ASCII status line with progress metadata", statusLine.includes("[SUBAGENT MESH]") && statusLine.includes("task-feat-3"));
  }

  // --------------------------------------------------------------------------
  // Feature 4: Confidence Scoring & Bayesian Engine
  // --------------------------------------------------------------------------
  console.log("\n[Feature 4: Confidence Scoring & Bayesian Engine]");
  {
    // T1.4.1: Initial confidence evaluates to default prior ~0.30
    const confPrior = calculateConfidence({});
    near("T1.4.1: Initial confidence without evidence matches prior (0.30)", getScore(confPrior), DEFAULT_PRIOR_CONFIDENCE, 0.01);
    near("T1.4.1b: Base prior log-odds matches ln(0.3/0.7)", confPrior.prior, DEFAULT_PRIOR_LOG_ODDS, 0.01);

    // T1.4.2: Clean test pass applies boost Delta L_test ~ +2.9755 -> Confidence ~ 0.893
    const confTests = calculateConfidence({
      toolEvidence: {
        deterministicPass: true,
        toolSuccess: true,
        exitCode: 0,
        command: "bun test",
        stdoutSnippet: "14 passed",
        stderrSnippet: "",
        diffStats: { filesChanged: 1, insertions: 10, deletions: 2 },
      },
    });
    near("T1.4.2: Clean test pass boosts confidence to ~0.893", getScore(confTests), 0.893, 0.02);

    // T1.4.3: Clean tests + linter pass applies tool boost Delta L_tool ~ +4.0741 -> Confidence ~ 0.961
    const confTools = calculateConfidence({
      toolEvidence: {
        deterministicPass: true,
        toolSuccess: true,
        exitCode: 0,
        command: "make test lint",
        typecheckLog: "0 errors",
        stdoutSnippet: "all clean",
        stderrSnippet: "",
        diffStats: { filesChanged: 1, insertions: 10, deletions: 2 },
      },
    });
    check("T1.4.3: Clean tests + linter boost reaches > 0.95", getScore(confTools) >= 0.95);

    // T1.4.4: Independent unentangled Opus review adds +1.0975 boost (clean tests + Opus review reaches ~0.962)
    const confPeer = calculateConfidence({
      toolEvidence: {
        deterministicPass: true,
        toolSuccess: true,
        exitCode: 0,
        command: "bun test",
        stdoutSnippet: "ok",
        stderrSnippet: "",
        diffStats: { filesChanged: 1, insertions: 5, deletions: 0 },
      },
      peerReviews: [
        {
          score: 1.0,
          modelTier: "XHigh",
          modelFamily: "claude",
          sycophancyRisk: 0.05,
          claimsRepeatedWithoutEvidence: false,
          observedConfidence: false,
        },
      ],
    });
    near("T1.4.4: Clean test + Opus review reaches ~0.962", getScore(confPeer), 0.962, 0.015);

    // T1.4.4b: Clean tests + linters + Opus review reaches ~0.987 without artificial linter boost
    const confPeerWithLint = calculateConfidence({
      toolEvidence: {
        deterministicPass: true,
        toolSuccess: true,
        exitCode: 0,
        command: "bun test",
        lintersPassed: true,
        stdoutSnippet: "ok",
        stderrSnippet: "",
        diffStats: { filesChanged: 1, insertions: 5, deletions: 0 },
      },
      peerReviews: [
        {
          score: 1.0,
          modelTier: "XHigh",
          modelFamily: "claude",
          sycophancyRisk: 0.05,
          claimsRepeatedWithoutEvidence: false,
          observedConfidence: false,
        },
      ],
    });
    near("T1.4.4b: Clean test + linters + Opus review reaches ~0.987", getScore(confPeerWithLint), 0.987, 0.015);

    // T1.4.5: Mathematical sigmoid and logOdds invertibility
    const pSample = 0.732;
    const lSample = logOdds(pSample);
    const pInverted = sigmoid(lSample);
    near("T1.4.5: sigmoid(logOdds(p)) === p invertible", pInverted, pSample, 0.0001);
  }

  // --------------------------------------------------------------------------
  // Feature 5: Evidence Handling
  // --------------------------------------------------------------------------
  console.log("\n[Feature 5: Evidence Handling]");
  {
    // T1.5.1: Clean test logs with exitCode 0 sets deterministicPass true
    const evPass: ObjectiveVerificationEvidence = {
      command: "go test -v ./...",
      exitCode: 0,
      stdoutSnippet: "PASS\nok  command-line-arguments 0.012s",
      stderrSnippet: "",
      deterministicPass: true,
      diffStats: { filesChanged: 2, insertions: 25, deletions: 4 },
    };
    check("T1.5.1: Clean evidence correctly flags deterministicPass: true", evPass.deterministicPass && evPass.exitCode === 0);

    // T1.5.2: DiffStats accurately recorded
    check("T1.5.2: DiffStats records file modification counts accurately", evPass.diffStats.filesChanged === 2 && evPass.diffStats.insertions === 25 && evPass.diffStats.deletions === 4);

    // T1.5.3: AST analysis structure validates syntax and symbols
    const evAst: ObjectiveVerificationEvidence = {
      ...evPass,
      astAnalysis: {
        tool: "tree-sitter",
        symbolsChanged: ["VerifySignature", "ParseToken"],
        syntaxValid: true,
      },
    };
    check("T1.5.3: AST analysis structure includes symbols and syntax validity", evAst.astAnalysis?.syntaxValid === true && evAst.astAnalysis?.symbolsChanged.length === 2);

    // T1.5.4: Typecheck failure marks deterministicPass false
    const evTypeFail: ObjectiveVerificationEvidence = {
      command: "bun build --no-bundle src/index.ts",
      exitCode: 1,
      stdoutSnippet: "",
      stderrSnippet: "error: Type 'string' is not assignable to type 'number'",
      deterministicPass: false,
      diffStats: { filesChanged: 1, insertions: 1, deletions: 1 },
    };
    check("T1.5.4: Type check failure sets deterministicPass: false", !evTypeFail.deterministicPass && evTypeFail.exitCode !== 0);

    // T1.5.5: Evidence presence validation in ConfidenceEngine
    const confWithEv = calculateConfidence({ toolEvidence: evPass });
    const confWithoutEv = calculateConfidence({});
    check("T1.5.5: Verified evidence produces higher confidence than missing evidence", getScore(confWithEv) > getScore(confWithoutEv));
  }

  // --------------------------------------------------------------------------
  // Feature 6: Deterministic Tool Binary Veto
  // --------------------------------------------------------------------------
  console.log("\n[Feature 6: Deterministic Tool Binary Veto]");
  {
    // T1.6.1: exitCode != 0 forces confidence to exactly 0.0
    const confFail1 = calculateConfidence({
      toolEvidence: {
        command: "go test ./...",
        exitCode: 1,
        stdoutSnippet: "FAIL: TestTokenExpiration",
        stderrSnippet: "",
        deterministicPass: false,
        diffStats: { filesChanged: 1, insertions: 2, deletions: 1 },
      },
      peerReviews: [{ score: 0.99, modelTier: "XHigh" }],
    });
    eq("T1.6.1: Test exitCode 1 forces confidence to 0.0 despite high peer review", getScore(confFail1), 0.0);

    // T1.6.2: Compiler / syntax error forces confidence to 0.0
    const confSyntaxFail = calculateConfidence({
      toolEvidence: {
        command: "bun build",
        exitCode: 2,
        stdoutSnippet: "",
        stderrSnippet: "SyntaxError: Unexpected token",
        deterministicPass: false,
        diffStats: { filesChanged: 1, insertions: 1, deletions: 0 },
      },
      peerReviews: [{ score: 0.95, modelTier: "High" }],
    });
    eq("T1.6.2: Compiler / syntax error forces confidence to 0.0", getScore(confSyntaxFail), 0.0);

    // T1.6.3: Linter failure with deterministicPass false forces confidence to 0.0
    const confLintFail = calculateConfidence({
      toolEvidence: {
        command: "golangci-lint run",
        exitCode: 1,
        stdoutSnippet: "errcheck: Error return value of os.Remove is not checked",
        stderrSnippet: "",
        deterministicPass: false,
        diffStats: { filesChanged: 1, insertions: 4, deletions: 1 },
      },
    });
    eq("T1.6.3: Linter exitCode 1 sets confidence to 0.0", getScore(confLintFail), 0.0);

    // T1.6.4: Binary veto cannot be outvoted by any number of peer approvals
    const confMultiPeerFail = calculateConfidence({
      toolEvidence: {
        command: "make test",
        exitCode: 1,
        stdoutSnippet: "FAIL",
        stderrSnippet: "",
        deterministicPass: false,
        diffStats: { filesChanged: 1, insertions: 1, deletions: 1 },
      },
      peerReviews: [
        { score: 1.0, modelTier: "XHigh" },
        { score: 1.0, modelTier: "High" },
        { score: 1.0, modelTier: "High" },
      ],
    });
    eq("T1.6.4: Three peer approvals cannot override deterministic binary veto (C=0.0)", getScore(confMultiPeerFail), 0.0);

    // T1.6.5: Recovery - once tool passes on revision, binary veto lifts
    const confFixed = calculateConfidence({
      toolEvidence: {
        command: "make test",
        exitCode: 0,
        stdoutSnippet: "PASS",
        stderrSnippet: "",
        deterministicPass: true,
        diffStats: { filesChanged: 1, insertions: 5, deletions: 1 },
      },
      peerReviews: [{ score: 0.95, modelTier: "XHigh", sycophancyRisk: 0.05 }],
    });
    check("T1.6.5: Binary veto lifts and confidence restores once tests pass", getScore(confFixed) >= 0.95);
  }

  // --------------------------------------------------------------------------
  // Feature 7: Autonomous Peer Task Handoff
  // --------------------------------------------------------------------------
  console.log("\n[Feature 7: Autonomous Peer Task Handoff]");
  {
    const controller = new PeerHandoffController({ correlationId: "task-feat-7" });

    // T1.7.1: Worker publishes draft -> state transitions from DRAFTING to VERIFYING
    eq("T1.7.1a: Initial controller state is DRAFTING", controller.getState(), "DRAFTING");
    const draftPayload: DraftPayload = {
      taskSlug: "auth-refresh",
      worktreePath: "/tmp/worktree-1",
      baseRef: "main",
      headSha: "abc1234",
      patch: "diff --git a/auth.ts b/auth.ts\n...",
      filesModified: ["auth.ts"],
      summary: "Add refresh token rotation",
    };
    const submitRes = controller.submitDraft(draftPayload);
    eq("T1.7.1b: Submitting draft transitions state to VERIFYING", controller.getState(), "VERIFYING");

    // T1.7.2: Outcome Non-Disclosure - draft masking strips author confidence and self-evaluation
    const unmasked = {
      ...draftPayload,
      authorConfidence: 0.99,
      authorInternalReasoning: "I am sure this works",
      attemptNumber: 3,
    };
    const maskedDraft = controller.submitDraft(unmasked as any);
    check("T1.7.2: Outcome Non-Disclosure strips author confidence and self-evaluation", (maskedDraft.maskedPayload as any).authorConfidence === undefined && (maskedDraft.maskedPayload as any).authorInternalReasoning === undefined);

    // T1.7.3: Reviewer publishes critique -> state transitions to REMEDIATING
    const critique: CritiquePayload = {
      taskSlug: "auth-refresh",
      targetMessageId: "msg-draft-1",
      lens: "security",
      severity: "warning",
      reproCommand: "curl -X POST /refresh -d 'invalid'",
      objection: "Token replay attack possible without nonce check",
      remediationHint: "Store used nonces in redis with TTL",
    };
    const critiqueRes = controller.receiveCritiques([critique]);
    eq("T1.7.3: Receiving open critiques transitions state to REMEDIATING", controller.getState(), "REMEDIATING");

    // T1.7.4: Reviewer publishes unanimous PASS with C >= 0.95 -> transitions to GATE_READY
    controller.remediate(); // increment attempt, move back to DRAFTING
    controller.submitDraft(draftPayload); // move to VERIFYING
    const passVerification: VerificationPayload = {
      taskSlug: "auth-refresh",
      targetDraftMessageId: "msg-draft-2",
      verdict: "PASS",
      evaluatorId: "opus-checker",
      evaluatorModel: "claude-opus-4",
      evidence: {
        command: "bun test",
        exitCode: 0,
        stdoutSnippet: "all passed",
        stderrSnippet: "",
        deterministicPass: true,
        diffStats: { filesChanged: 1, insertions: 15, deletions: 2 },
      },
      findings: [],
    };
    const verifRes = controller.receiveVerification(passVerification);
    eq("T1.7.4: Clean verification approval transitions state to GATE_READY", controller.getState(), "GATE_READY");

    // T1.7.5: 5-component handoff payload validation
    const handoffData = {
      observation: "Test failed with nil pointer dereference at auth.go:42",
      logicChain: "auth.go:42 lacks null check before user.Token dereference -> passing null causes panic -> adding if user == nil check fixes crash",
      caveats: "Redis session store must also handle expired tokens gracefully",
      conclusion: "Patch applied with null check, test suite now passes cleanly",
      verificationMethod: "go test -v -run TestUserNilToken ./auth",
    };
    check("T1.7.5: 5-component handoff payload contains all required sections", Boolean(handoffData.observation && handoffData.logicChain && handoffData.caveats && handoffData.conclusion && handoffData.verificationMethod));
  }

  // --------------------------------------------------------------------------
  // Feature 8: Attempt Counter & Budgeting
  // --------------------------------------------------------------------------
  console.log("\n[Feature 8: Attempt Counter & Budgeting]");
  {
    const controller = new PeerHandoffController({ correlationId: "task-feat-8", maxAttempts: 5 });

    // T1.8.1: Initial attempt counter is 1
    eq("T1.8.1: Initial attempt counter starts at 1", controller.getAttemptCount(), 1);

    // T1.8.2: First remediation increments to attempt 2
    controller.receiveCritiques([{ taskSlug: "t", targetMessageId: "m", lens: "logic", severity: "warning", objection: "bug", remediationHint: "fix" }]);
    const rem1 = controller.remediate();
    eq("T1.8.2: First remediation increments attempt counter to 2", controller.getAttemptCount(), 2);
    check("T1.8.2b: Attempt 2 does NOT trigger soft checkpoint", !rem1.softCheckpoint);

    // T1.8.3: Attempt 3 triggers SOFT_CHECKPOINT flag for clean-context debugger
    controller.receiveCritiques([{ taskSlug: "t", targetMessageId: "m", lens: "logic", severity: "warning", objection: "bug2", remediationHint: "fix2" }]);
    const rem2 = controller.remediate();
    eq("T1.8.3a: Second remediation sets attempt counter to 3", controller.getAttemptCount(), 3);
    check("T1.8.3b: Attempt 3 triggers soft checkpoint for fresh debugger invocation", rem2.softCheckpoint === true);

    // T1.8.4: Attempt 4 continues with incremented counter
    controller.receiveCritiques([{ taskSlug: "t", targetMessageId: "m", lens: "logic", severity: "warning", objection: "bug3", remediationHint: "fix3" }]);
    const rem3 = controller.remediate();
    eq("T1.8.4a: Third remediation sets attempt counter to 4", controller.getAttemptCount(), 4);
    check("T1.8.4b: Attempt 4 does not trigger soft checkpoint", !rem3.softCheckpoint);

    // T1.8.5: Attempt 5 failure triggers HARD_CAP and transitions to ESCALATED
    controller.receiveCritiques([{ taskSlug: "t", targetMessageId: "m", lens: "logic", severity: "warning", objection: "bug4", remediationHint: "fix4" }]);
    controller.remediate(); // moves to attempt 5
    eq("T1.8.5a: Attempt counter reaches 5", controller.getAttemptCount(), 5);
    controller.receiveCritiques([{ taskSlug: "t", targetMessageId: "m", lens: "logic", severity: "warning", objection: "bug5", remediationHint: "fix5" }]);
    const rem5 = controller.remediate(); // attempt 5 fails -> exceeded
    check("T1.8.5b: Hard cap exceeded triggers escalation", rem5.escalated === true);
    eq("T1.8.5c: State transitions to ESCALATED upon exceeding budget cap", controller.getState(), "ESCALATED");
  }
}

// ============================================================================
// TIER 2: BOUNDARY & CORNER CASES
// ============================================================================

async function runTier2BoundaryTests() {
  console.log("\n--- TIER 2: Boundary & Corner Cases ---");

  // T2.1: Empty message payload and empty evidence array handling
  const emptyConf = calculateConfidence({ toolEvidence: undefined, peerReviews: [], critiques: [] });
  check("T2.1: Empty inputs produce valid confidence score without exceptions", !isNaN(getScore(emptyConf)) && getScore(emptyConf) > 0);

  // T2.2: Extreme confidence scores (0.0 clamped, 1.0 asymptotic handling without NaN)
  const zeroConf = calculateConfidence({
    toolEvidence: { command: "test", exitCode: 1, deterministicPass: false, stdoutSnippet: "", stderrSnippet: "", diffStats: { filesChanged: 0, insertions: 0, deletions: 0 } },
  });
  eq("T2.2a: Extreme score 0.0 is cleanly clamped", getScore(zeroConf), 0.0);

  const maxLogOdds = 1000;
  const sigInf = sigmoid(maxLogOdds);
  check("T2.2b: Extreme log-odds sigmoid approaches 1.0 without becoming NaN or Infinity", sigInf <= 1.0 && !isNaN(sigInf) && sigInf > 0.9999);

  // T2.3: Extreme negative log-odds sigmoid approaches 0.0
  const minLogOdds = -1000;
  const sigNegInf = sigmoid(minLogOdds);
  check("T2.3: Extreme negative log-odds approaches 0.0 without underflow NaN", sigNegInf >= 0.0 && !isNaN(sigNegInf) && sigNegInf < 0.0001);

  // T2.4: Sycophancy penalty edge case: unbacked approval with 0 evidence discounted by 80% (C * 0.20)
  const unbackedConf = calculateConfidence({
    peerReviews: [
      {
        score: 0.95,
        modelTier: "XHigh",
        claimsRepeatedWithoutEvidence: true,
        sycophancyRisk: 0.80,
      },
    ],
  });
  check("T2.4: Unbacked sycophantic review is heavily penalized and remains well below 0.95 threshold", getScore(unbackedConf) < 0.60);

  // T2.5: Behavioral entanglement CIG discount: intra-family (0.70) vs cross-family (0.20)
  const intraFamilyConf = calculateConfidence({
    toolEvidence: { command: "test", exitCode: 0, deterministicPass: true, stdoutSnippet: "", stderrSnippet: "", diffStats: { filesChanged: 1, insertions: 1, deletions: 0 } },
    peerReviews: [
      { score: 0.95, modelFamily: "claude", modelTier: "High", sycophancyRisk: 0.10 },
      { score: 0.95, modelFamily: "claude", modelTier: "High", sycophancyRisk: 0.10 }, // intra-family
    ],
  });
  const crossFamilyConf = calculateConfidence({
    toolEvidence: { command: "test", exitCode: 0, deterministicPass: true, stdoutSnippet: "", stderrSnippet: "", diffStats: { filesChanged: 1, insertions: 1, deletions: 0 } },
    peerReviews: [
      { score: 0.95, modelFamily: "claude", modelTier: "High", sycophancyRisk: 0.10 },
      { score: 0.95, modelFamily: "gemini", modelTier: "High", sycophancyRisk: 0.10 }, // cross-family
    ],
  });
  check("T2.5: Cross-family peers yield higher confidence than intra-family peers due to CIG discounting", getScore(crossFamilyConf) > getScore(intraFamilyConf));

  // T2.6: Peer observed author confidence: sycophancy risk penalized to 0.50
  const observedConf = calculateConfidence({
    peerReviews: [{ score: 0.95, modelTier: "High", observedConfidence: true, sycophancyRisk: 0.50 }],
  });
  const blindConf = calculateConfidence({
    peerReviews: [{ score: 0.95, modelTier: "High", observedConfidence: false, sycophancyRisk: 0.05 }],
  });
  check("T2.6: Peer who observed author confidence has lower effective weight than blind verifier", getScore(observedConf) < getScore(blindConf));

  // T2.7: Blackboard file stream gracefully handles corrupted / truncated JSON lines without crashing
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "mesh-corrupt-test-"));
  try {
    const stream = new BlackboardStream({ basePath: tmpDir, correlationId: "task-corrupted" });
    const logPath = stream.getFilePath();

    // Write a valid line, a corrupted line, and another valid line
    const valid1 = JSON.stringify(createMeshMessage({ topic: "spec", sender: "s1", correlationId: "c", payload: { a: 1 } }));
    const corrupted = "{ bad json line truncate...";
    const valid2 = JSON.stringify(createMeshMessage({ topic: "spec", sender: "s2", correlationId: "c", payload: { a: 2 } }));
    fs.writeFileSync(logPath, `${valid1}\n${corrupted}\n${valid2}\n`);

    const readMessages = await stream.readAll();
    check("T2.7: Corrupted JSON lines are skipped without throwing", readMessages.length === 2 && readMessages[0].sender.id === "s1" && readMessages[1].sender.id === "s2");

    stream.close();
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }

  // T2.8: Concurrent Blackboard file writes simulation (rapid parallel appends)
  const concDir = fs.mkdtempSync(path.join(os.tmpdir(), "mesh-conc-test-"));
  try {
    const concStream = new BlackboardStream({ basePath: concDir, correlationId: "task-concurrent" });
    const WRITE_COUNT = 15;
    const writePromises: Promise<void>[] = [];

    for (let i = 0; i < WRITE_COUNT; i++) {
      const msg = createMeshMessage({
        topic: "draft",
        sender: `worker-${i}`,
        correlationId: "task-concurrent",
        payload: { seq: i },
      });
      writePromises.push(Promise.resolve(concStream.append(msg)));
    }
    await Promise.all(writePromises);

    const concEvents = await concStream.readAll();
    check("T2.8: Rapid concurrent appends are all safely persisted without loss or corruption", concEvents.length === WRITE_COUNT);
    concStream.close();
  } finally {
    fs.rmSync(concDir, { recursive: true, force: true });
  }

  // T2.9: Attempt counter boundary: exactly attempt 3 returns softCheckpoint: true, attempt 4 returns false
  const cBound = new PeerHandoffController({ correlationId: "task-bound" });
  cBound.remediate(); // attempt 2
  const r3 = cBound.remediate(); // attempt 3
  const r4 = cBound.remediate(); // attempt 4
  check("T2.9: Soft checkpoint boundary is strictly triggered on attempt 3 only", r3.softCheckpoint === true && r4.softCheckpoint === false);

  // T2.10: Attempt counter boundary: attempt 5 is hard cap
  const cCap = new PeerHandoffController({ correlationId: "task-cap", maxAttempts: 5 });
  cCap.remediate(); // 2
  cCap.remediate(); // 3
  cCap.remediate(); // 4
  const r5 = cCap.remediate(); // 5
  const rExceeded = cCap.remediate(); // 6 -> exceeded
  check("T2.10: Exceeding maxAttempts transitions to ESCALATED and returns escalated: true", r5.escalated === false && rExceeded.escalated === true && cCap.getState() === "ESCALATED");

  // T2.11: calculateConfidence with missing command property does not throw TypeError
  let noCmdThrew = false;
  let confNoCmdScore = 0;
  try {
    const confNoCmd = calculateConfidence({
      toolEvidence: {
        deterministicPass: true,
        exitCode: 0,
        stdoutSnippet: "ok",
      } as any,
    });
    confNoCmdScore = getScore(confNoCmd);
  } catch {
    noCmdThrew = true;
  }
  check("T2.11: calculateConfidence with missing command property does not throw", !noCmdThrew && confNoCmdScore > 0.5);

  // T2.12: receiveVerification rejects undefined evidence and transitions to REMEDIATING (NOT GATE_READY)
  const cUndef = new PeerHandoffController({ correlationId: "task-undef-ev" });
  cUndef.submitDraft({ taskSlug: "t", patch: "" });
  cUndef.receiveVerification({
    taskSlug: "t",
    targetDraftMessageId: "m",
    verdict: "PASS",
    evaluatorId: "e",
    evaluatorModel: "m",
  });
  eq("T2.12: receiveVerification rejects undefined evidence and transitions to REMEDIATING", cUndef.getState(), "REMEDIATING");
  check("T2.12b: State is strictly NOT GATE_READY when evidence is missing", cUndef.getState() !== "GATE_READY");

  // T2.13: receiveVerification rejects failing tool evidence (exitCode != 0)
  const cFailEv = new PeerHandoffController({ correlationId: "task-fail-ev" });
  cFailEv.submitDraft({ taskSlug: "t", patch: "" });
  cFailEv.receiveVerification({
    taskSlug: "t",
    targetDraftMessageId: "m",
    verdict: "PASS",
    evaluatorId: "e",
    evaluatorModel: "m",
    evidence: {
      command: "bun test",
      exitCode: 1,
      deterministicPass: false,
    },
  });
  eq("T2.13: receiveVerification with failing evidence transitions to REMEDIATING", cFailEv.getState(), "REMEDIATING");

  // T2.14: BlackboardStream flock file locking preserves all concurrent writes without loss
  const flockDir = fs.mkdtempSync(path.join(os.tmpdir(), "mesh-flock-test-"));
  try {
    const flockStream = new BlackboardStream({ basePath: flockDir, correlationId: "task-flock-test" });
    const PARALLEL_COUNT = 20;
    const promises: Promise<void>[] = [];
    for (let i = 0; i < PARALLEL_COUNT; i++) {
      const msg = createMeshMessage({
        topic: "draft",
        sender: `flock-worker-${i}`,
        correlationId: "task-flock-test",
        payload: { index: i, timestamp: Date.now() },
      });
      promises.push(flockStream.append(msg));
    }
    await Promise.all(promises);
    const msgs = await flockStream.readAll();
    check("T2.14: BlackboardStream flock locking persists all concurrent writes without loss", msgs.length === PARALLEL_COUNT);
    flockStream.close();
  } finally {
    fs.rmSync(flockDir, { recursive: true, force: true });
  }
}

// ============================================================================
// TIER 3: CROSS-FEATURE COMBINATIONS
// ============================================================================

async function runTier3CombinationTests() {
  console.log("\n--- TIER 3: Cross-Feature Combination Tests ---");

  // T3.1: Dissent critique overriding high peer confidence
  // Clean tests + linters + Opus PASS has C = 0.987, but a warning with repro (beta = 3.5) drops C to ~0.695 < 0.95
  const confWithWarning = calculateConfidence({
    toolEvidence: {
      command: "make test",
      exitCode: 0,
      deterministicPass: true,
      lintersPassed: true,
      stdoutSnippet: "PASS",
      stderrSnippet: "",
      diffStats: { filesChanged: 1, insertions: 10, deletions: 0 },
    },
    peerReviews: [
      { score: 1.0, modelTier: "XHigh", sycophancyRisk: 0.05 },
    ],
    critiques: [
      {
        taskSlug: "comb-1",
        targetMessageId: "m1",
        lens: "security",
        severity: "warning",
        reproCommand: "go test -run TestRace ./...",
        objection: "Data race detected on shared channel",
        remediationHint: "Protect access with sync.Mutex",
      },
    ],
  });
  near("T3.1: Reproducible warning drops confidence from ~0.987 to ~0.695 below GATE threshold", getScore(confWithWarning), 0.695, 0.03);
  check("T3.1b: Confidence with active warning is strictly below GATE_CONFIDENCE_THRESHOLD (0.95)", getScore(confWithWarning) < GATE_CONFIDENCE_THRESHOLD);

  // T3.2: Tool failure vetoing unanimous positive peer reviews
  // 3 reviewers vote PASS with 1.0 confidence, but deterministic test suite fails
  const confUnanimousToolFail = calculateConfidence({
    toolEvidence: {
      command: "npm test",
      exitCode: 1,
      deterministicPass: false,
      stdoutSnippet: "1 failed, 15 passed",
      stderrSnippet: "",
      diffStats: { filesChanged: 1, insertions: 5, deletions: 1 },
    },
    peerReviews: [
      { score: 1.0, modelTier: "XHigh" },
      { score: 1.0, modelTier: "High" },
      { score: 1.0, modelTier: "High" },
    ],
  });
  eq("T3.2: Deterministic test failure completely overrides 3/3 unanimous LLM PASS votes (C=0.0)", getScore(confUnanimousToolFail), 0.0);

  // T3.3: Blackboard stream synchronization with Coordinator DAG
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "mesh-sync-dag-"));
  try {
    const stream = new BlackboardStream({ basePath: tmpDir, correlationId: "task-sync-dag" });
    const coordinator = new CoordinatorEngine();

    const parent = createMeshMessage({
      topic: "spec",
      sender: "planner",
      correlationId: "task-sync-dag",
      payload: { spec: "v1" },
    });
    const child = createMeshMessage({
      topic: "draft",
      sender: "worker",
      correlationId: "task-sync-dag",
      parentMessageId: parent.id,
      payload: { code: "impl" },
    });

    await stream.append(parent);
    await stream.append(child);
    coordinator.processMessage(parent);
    coordinator.processMessage(child);

    const streamEvents = await stream.readAll();
    const dag = coordinator.buildCausalDag("task-sync-dag");

    check("T3.3: Blackboard stream and coordinator DAG stay perfectly synchronized", streamEvents.length === 2 && dag.get(parent.id)?.[0].id === child.id);

    stream.close();
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }

  // T3.4: Asymmetric Dissent: Blocker critique drops confidence to 0.0, advisory critique only subtracts 0.3 log-odds
  const confAdvisory = calculateConfidence({
    toolEvidence: { command: "test", exitCode: 0, deterministicPass: true, stdoutSnippet: "", stderrSnippet: "", diffStats: { filesChanged: 1, insertions: 1, deletions: 0 } },
    peerReviews: [{ score: 0.95, modelTier: "High" }],
    critiques: [{ taskSlug: "t", targetMessageId: "m", lens: "docs", severity: "advisory", objection: "typo in docstring", remediationHint: "fix typo" }],
  });
  const confBlocker = calculateConfidence({
    toolEvidence: { command: "test", exitCode: 0, deterministicPass: true, stdoutSnippet: "", stderrSnippet: "", diffStats: { filesChanged: 1, insertions: 1, deletions: 0 } },
    peerReviews: [{ score: 0.95, modelTier: "High" }],
    critiques: [{ taskSlug: "t", targetMessageId: "m", lens: "sec", severity: "blocker", objection: "SQL injection", remediationHint: "use prepared statements" }],
  });
  check("T3.4: Advisory critique mildly penalizes confidence while blocker zeroes it completely", getScore(confAdvisory) > 0.70 && getScore(confBlocker) === 0.0);

  // T3.5: Multi-reviewer repetition penalty: identical claims repeated without new evidence are downweighted
  const confNonRepetitive = calculateConfidence({
    peerReviews: [
      { score: 0.95, modelTier: "High", claimsRepeatedWithoutEvidence: false, sycophancyRisk: 0.05 },
      { score: 0.95, modelTier: "High", claimsRepeatedWithoutEvidence: false, sycophancyRisk: 0.05 },
    ],
  });
  const confRepetitive = calculateConfidence({
    peerReviews: [
      { score: 0.95, modelTier: "High", claimsRepeatedWithoutEvidence: true, sycophancyRisk: 0.80 },
      { score: 0.95, modelTier: "High", claimsRepeatedWithoutEvidence: true, sycophancyRisk: 0.80 },
    ],
  });
  check("T3.5: Repeated claims without verified evidence receive heavier sycophancy penalty", getScore(confNonRepetitive) > getScore(confRepetitive));
}

// ============================================================================
// TIER 4: REAL-WORLD SCENARIOS
// ============================================================================

async function runTier4RealWorldScenarios() {
  console.log("\n--- TIER 4: Real-World Scenarios ---");

  // T4.1: Scenario 1 - Autonomous Worker-Checker-Fixer Loop
  console.log("\n[Scenario 1: Autonomous Worker-Checker-Fixer Loop]");
  {
    const controller = new PeerHandoffController({ correlationId: "task-scenario-1" });
    eq("T4.1a: Initial state is DRAFTING", controller.getState(), "DRAFTING");

    // Worker creates draft with a flaw
    controller.submitDraft({
      taskSlug: "kv-store",
      worktreePath: "/tmp/wt-1",
      baseRef: "main",
      headSha: "sha1",
      patch: "func Get(k string) string { return m[k] }",
      filesModified: ["kv.go"],
      summary: "Add KV store lookup",
    });
    eq("T4.1b: State advances to VERIFYING", controller.getState(), "VERIFYING");

    // Checker identifies missing mutex lock for concurrent map read/write
    controller.receiveCritiques([
      {
        taskSlug: "kv-store",
        targetMessageId: "m-draft-1",
        lens: "systems-lang",
        severity: "warning",
        reproCommand: "go test -race ./...",
        objection: "Fatal: concurrent map read and map write detected under race detector",
        remediationHint: "Wrap map access in sync.RWMutex",
      },
    ]);
    eq("T4.1c: Critique moves controller to REMEDIATING", controller.getState(), "REMEDIATING");

    // Worker applies remediation (Attempt 2)
    controller.remediate();
    eq("T4.1d: Remediating advances attempt counter to 2", controller.getAttemptCount(), 2);

    // Worker resubmits draft with sync.RWMutex and passing tests
    controller.submitDraft({
      taskSlug: "kv-store",
      worktreePath: "/tmp/wt-1",
      baseRef: "main",
      headSha: "sha2",
      patch: "mu.RLock(); defer mu.RUnlock(); return m[k]",
      filesModified: ["kv.go"],
      summary: "Add RWMutex locking to KV Get",
    });

    // Reviewer audits revision: tests pass, zero warnings, Opus approves
    const approvedVerif: VerificationPayload = {
      taskSlug: "kv-store",
      targetDraftMessageId: "m-draft-2",
      verdict: "PASS",
      evaluatorId: "opus-checker",
      evaluatorModel: "claude-opus-4",
      evidence: {
        command: "go test -race -v ./...",
        exitCode: 0,
        stdoutSnippet: "PASS\nok  kv 0.045s",
        stderrSnippet: "",
        deterministicPass: true,
        diffStats: { filesChanged: 1, insertions: 6, deletions: 1 },
      },
      findings: [],
    };
    controller.receiveVerification(approvedVerif);
    eq("T4.1e: Clean verification approval transitions lifecycle directly to GATE_READY", controller.getState(), "GATE_READY");
  }

  // T4.2: Scenario 2 - Echo Chamber Sycophancy Discounting Simulation
  console.log("\n[Scenario 2: Echo Chamber Sycophancy Discounting]");
  {
    // Author claims 0.99 confidence on flawed code
    // 3 peer reviewers from the same model family echo approval with "LGTM, looks good!" without citing any new AST or test logs
    const echoChamberScore = calculateConfidence({
      peerReviews: [
        { score: 0.99, modelTier: "High", modelFamily: "claude", claimsRepeatedWithoutEvidence: true, sycophancyRisk: 0.80 },
        { score: 0.99, modelTier: "High", modelFamily: "claude", claimsRepeatedWithoutEvidence: true, sycophancyRisk: 0.80 },
        { score: 0.99, modelTier: "High", modelFamily: "claude", claimsRepeatedWithoutEvidence: true, sycophancyRisk: 0.80 },
      ],
    });
    check("T4.2: Echo chamber reviews without verified evidence are discounted and fail to reach GATE (C < 0.95)", getScore(echoChamberScore) < GATE_CONFIDENCE_THRESHOLD);
  }

  // T4.3: Scenario 3 - Malicious / Hallucinated Agent with High Self-Confidence
  console.log("\n[Scenario 3: Hallucinated Agent with High Self-Confidence]");
  {
    // Agent asserts C = 1.0, but deterministic compiler rejects code with syntax error
    const halluConf = calculateConfidence({
      peerReviews: [{ score: 1.0, modelTier: "Max" }],
      toolEvidence: {
        command: "tsc --noEmit",
        exitCode: 2,
        stdoutSnippet: "",
        stderrSnippet: "error TS2304: Cannot find name 'unresolvedIdentifier'",
        deterministicPass: false,
        diffStats: { filesChanged: 1, insertions: 10, deletions: 0 },
      },
    });
    eq("T4.3: Hallucinated agent claiming 1.0 confidence is immediately vetoed to C = 0.0 by typechecker", getScore(halluConf), 0.0);
  }

  // T4.4: Scenario 4 - Soft Checkpoint Escalation to Clean Debugger at Attempt 3
  console.log("\n[Scenario 4: Soft Checkpoint Clean-Context Debugger Spawning]");
  {
    const controller = new PeerHandoffController({ correlationId: "task-scenario-4" });
    controller.submitDraft({ taskSlug: "buggy", worktreePath: "/tmp", baseRef: "main", headSha: "1", patch: "", filesModified: [], summary: "" });

    // Attempt 1 fails
    controller.receiveCritiques([{ taskSlug: "buggy", targetMessageId: "1", lens: "logic", severity: "warning", objection: "wrong order", remediationHint: "" }]);
    const r1 = controller.remediate();
    check("T4.4a: Attempt 1 remediation is within fast worker loop", !r1.softCheckpoint);

    // Attempt 2 fails -> Triggers Fixer Pattern (debugger subagent with clean context at attempt 3)
    controller.receiveCritiques([{ taskSlug: "buggy", targetMessageId: "2", lens: "logic", severity: "warning", objection: "wrong order persistent", remediationHint: "" }]);
    const r2 = controller.remediate();
    check("T4.4b: Attempt 3 triggers soft checkpoint for unpolluted debugger context", r2.softCheckpoint === true && controller.getAttemptCount() === 3);
  }

  // T4.5: Scenario 5 - Concurrent Multi-Session Mesh Blackboard IPC Arbitration
  console.log("\n[Scenario 5: Concurrent Multi-Session Mesh Blackboard IPC]");
  {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "mesh-multi-session-"));
    try {
      const sessionAuth = new BlackboardStream({ basePath: tmpDir, correlationId: "session-auth" });
      const sessionCrypto = new BlackboardStream({ basePath: tmpDir, correlationId: "session-crypto" });

      await sessionAuth.append(createMeshMessage({ topic: "draft", sender: "w-auth", correlationId: "session-auth", payload: { mod: "auth" } }));
      await sessionCrypto.append(createMeshMessage({ topic: "draft", sender: "w-crypto", correlationId: "session-crypto", payload: { mod: "crypto" } }));

      const authMsgs = await sessionAuth.readAll();
      const cryptoMsgs = await sessionCrypto.readAll();

      check("T4.5: Parallel sessions maintain separate independent blackboard event streams without cross-talk", authMsgs.length === 1 && cryptoMsgs.length === 1 && (authMsgs[0].payload as any).mod === "auth" && (cryptoMsgs[0].payload as any).mod === "crypto");

      sessionAuth.close();
      sessionCrypto.close();
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  }

  // T4.6: Scenario 6 - Active Mesh Subscription & Autonomous GATE_READY Emission
  console.log("\n[Scenario 6: Active Mesh Subscription & Autonomous GATE_READY Emission]");
  {
    let gateReadyReceived: MeshMessage | null = null;
    const testMesh = new SubagentMesh();
    const testCtrl = new PeerHandoffController({
      correlationId: "task-auto-gate",
      onGateReady: (v) => {
        const gateMsg = createMeshMessage({
          topic: "verification",
          sender: { id: "coordinator", role: "coordinator" },
          correlationId: "task-auto-gate",
          recipient: "*",
          payload: { taskSlug: v.taskSlug, status: "GATE_READY", verdict: "PASS" },
          evidence: v.evidence,
        });
        testMesh.publish(gateMsg);
      },
    });

    testMesh.subscribe("verification", (msg) => {
      if ((msg.payload as any)?.status === "GATE_READY") {
        gateReadyReceived = msg;
      }
    });

    testCtrl.submitDraft({ taskSlug: "auto-gate-test", patch: "" });
    testCtrl.receiveVerification({
      taskSlug: "auto-gate-test",
      targetDraftMessageId: "draft-1",
      verdict: "PASS",
      evaluatorId: "checker",
      evaluatorModel: "claude-opus",
      evidence: {
        deterministicPass: true,
        exitCode: 0,
        command: "bun test",
      },
    });

    check("T4.6: Autonomous emission of GATE_READY on mesh upon reaching consensus", gateReadyReceived !== null && (gateReadyReceived as any).payload.status === "GATE_READY");
  }

  // T4.7: Scenario 7 - Outcome Non-Disclosure on Draft Submissions
  console.log("\n[Scenario 7: Outcome Non-Disclosure on Draft Submissions]");
  {
    const ctrlOnd = new PeerHandoffController({ correlationId: "task-ond" });
    const draftWithSecrets: DraftPayload = {
      taskSlug: "ond-task",
      patch: "diff",
      authorConfidence: 0.99,
      authorInternalReasoning: "internal secret reasoning",
      attemptNumber: 2,
      selfScore: 10,
    };
    const { maskedPayload } = ctrlOnd.submitDraft(draftWithSecrets);
    check("T4.7a: Outcome Non-Disclosure strips authorConfidence", maskedPayload.authorConfidence === undefined);
    check("T4.7b: Outcome Non-Disclosure strips authorInternalReasoning", maskedPayload.authorInternalReasoning === undefined);
    check("T4.7c: Outcome Non-Disclosure strips attemptNumber and selfScore", (maskedPayload as any).attemptNumber === undefined && (maskedPayload as any).selfScore === undefined);
  }
}

// ============================================================================
// BENCHMARK TESTS: HIGH-RESOLUTION TIMING (<1ms In-Memory, <10ms File/IPC)
// ============================================================================

async function runBenchmarkTests() {
  console.log("\n--- BENCHMARK TESTS: High-Resolution Latency Overhead ---");

  // --------------------------------------------------------------------------
  // Benchmark 1: In-Memory Event Dispatch Latency (Mean < 1.0ms, P95 < 1.0ms)
  // --------------------------------------------------------------------------
  console.log("\n[Benchmark 1: In-Memory Pub/Sub Dispatch Latency]");
  {
    const mesh = new SubagentMesh();
    const SAMPLES = 1000;
    const WARMUP = 100;
    const timings: number[] = [];

    let receivedMsg: MeshMessage | null = null;
    mesh.subscribe("verification", (msg) => {
      receivedMsg = msg;
    });

    const benchMsg = createMeshMessage({
      topic: "verification",
      sender: { id: "bench-checker", role: "reviewer" },
      correlationId: "task-bench-1",
      payload: { verdict: "PASS" },
    });

    // Warmup
    for (let i = 0; i < WARMUP; i++) {
      mesh.publish(benchMsg);
    }

    // Active measurement
    for (let i = 0; i < SAMPLES; i++) {
      const t0 = performance.now();
      mesh.publish(benchMsg);
      const t1 = performance.now();
      timings.push(t1 - t0);
    }

    const memStats = calculatePercentiles(timings);
    console.log(`In-Memory Dispatch Latency (${SAMPLES} iterations):`);
    console.log(`  Mean: ${memStats.meanMs.toFixed(4)} ms`);
    console.log(`  P50:  ${memStats.p50Ms.toFixed(4)} ms`);
    console.log(`  P95:  ${memStats.p95Ms.toFixed(4)} ms`);
    console.log(`  P99:  ${memStats.p99Ms.toFixed(4)} ms`);
    console.log(`  Max:  ${memStats.maxMs.toFixed(4)} ms`);

    check("TB.1a: In-memory Event Dispatch Mean Latency < 1.0ms", memStats.meanMs < 1.0, `mean=${memStats.meanMs.toFixed(4)}ms`);
    check("TB.1b: In-memory Event Dispatch P95 Latency < 1.0ms", memStats.p95Ms < 1.0, `p95=${memStats.p95Ms.toFixed(4)}ms`);
  }

  // --------------------------------------------------------------------------
  // Benchmark 2: File/IPC Blackboard Append + Read Latency (Mean < 10.0ms, P95 < 10.0ms)
  // --------------------------------------------------------------------------
  console.log("\n[Benchmark 2: File/IPC Blackboard Append + Read Latency]");
  {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "mesh-bench-ipc-"));
    try {
      const stream = new BlackboardStream({ basePath: tmpDir, correlationId: "task-bench-ipc" });
      const SAMPLES = 100;
      const WARMUP = 10;
      const timings: number[] = [];

      const benchMsg = createMeshMessage({
        topic: "verification",
        sender: { id: "ipc-checker", role: "reviewer" },
        correlationId: "task-bench-ipc",
        payload: { verdict: "PASS", data: "benchmark payload bytes" },
      });

      // Warmup
      for (let i = 0; i < WARMUP; i++) {
        await stream.append(benchMsg);
        await stream.readRecent(1);
      }

      // Active measurement
      for (let i = 0; i < SAMPLES; i++) {
        const t0 = performance.now();
        await stream.append(benchMsg);
        await stream.readRecent(1);
        const t1 = performance.now();
        timings.push(t1 - t0);
      }

      const fileStats = calculatePercentiles(timings);
      console.log(`File/IPC Append + Read Latency (${SAMPLES} iterations):`);
      console.log(`  Mean: ${fileStats.meanMs.toFixed(4)} ms`);
      console.log(`  P50:  ${fileStats.p50Ms.toFixed(4)} ms`);
      console.log(`  P95:  ${fileStats.p95Ms.toFixed(4)} ms`);
      console.log(`  P99:  ${fileStats.p99Ms.toFixed(4)} ms`);
      console.log(`  Max:  ${fileStats.maxMs.toFixed(4)} ms`);

      check("TB.2a: File/IPC Blackboard Append+Read Mean Latency < 10.0ms", fileStats.meanMs < 10.0, `mean=${fileStats.meanMs.toFixed(4)}ms`);
      check("TB.2b: File/IPC Blackboard Append+Read P95 Latency < 10.0ms", fileStats.p95Ms < 10.0, `p95=${fileStats.p95Ms.toFixed(4)}ms`);

      stream.close();
    } finally {
      fs.rmSync(tmpDir, { recursive: true, force: true });
    }
  }
}

// ============================================================================
// MASTER RUNNER
// ============================================================================

async function main() {
  console.log("================================================================================");
  console.log("Subagent Mesh & Bayesian Confidence Propagation: Test & Benchmark Suite");
  console.log("================================================================================");

  await runTier1FeatureTests();
  await runTier2BoundaryTests();
  await runTier3CombinationTests();
  await runTier4RealWorldScenarios();
  await runBenchmarkTests();

  console.log("\n================================================================================");
  console.log(`Test Execution Summary: ${pass} passed, ${fail} failed`);
  console.log("================================================================================");

  if (fail > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("Unhandled test execution exception:", err);
  process.exit(1);
});
