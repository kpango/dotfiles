// Regression tests for agent/hooks/pi/security-gate.ts's `handleShellCommandResult`
// (T9/I-14: reflecting decide.py's Laya-adjusted top-level `decision` into pi's
// confirm/block UX). Run with `bun test` (see agent/scripts/test-security-gate-pi.sh).
//
// Placed under agent/scripts/jev/ rather than agent/hooks/pi/ so this new test file
// is Tier A (agent/hooks/pi/* is Tier B protected per
// agent/write-scope-rules.json's suffix_patterns; test files under
// agent/scripts/jev/ are not -- only its production modules are, CONTEXT.md I-15) --
// same reasoning as agent/scripts/jev/test_decide_integration.py for the Python
// side (T9 draft, §0).
import { describe, expect, test } from "bun:test";
import { handleShellCommandResult } from "../../hooks/pi/security-gate";

type DecideResult = Parameters<typeof handleShellCommandResult>[0];

function fakeConfirm(responses: boolean[]): (title: string, message: string) => Promise<boolean> {
  let i = 0;
  return async (_title, _message) => {
    const r = responses[i] ?? true;
    i += 1;
    return r;
  };
}

describe("handleShellCommandResult", () => {
  test("no laya field at all -- existing all_matches behavior unaffected (hasUI, approved)", async () => {
    const result: DecideResult = {
      decision: "ask",
      reason: "some ask rule",
      matched_rule_id: "git_clean_force_only",
      all_matches: [{ id: "git_clean_force_only", tier: "ask", description: "git clean -f" }],
    };
    const confirm = fakeConfirm([true]);
    const blocked = await handleShellCommandResult(result, "git clean -f", confirm, true);
    expect(blocked).toBeUndefined();
  });

  test("no laya field at all -- existing all_matches behavior unaffected (no UI, hard block)", async () => {
    const result: DecideResult = {
      decision: "block",
      reason: "rm -rf /",
      matched_rule_id: "rm_rf_root_home",
      all_matches: [{ id: "rm_rf_root_home", tier: "block", description: "rm -rf /" }],
    };
    const blocked = await handleShellCommandResult(result, "rm -rf /", fakeConfirm([]), false);
    expect(blocked).toEqual({ block: true, reason: "Security Gate blocked command: rm -rf /" });
  });

  test("guard_deny escalating a deterministic allow (no match at all) -- hard block even with hasUI", async () => {
    const result: DecideResult = {
      decision: "block",
      reason: "orig [laya guard_deny p=0.9500]",
      all_matches: [],
      laya: {
        probability: 0.95,
        enabled_capabilities: ["guard_deny"],
        applied_capability: "guard_deny",
        decision: "block",
      },
    };
    // hasUI=true, and confirm always returns true -- must STILL hard-block (no
    // confirm shown at all; confirmFn is never invoked -- see the dedicated
    // "confirmFn must never be called" test below for that specific assertion).
    const confirm = fakeConfirm([true]);
    const blocked = await handleShellCommandResult(result, "cat ~/.aws/credentials", confirm, true);
    expect(blocked?.block).toBe(true);
    expect(blocked?.reason).toContain("guard_deny");
  });

  test("guard_deny escalating a deterministic allow -- confirmFn is never invoked", async () => {
    const result: DecideResult = {
      decision: "block",
      reason: "orig [laya guard_deny p=0.9500]",
      all_matches: [],
      laya: {
        probability: 0.95,
        enabled_capabilities: ["guard_deny"],
        applied_capability: "guard_deny",
        decision: "block",
      },
    };
    let confirmCalls = 0;
    const confirm = async (_title: string, _message: string) => {
      confirmCalls += 1;
      return true;
    };
    await handleShellCommandResult(result, "cat ~/.aws/credentials", confirm, true);
    expect(confirmCalls).toBe(0);
  });

  test("guard_deny escalating a DETERMINISTIC ask (Checker-reproduced defect): all_matches has an ask-tier entry, must still hard-block unconditionally", async () => {
    // Reproduces the Checker's exact report: guard_deny enabled, mock
    // noul=0.95, harness=pi, command "git checkout ." -> decision="block",
    // all_matches=[git_checkout_discard] (an ask-tier deterministic match).
    // Before the fix, this fell through to the all_matches loop, showed an
    // ordinary confirm for the ask-tier entry, and approving it returned
    // `undefined` (allow), executing the command despite decision="block".
    const result: DecideResult = {
      decision: "block",
      reason: "git checkout . discards uncommitted changes [laya guard_deny p=0.9500]",
      matched_rule_id: "git_checkout_discard",
      all_matches: [{ id: "git_checkout_discard", tier: "ask", description: "git checkout . discards uncommitted changes" }],
      laya: {
        probability: 0.95,
        enabled_capabilities: ["guard_deny"],
        applied_capability: "guard_deny",
        decision: "block",
      },
    };
    // confirm always approves -- if the bug were still present, this would
    // let the command through (return undefined).
    const confirm = fakeConfirm([true]);
    const blocked = await handleShellCommandResult(result, "git checkout .", confirm, true);
    expect(blocked?.block).toBe(true);
  });

  test("deterministic block-tier match (no Laya at all) is now also a hard, unconditional block even with hasUI true and an approving confirm", async () => {
    // Independent of guard_deny: decide.py's own block_rules-before-ask_rules
    // ordering guarantees any all_matches entry with tier "block" already
    // implies decision === "block". The pre-existing pi implementation showed
    // a confirm for this case too when hasUI was true -- this fix closes that
    // inconsistency with I-2 as a byproduct.
    const result: DecideResult = {
      decision: "block",
      reason: "rm -rf /",
      matched_rule_id: "rm_rf_root_home",
      all_matches: [{ id: "rm_rf_root_home", tier: "block", description: "rm -rf /" }],
    };
    const confirm = fakeConfirm([true]);
    const blocked = await handleShellCommandResult(result, "rm -rf /", confirm, true);
    expect(blocked?.block).toBe(true);
  });

  test("guard_strengthen escalating allow->ask (no match at all) -- one confirm, approved -> allow", async () => {
    const result: DecideResult = {
      decision: "ask",
      reason: "orig [laya guard_strengthen p=0.7000]",
      all_matches: [],
      laya: {
        probability: 0.7,
        enabled_capabilities: ["guard_strengthen"],
        applied_capability: "guard_strengthen",
        decision: "ask",
      },
    };
    const confirm = fakeConfirm([true]);
    const blocked = await handleShellCommandResult(result, "rm -rf ./build", confirm, true);
    expect(blocked).toBeUndefined();
  });

  test("guard_strengthen escalating allow->ask (no match at all) -- rejected -> block", async () => {
    const result: DecideResult = {
      decision: "ask",
      reason: "orig [laya guard_strengthen p=0.7000]",
      all_matches: [],
      laya: {
        probability: 0.7,
        enabled_capabilities: ["guard_strengthen"],
        applied_capability: "guard_strengthen",
        decision: "ask",
      },
    };
    const confirm = fakeConfirm([false]);
    const blocked = await handleShellCommandResult(result, "rm -rf ./build", confirm, true);
    expect(blocked?.block).toBe(true);
  });

  test("guard_strengthen with no UI -- hard block (same convention as a deterministic no-UI block)", async () => {
    const result: DecideResult = {
      decision: "ask",
      reason: "orig",
      all_matches: [],
      laya: {
        probability: 0.7,
        enabled_capabilities: ["guard_strengthen"],
        applied_capability: "guard_strengthen",
        decision: "ask",
      },
    };
    const blocked = await handleShellCommandResult(result, "rm -rf ./build", fakeConfirm([]), false);
    expect(blocked?.block).toBe(true);
  });

  test("guard_relax: the confirm for the relaxed match is skipped entirely", async () => {
    const result: DecideResult = {
      decision: "allow",
      reason: "orig [laya guard_relax p=0.1000]",
      matched_rule_id: "git_clean_force_only",
      all_matches: [{ id: "git_clean_force_only", tier: "ask", description: "git clean -f" }],
      laya: {
        probability: 0.1,
        enabled_capabilities: ["guard_relax"],
        applied_capability: "guard_relax",
        decision: "allow",
      },
    };
    // confirm() must NEVER be called -- if it were and returned false, this would
    // wrongly report a block; asserting `blocked === undefined` combined with a
    // confirm stub that always returns false pins "the confirm was skipped, not
    // just approved" (a confirm stub returning true wouldn't distinguish the two).
    const confirm = fakeConfirm([false]);
    const blocked = await handleShellCommandResult(result, "git clean -f", confirm, true);
    expect(blocked).toBeUndefined();
  });

  test("guard_relax: an UNRELATED other match in the same compound command is still processed normally", async () => {
    const result: DecideResult = {
      decision: "allow",
      reason: "orig [laya guard_relax p=0.1000]",
      matched_rule_id: "git_clean_force_only",
      all_matches: [
        { id: "git_clean_force_only", tier: "ask", description: "git clean -f" },
        { id: "some_other_ask_rule", tier: "ask", description: "some other risky thing" },
      ],
      laya: {
        probability: 0.1,
        enabled_capabilities: ["guard_relax"],
        applied_capability: "guard_relax",
        decision: "allow",
      },
    };
    // The relaxed match (git_clean_force_only) is skipped; the OTHER match still
    // gets its own confirm, and rejecting it must still block.
    const confirm = fakeConfirm([false]);
    const blocked = await handleShellCommandResult(result, "git clean -f && some-other-risky-thing", confirm, true);
    expect(blocked?.block).toBe(true);
    expect(blocked?.reason).toContain("some other risky thing");
  });
});
