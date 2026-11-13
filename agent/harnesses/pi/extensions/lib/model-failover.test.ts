import {
  resolveFailoverCandidates,
  splitModelRef,
  type ModelRoutingConfig,
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
      model: "antigravity/gemini-3.8-flash-low",
      fallbacks: [
        { model: "opencode-go/qwen3.8-flash", trigger: "token_exhaustion" },
        { model: "antigravity/gemini-3.7-flash-low", trigger: "rate_limit" },
      ],
    },
    Medium: {
      model: "opencode-go/kimi-k3",
      fallbacks: [
        { model: "opencode-go/kimi-k2.7-code", trigger: "token_exhaustion" },
        { model: "antigravity/gemini-3.8-flash-medium", trigger: "rate_limit" },
      ],
    },
    High: {
      model: "anthropic/claude-sonnet-5",
      fallbacks: [
        { model: "anthropic/claude-sonnet-4-6", trigger: "rate_limit" },
        { model: "opencode-go/deepseek-v4-pro", trigger: "token_exhaustion" },
        { model: "antigravity/gemini-3.8-flash-high", trigger: "cost_saver" },
      ],
    },
    XHigh: {
      model: "codex/gpt-6-astra",
      fallbacks: [
        { model: "antigravity/gemini-3.8-flash-high", trigger: "rate_limit" },
        { model: "anthropic/claude-opus-5", trigger: "cost_saver" },
        { model: "opencode-go/kimi-k3", trigger: "token_exhaustion" },
      ],
    },
    Max: {
      model: "anthropic/claude-fable-5-1",
      fallbacks: [
        { model: "anthropic/claude-fable-5", trigger: "token_exhaustion" },
        { model: "codex/gpt-6-astra", trigger: "rate_limit" },
        { model: "antigravity/gemini-3.8-flash-high", trigger: "cost_saver" },
      ],
    },
  },
};

// 1. rate_limit on a tier primary resolves to that tier's rate_limit fallback.
eq(
  "rate_limit on High primary -> sonnet-4-6",
  resolveFailoverCandidates(routing, "anthropic/claude-sonnet-5", "rate_limit"),
  ["anthropic/claude-sonnet-4-6"]
);

// 2. token_exhaustion on a tier primary resolves to that tier's token_exhaustion fallback.
eq(
  "token_exhaustion on High primary -> deepseek-v4-pro",
  resolveFailoverCandidates(routing, "anthropic/claude-sonnet-5", "token_exhaustion"),
  ["opencode-go/deepseek-v4-pro"]
);

// 3. rate_limit on Low primary.
eq(
  "rate_limit on Low primary -> gemini-3.7-flash-low",
  resolveFailoverCandidates(routing, "antigravity/gemini-3.8-flash-low", "rate_limit"),
  ["antigravity/gemini-3.7-flash-low"]
);

// 4. token_exhaustion on Medium primary.
eq(
  "token_exhaustion on Medium primary -> kimi-k2.7-code",
  resolveFailoverCandidates(routing, "opencode-go/kimi-k3", "token_exhaustion"),
  ["opencode-go/kimi-k2.7-code"]
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
  "chain exhausted: on sonnet-4-6, rate_limit again -> []",
  resolveFailoverCandidates(routing, "anthropic/claude-sonnet-4-6", "rate_limit"),
  []
);

// 7. Home-tier preference: kimi-k3 is Medium's primary AND XHigh's token_exhaustion
//    fallback. token_exhaustion must resolve via the Medium home tier, not XHigh.
eq(
  "home-tier preference: kimi-k3 token_exhaustion -> kimi-k2.7-code (Medium home)",
  resolveFailoverCandidates(routing, "opencode-go/kimi-k3", "token_exhaustion"),
  ["opencode-go/kimi-k2.7-code"]
);

// 8. Model that is a tier primary shared as another tier's fallback:
//    codex/gpt-6-astra is XHigh primary -> its rate_limit fallback.
eq(
  "codex/gpt-6-astra (XHigh primary) rate_limit -> gemini-3.8-flash-high",
  resolveFailoverCandidates(routing, "codex/gpt-6-astra", "rate_limit"),
  ["antigravity/gemini-3.8-flash-high"]
);

// 8b. Cross-tier fall-through (regression): antigravity/gemini-3.8-flash-high is a
//     TERMINAL cost_saver fallback in High (dead-end) but a MID-CHAIN rate_limit
//     fallback in XHigh. A token_exhaustion hit must NOT commit to the High dead-end;
//     it must fall through to XHigh and find the downstream token_exhaustion fallback.
//     This is the real 2-hop scenario: XHigh rate_limit -> gemini-3.8-flash-high, then
//     a later token_exhaustion -> kimi-k3.
eq(
  "fall-through: shared model, token_exhaustion -> kimi-k3 (via XHigh, not High dead-end)",
  resolveFailoverCandidates(routing, "antigravity/gemini-3.8-flash-high", "token_exhaustion"),
  ["opencode-go/kimi-k3"]
);

// 8c. Same shared model, rate_limit: no forward rate_limit entry exists after its
//     position in any containing tier -> genuinely exhausted -> [].
eq(
  "fall-through: shared model, rate_limit fully exhausted -> []",
  resolveFailoverCandidates(routing, "antigravity/gemini-3.8-flash-high", "rate_limit"),
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
eq("splitModelRef anthropic/claude-sonnet-5", splitModelRef("anthropic/claude-sonnet-5"), {
  provider: "anthropic",
  modelId: "claude-sonnet-5",
});
eq("splitModelRef keeps nested slashes in id", splitModelRef("prov/a/b"), {
  provider: "prov",
  modelId: "a/b",
});
eq("splitModelRef no slash -> undefined", splitModelRef("noslash"), undefined);
eq("splitModelRef leading slash -> undefined", splitModelRef("/x"), undefined);
eq("splitModelRef trailing slash -> undefined", splitModelRef("x/"), undefined);

console.log(`\nmodel-failover: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
