import extension, {
  buildQuotaAdvice,
  evaluateQuotaGuard,
  loadQuotaUsage,
  resolveFailoverCandidates,
  splitModelRef,
  type ModelRoutingConfig,
  type QuotaGuardPolicy,
  type QuotaUsage,
} from "../model-failover";

let pass = 0;
let fail = 0;

function eq<T>(name: string, actual: T, expected: T) {
  if (JSON.stringify(actual) === JSON.stringify(expected)) {
    console.log(`ok: ${name}`);
    pass++;
  } else {
    console.error(`FAIL: ${name}`);
    console.error(`  actual:   ${JSON.stringify(actual)}`);
    console.error(`  expected: ${JSON.stringify(expected)}`);
    fail++;
  }
}

// Fixture mirrors the real model-routing.json tier/fallback shape.
const routing: ModelRoutingConfig = {
  tiers: {
    Low: {
      model: "opencode-go/deepseek-v4.1-flash",
      fallbacks: [
        { model: "ollama/gpt-oss-20b", trigger: "token_exhaustion" },
        { model: "antigravity-cli/gemini-4-hydrogen", trigger: "rate_limit" },
      ],
    },
    Medium: {
      model: "opencode-go/kimi-k3.1-pro",
      fallbacks: [
        { model: "opencode-go/qwen4-max", trigger: "token_exhaustion" },
        { model: "antigravity-cli/gemini-4-hydrogen", trigger: "rate_limit" },
      ],
    },
    High: {
      model: "anthropic/claude-sonnet-5-5",
      fallbacks: [
        { model: "antigravity-cli/claude-sonnet-5-5", trigger: "rate_limit" },
        { model: "openai/gpt-6.2-sol", trigger: "token_exhaustion" },
        { model: "antigravity-cli/gemini-4-argon", trigger: "cost_saver" },
      ],
    },
    XHigh: {
      model: "openai/gpt-6.2-astra",
      fallbacks: [
        { model: "antigravity-cli/gemini-4-argon", trigger: "rate_limit" },
        { model: "anthropic/claude-opus-5-5", trigger: "cost_saver" },
        { model: "opencode-go/kimi-k3.1-pro", trigger: "token_exhaustion" },
      ],
    },
    Max: {
      model: "anthropic/claude-fable-5-2",
      fallbacks: [
        { model: "anthropic/claude-opus-5-5", trigger: "token_exhaustion" },
        { model: "openai/gpt-6.2-astra", trigger: "rate_limit" },
        { model: "antigravity-cli/gemini-4-argon", trigger: "cost_saver" },
      ],
    },
  },
};

// 1. rate_limit on a tier primary resolves to that tier's rate_limit fallback.
eq(
  "rate_limit on High primary -> antigravity-cli/claude-sonnet-5-5",
  resolveFailoverCandidates(routing, "anthropic/claude-sonnet-5-5", "rate_limit"),
  ["antigravity-cli/claude-sonnet-5-5"]
);

// 2. token_exhaustion on a tier primary resolves to that tier's token_exhaustion fallback.
eq(
  "token_exhaustion on High primary -> openai/gpt-6.2-sol",
  resolveFailoverCandidates(routing, "anthropic/claude-sonnet-5-5", "token_exhaustion"),
  ["openai/gpt-6.2-sol"]
);

// 3. rate_limit on Low primary.
eq(
  "rate_limit on Low primary -> gemini-4-hydrogen",
  resolveFailoverCandidates(routing, "opencode-go/deepseek-v4.1-flash", "rate_limit"),
  ["antigravity-cli/gemini-4-hydrogen"]
);

// 4. token_exhaustion on Medium primary.
eq(
  "token_exhaustion on Medium primary -> opencode-go/qwen4-max",
  resolveFailoverCandidates(routing, "opencode-go/kimi-k3.1-pro", "token_exhaustion"),
  ["opencode-go/qwen4-max"]
);

// 5. Unknown model (not in routing at all) yields no candidates (safe no-op).
eq(
  "unknown model -> []",
  resolveFailoverCandidates(routing, "someprovider/unknown-model", "rate_limit"),
  []
);

// 6. Forward-only chain progression: already on the rate_limit fallback, hitting
//    rate_limit again finds no further rate_limit entry -> chain exhausted.
eq(
  "chain exhausted: on antigravity-cli/claude-sonnet-5-5, rate_limit again -> []",
  resolveFailoverCandidates(routing, "antigravity-cli/claude-sonnet-5-5", "rate_limit"),
  []
);

// 7. Home-tier preference: kimi-k3.1-pro is Medium's primary AND XHigh's token_exhaustion
//    fallback. token_exhaustion must resolve via the Medium home tier, not XHigh.
eq(
  "home-tier preference: kimi-k3.1-pro token_exhaustion -> qwen4-max (Medium home)",
  resolveFailoverCandidates(routing, "opencode-go/kimi-k3.1-pro", "token_exhaustion"),
  ["opencode-go/qwen4-max"]
);

// 8. Model that is a tier primary shared as another tier's fallback:
//    openai/gpt-6.2-astra is XHigh primary -> its rate_limit fallback.
eq(
  "openai/gpt-6.2-astra (XHigh primary) rate_limit -> gemini-4-argon",
  resolveFailoverCandidates(routing, "openai/gpt-6.2-astra", "rate_limit"),
  ["antigravity-cli/gemini-4-argon"]
);

// 8b. Cross-tier fall-through (regression): antigravity-cli/gemini-4-argon is a
//     TERMINAL cost_saver fallback in High (dead-end) but a MID-CHAIN rate_limit
//     fallback in XHigh. A token_exhaustion hit must NOT commit to the High dead-end;
//     it must fall through to XHigh and find the downstream token_exhaustion fallback.
//     This is the real 2-hop scenario: XHigh rate_limit -> gemini-4-argon, then
//     a later token_exhaustion -> kimi-k3.1-pro.
eq(
  "fall-through: shared model, token_exhaustion -> kimi-k3.1-pro (via XHigh, not High dead-end)",
  resolveFailoverCandidates(routing, "antigravity-cli/gemini-4-argon", "token_exhaustion"),
  ["opencode-go/kimi-k3.1-pro"]
);

// 8c. Same shared model, rate_limit: no forward rate_limit entry exists after its
//     position in any containing tier -> genuinely exhausted -> [].
eq(
  "fall-through: shared model, rate_limit fully exhausted -> []",
  resolveFailoverCandidates(routing, "antigravity-cli/gemini-4-argon", "rate_limit"),
  []
);

// 9. No matching trigger in the tier (Low has no cost_saver-style token match at end).
eq(
  "no matching trigger -> []",
  resolveFailoverCandidates(
    { tiers: { High: { model: "a/b", fallbacks: [{ model: "a/c", trigger: "rate_limit" }] } } },
    "a/b",
    "token_exhaustion"
  ),
  []
);

// 10. Undefined / empty routing is handled safely.
eq("undefined routing -> []", resolveFailoverCandidates(undefined, "a/b", "rate_limit"), []);
eq("empty tiers -> []", resolveFailoverCandidates({ tiers: {} }, "a/b", "rate_limit"), []);

// 11. splitModelRef parses provider/modelId, rejects malformed refs.
eq("splitModelRef anthropic/claude-sonnet-5-5", splitModelRef("anthropic/claude-sonnet-5-5"), {
  provider: "anthropic",
  modelId: "claude-sonnet-5-5",
});
eq("splitModelRef keeps nested slashes in id", splitModelRef("prov/a/b"), {
  provider: "prov",
  modelId: "a/b",
});
eq("splitModelRef no slash -> undefined", splitModelRef("noslash"), undefined);
eq("splitModelRef leading slash -> undefined", splitModelRef("/x"), undefined);
eq("splitModelRef trailing slash -> undefined", splitModelRef("x/"), undefined);

// 12. Quota guard: pure decision, usage loading, and the turn_end wiring (advisory only).
const qPolicy: QuotaGuardPolicy = {
  enabled: true,
  fiveHourMaxPct: 20,
  weeklyMaxPct: 50,
  highVolumeSubagentDefault: "opencode-go/deepseek-v4.1-flash",
};
eq("quota: disabled policy -> not enabled", evaluateQuotaGuard({ ...qPolicy, enabled: false }, { fiveHourPct: 99, weeklyPct: 99 }).enabled, false);
eq("quota: undefined policy -> not enabled", evaluateQuotaGuard(undefined, { fiveHourPct: 99, weeklyPct: 99 }).enabled, false);
eq("quota: under both limits -> over=false", evaluateQuotaGuard(qPolicy, { fiveHourPct: 19, weeklyPct: 49 }).over, false);
eq("quota: 5h at limit -> over", evaluateQuotaGuard(qPolicy, { fiveHourPct: 20, weeklyPct: 0 }).over, true);
eq("quota: weekly over -> recommend model", evaluateQuotaGuard(qPolicy, { fiveHourPct: 0, weeklyPct: 60 }).recommend, "opencode-go/deepseek-v4.1-flash");
eq("quota: unknown usage -> over=null (not fine)", evaluateQuotaGuard(qPolicy, { fiveHourPct: null, weeklyPct: null }).over, null);
eq("quota: advice only when over", buildQuotaAdvice(evaluateQuotaGuard(qPolicy, { fiveHourPct: 1, weeklyPct: 1 })), undefined);
eq("quota: advice mentions model", buildQuotaAdvice(evaluateQuotaGuard(qPolicy, { fiveHourPct: 30, weeklyPct: 1 }))?.includes("deepseek-v4.1-flash"), true);
eq("quota: env usage parsed", loadQuotaUsage({ OPENCODE_GO_USAGE_5H_PCT: "25", OPENCODE_GO_USAGE_WEEK_PCT: "7" }, "/nonexistent-home"), { fiveHourPct: 25, weeklyPct: 7 });
eq("quota: out-of-range/garbage env -> null", loadQuotaUsage({ OPENCODE_GO_USAGE_5H_PCT: "250", OPENCODE_GO_USAGE_WEEK_PCT: "abc" }, "/nonexistent-home"), { fiveHourPct: null, weeklyPct: null });

{
  const handlers: Array<(e: unknown, ctx: unknown) => Promise<void>> = [];
  const starts: Array<() => Promise<void>> = [];
  const pi: any = {
    on: (name: string, h: any) => (name === "turn_end" ? handlers.push(h) : name === "session_start" ? starts.push(h) : undefined),
  };
  const notes: string[] = [];
  const ctx = { ui: { notify: (m: string) => notes.push(m) } };
  let usage: QuotaUsage = { fiveHourPct: 30, weeklyPct: 0 };
  extension(pi, {
    loadConfig: () => ({ pricingCliffAdvisoryConfig: { enabled: false } }) as any,
    loadRouting: () => ({ tiers: {}, routingPolicy: { openCodeGoQuotaGuard: qPolicy } }),
    loadQuota: () => usage,
  });
  const fire = async () => {
    for (const h of handlers) await h({}, ctx);
  };
  await fire();
  await fire();
  eq("quota wiring: notifies once while the state is unchanged", notes.length, 1);
  usage = { fiveHourPct: 1, weeklyPct: 1 };
  await fire();
  usage = { fiveHourPct: 30, weeklyPct: 0 };
  await fire();
  eq("quota wiring: re-notifies after recovering and crossing again", notes.length, 2);
  for (const s of starts) await s();
  await fire();
  eq("quota wiring: session_start resets", notes.length, 3);
}

console.log(`\nmodel-failover: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
