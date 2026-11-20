/**
 * WA5/T6: per-model context pressure (85% pre-warning / 100% Pricing Cliff) surfaced by
 * context-economy.ts (statusline + /economy) and model-failover.ts (candidate advice).
 * Thresholds come from sol-pi-core (pricingCliffFor / evaluateOnlineCompaction); nothing
 * here may auto-compact or auto-switch (grill D3), and the three extensions that react to
 * turn_end (sol-pi / context-economy / model-failover) must not double-notify.
 */
import { describe, expect, test } from "bun:test";
import contextEconomy, { contextTokensFromUsage, nextStepGuidance } from "../context-economy";
import modelFailover, { buildFailoverAdvice, type ModelRoutingConfig } from "../model-failover";
import { register as registerSolPi } from "../sol-pi";
import { DEFAULT_CONFIG, evaluateOnlineCompaction, setPricingCliffCatalog, type SolPiConfig } from "./sol-pi-core";

const config: SolPiConfig = DEFAULT_CONFIG;
const routing: ModelRoutingConfig = {
  tiers: {
    High: {
      model: "anthropic/claude-sonnet-5-5",
      fallbacks: [
        { model: "anthropic/claude-haiku-5-5", trigger: "token_exhaustion" },
        { model: "openai/gpt-6.2-sol", trigger: "token_exhaustion" },
      ],
    },
    Low: {
      model: "anthropic/claude-haiku-5-5",
      fallbacks: [{ model: "openai/gpt-6.2-sol", trigger: "token_exhaustion" }],
    },
  },
};

interface Harness {
  handlers: Record<string, ((...a: any[]) => any)[]>;
  commands: Record<string, any>;
  sideEffects: string[];
  pi: any;
  notes: { msg: string; level: string }[];
  status: string[];
  ctx: any;
}
function harness(modelProvider: string, modelId: string): Harness {
  const h: Harness = { handlers: {}, commands: {}, sideEffects: [], pi: undefined, notes: [], status: [], ctx: undefined };
  h.pi = new Proxy(
    {
      on: (n: string, fn: any) => void (h.handlers[n] ??= []).push(fn),
      registerCommand: (n: string, d: any) => void (h.commands[n] = d),
      // Tool registration is not a side effect (no model/compaction mutation): keep it
      // out of the sideEffects recorder so ob_recall / online_plan registration stays inert.
      registerTool: (_t: any) => void 0,
    },
    {
      get(t: any, k: string) {
        if (k in t) return t[k];
        // setModel / compact / sendUserMessage / anything else = a side-effect API.
        return (...a: any[]) => void h.sideEffects.push(String(k));
      },
    }
  );
  h.ctx = {
    model: { provider: modelProvider, id: modelId },
    ui: {
      notify: (msg: string, level: string) => h.notes.push({ msg, level }),
      setStatus: (_k: string, v: string) => h.status.push(v),
      theme: { fg: (_c: string, t: string) => t },
    },
    compact: () => h.sideEffects.push("ctx.compact"),
    modelRegistry: { find: () => (h.sideEffects.push("registry.find"), undefined) },
  };
  return h;
}
async function turnEnd(h: Harness, tokens: number, model?: string) {
  const event = { message: { model, usage: { inputTokens: tokens } } };
  for (const fn of h.handlers["turn_end"] ?? []) await fn(event, h.ctx);
}

describe("per-model thresholds come from sol-pi-core (no second copy)", () => {
  const cases: [string, number, number][] = [
    ["anthropic/claude-haiku-5-5", 90_000, 76_500],
    ["openai/gpt-6.2-sol", 250_000, 212_500],
    ["anthropic/claude-sonnet-5-5", 180_000, 153_000],
  ];
  for (const [model, cliff, warnAt] of cases) {
    test(`${model}: ok below ${warnAt}, warn at ${warnAt}, exceeded at ${cliff}`, () => {
      expect(evaluateOnlineCompaction(warnAt - 1, model, undefined, config).level).toBe("ok");
      const w = evaluateOnlineCompaction(warnAt, model, undefined, config);
      expect(w.level).toBe("warn");
      expect(w.cliff).toBe(cliff);
      expect(evaluateOnlineCompaction(cliff, model, undefined, config).level).toBe("exceeded");
    });
  }
  test("a catalog compaction_threshold change is honoured by context-economy (single source)", async () => {
    setPricingCliffCatalog({ models: { "anthropic/claude-haiku-5-5": { model_id: "claude-haiku-5-5", compaction_threshold: 1000 } } });
    try {
      const h = harness("anthropic", "claude-haiku-5-5");
      contextEconomy(h.pi, { loadConfig: () => config });
      await turnEnd(h, 1000);
      expect(h.status.at(-1)).toContain("cliff 100%");
    } finally {
      setPricingCliffCatalog(undefined);
    }
  });
  test("the onlineContextCompact kill switch (shipped state) does not hide the badge", async () => {
    const killed: SolPiConfig = { ...config, onlineContextCompactConfig: { ...config.onlineContextCompactConfig, enabled: false } };
    const h = harness("anthropic", "claude-haiku-5-5");
    contextEconomy(h.pi, { loadConfig: () => killed });
    await turnEnd(h, 95_000);
    expect(h.status.at(-1)).toContain("cliff");
  });
});

describe("nextStepGuidance / contextTokensFromUsage", () => {
  test("ok -> empty; warn -> plan /compact; exceeded -> /compact + ratio 12.5x", () => {
    const m = "anthropic/claude-haiku-5-5";
    expect(nextStepGuidance(evaluateOnlineCompaction(1000, m, 12.5, config), 12.5)).toBe("");
    const w = nextStepGuidance(evaluateOnlineCompaction(80_000, m, 12.5, config), 12.5);
    expect(w).toContain("89%");
    expect(w).toContain("/compact");
    expect(w).toContain("12.5x");
    const e = nextStepGuidance(evaluateOnlineCompaction(95_000, m, 12.5, config), 12.5);
    expect(e).toContain("Pricing Cliff 超過");
    expect(e).toContain("/compact");
    expect(e).toContain("12.5x");
  });
  test("sums fresh + cache read + cache write (same as sol-pi.ts)", () => {
    expect(contextTokensFromUsage({ inputTokens: 1, cacheReadInputTokens: 2, cacheCreationInputTokens: 4 })).toBe(7);
    expect(contextTokensFromUsage(undefined)).toBe(0);
  });
});

describe("context-economy: statusline / report only, never notifies, never acts", () => {
  test("85% shows warn badge, 100% shows cliff badge, ok shows none", async () => {
    const h = harness("anthropic", "claude-haiku-5-5");
    contextEconomy(h.pi, { loadConfig: () => config });
    await turnEnd(h, 10_000);
    expect(h.status.at(-1)).not.toContain("cliff");
    await turnEnd(h, 76_500);
    expect(h.status.at(-1)).toContain("85% of cliff");
    await turnEnd(h, 90_000);
    expect(h.status.at(-1)).toContain("🔴 cliff 100%");
  });
  test("/economy includes the next-step guidance", async () => {
    const h = harness("anthropic", "claude-haiku-5-5");
    contextEconomy(h.pi, { loadConfig: () => config });
    await turnEnd(h, 95_000);
    await h.commands["economy"].handler("", h.ctx);
    expect(h.notes.at(-1)!.msg).toContain("Pricing Cliff 超過");
    expect(h.notes.at(-1)!.msg).toContain("95,000/90,000");
  });
  test("no notify and no side-effect API at any level", async () => {
    const h = harness("anthropic", "claude-haiku-5-5");
    contextEconomy(h.pi, { loadConfig: () => config });
    for (const t of [10_000, 76_500, 90_000, 200_000]) await turnEnd(h, t);
    expect(h.notes).toEqual([]);
    expect(h.sideEffects).toEqual([]);
  });
  test("disabled pricingCliffAdvisory -> no badge", async () => {
    const off: SolPiConfig = { ...config, pricingCliffAdvisoryConfig: { enabled: false } };
    const h = harness("anthropic", "claude-haiku-5-5");
    contextEconomy(h.pi, { loadConfig: () => off });
    await turnEnd(h, 95_000);
    expect(h.status.at(-1)).not.toContain("cliff");
  });
});

describe("model-failover advisory", () => {
  test("ok level -> undefined", () => {
    expect(buildFailoverAdvice(1000, "anthropic/claude-sonnet-5-5", routing, config)).toBeUndefined();
  });
  test("no candidates -> undefined (nothing candidate-specific to say)", () => {
    expect(buildFailoverAdvice(95_000, "anthropic/claude-haiku-5-5x-unknown", routing, config)).toBeUndefined();
    expect(buildFailoverAdvice(95_000, "anthropic/claude-sonnet-5-5", undefined, config)).toBeUndefined();
  });
  test("candidate whose cliff <= current tokens is flagged; roomy candidate is not", () => {
    const a = buildFailoverAdvice(160_000, "anthropic/claude-sonnet-5-5", routing, config)!;
    expect(a.level).toBe("warn");
    expect(a.message).toContain("anthropic/claude-haiku-5-5 (cliff 90000 <= 現在 160000");
    expect(a.message).toContain("openai/gpt-6.2-sol (cliff 250000: 余裕あり)");
    expect(a.message).toContain("12.5x");
    expect(a.message).toContain("自動切替はしません");
  });
  test("exceeded wording at 100%", () => {
    const a = buildFailoverAdvice(180_000, "anthropic/claude-sonnet-5-5", routing, config)!;
    expect(a.level).toBe("exceeded");
    expect(a.message).toContain("Pricing Cliff 到達");
  });
  test("turn_end: notifies once per (model, level), never calls setModel/compact", async () => {
    const h = harness("anthropic", "claude-sonnet-5-5");
    modelFailover(h.pi, { loadConfig: () => config, loadRouting: () => routing });
    await turnEnd(h, 10_000);
    expect(h.notes).toHaveLength(0);
    await turnEnd(h, 160_000);
    await turnEnd(h, 161_000);
    expect(h.notes).toHaveLength(1);
    await turnEnd(h, 180_000);
    expect(h.notes).toHaveLength(2);
    await turnEnd(h, 181_000);
    expect(h.notes).toHaveLength(2);
    expect(h.sideEffects).toEqual([]);
  });
  test("onlineContextCompact kill switch alone does not silence the failover advisory", async () => {
    const killed: SolPiConfig = { ...config, onlineContextCompactConfig: { ...config.onlineContextCompactConfig, enabled: false } };
    const h = harness("anthropic", "claude-sonnet-5-5");
    modelFailover(h.pi, { loadConfig: () => killed, loadRouting: () => routing });
    await turnEnd(h, 500_000);
    expect(h.notes.length).toBeGreaterThan(0);
  });
  test("disabled pricingCliffAdvisory -> failover advisory is silent", async () => {
    const off: SolPiConfig = { ...config, pricingCliffAdvisoryConfig: { enabled: false } };
    const h = harness("anthropic", "claude-sonnet-5-5");
    modelFailover(h.pi, { loadConfig: () => off, loadRouting: () => routing });
    await turnEnd(h, 500_000);
    expect(h.notes).toEqual([]);
  });
  test("turn_end handler never invokes setModel even for an exceeded context (explicit spy)", async () => {
    const h = harness("anthropic", "claude-sonnet-5-5");
    modelFailover(h.pi, { loadConfig: () => config, loadRouting: () => routing });
    await turnEnd(h, 500_000);
    expect(h.sideEffects).not.toContain("setModel");
    expect(h.sideEffects).not.toContain("ctx.compact");
  });
});

describe("no duplicate notifications across sol-pi / context-economy / model-failover", () => {
  test("one 85% crossing = exactly one SoL-Pi toast + one failover toast + zero economy toasts; repeats are silent", async () => {
    const h = harness("anthropic", "claude-sonnet-5-5");
    registerSolPi(h.pi, () => config);
    contextEconomy(h.pi, { loadConfig: () => config });
    modelFailover(h.pi, { loadConfig: () => config, loadRouting: () => routing });
    await turnEnd(h, 160_000);
    const sol = h.notes.filter((n) => n.msg.startsWith("[SoL-Pi]"));
    const fo = h.notes.filter((n) => n.msg.startsWith("[model-failover]"));
    expect(sol).toHaveLength(1);
    expect(fo).toHaveLength(1);
    expect(h.notes).toHaveLength(2);
    expect(fo[0].msg).not.toContain("recommend compacting");
    await turnEnd(h, 161_000);
    expect(h.notes).toHaveLength(2);
    expect(h.sideEffects).toEqual([]);
  });
});
