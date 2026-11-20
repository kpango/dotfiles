/**
 * Tests for SoL-Pi runtime enforcement core (arXiv:2609.20519).
 * Action Fusion / ObservationPack / Evidence-Preserving Reducer / Pricing Cliff.
 */
import { describe, expect, test, beforeAll, afterAll } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  netnsAvailable,
  loadSolPiConfig,
  runActionFusionValidator,
  detectEditThenBash,
  packObservation,
  selectObservationReplay,
  reduceEvidencePreserving,
  verifyQuotesInRawLog,
  redactSecrets,
  evaluateOnlineCompaction,
  pricingCliffFor,
  setPricingCliffCatalog,
  isBuildDefinitionFile,
  resolveArchiveDir,
  goValidatorEnv,
} from "./sol-pi-core";

let tmp: string;
beforeAll(() => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sol-pi-test-"));
});
afterAll(() => {
  fs.rmSync(tmp, { recursive: true, force: true });
});

describe("loadSolPiConfig", () => {
  test("reads thresholds from the shipped sol-pi.json", () => {
    const c = loadSolPiConfig();
    expect(c.observationPackConfig.minBytesThreshold).toBe(10240);
    expect(c.observationPackConfig.fullReplayTurns).toBe(2);
    expect(c.observationPackConfig.archiveDir).toBe("/tmp/omp-obs-pack");
    expect(c.evidencePreservingReducerConfig.minBytesThreshold).toBe(4096);
    expect(c.evidencePreservingReducerConfig.failClosedOnQuoteMismatch).toBe(true);
    expect(c.cacheWriteReadRatio).toBe(12.5);
  });
  test("falls back to defaults on missing/invalid file", () => {
    const bad = path.join(tmp, "bad.json");
    fs.writeFileSync(bad, "{not json");
    for (const p of [bad, path.join(tmp, "nope.json")]) {
      const c = loadSolPiConfig(p);
      expect(c.observationPackConfig.minBytesThreshold).toBe(10240);
      expect(c.evidencePreservingReducerConfig.minBytesThreshold).toBe(4096);
    }
  });
});

describe("Action Fusion", () => {
  test("invalid json fails, valid json passes", async () => {
    const good = path.join(tmp, "good.json");
    const badf = path.join(tmp, "bad2.json");
    fs.writeFileSync(good, '{"a":1}');
    fs.writeFileSync(badf, '{"a":');
    const g = await runActionFusionValidator(good, tmp);
    expect(g.ran).toBe(true);
    expect(g.ok).toBe(true);
    const b = await runActionFusionValidator(badf, tmp);
    expect(b.ran).toBe(true);
    expect(b.ok).toBe(false);
    expect(b.output.length).toBeGreaterThan(0);
  });
  test("bash -n catches shell syntax errors", async () => {
    const f = path.join(tmp, "bad.sh");
    fs.writeFileSync(f, "if then fi (\n");
    expect((await runActionFusionValidator(f, tmp)).ok).toBe(false);
  });
  test("unknown extension is skipped", async () => {
    const f = path.join(tmp, "a.txt");
    fs.writeFileSync(f, "x");
    const r = await runActionFusionValidator(f, tmp);
    expect(r.ran).toBe(false);
    expect(r.reason).toBe("no-validator");
  });
  test("path outside cwd is rejected without executing", async () => {
    const outside = path.join(os.tmpdir(), "sol-pi-outside.json");
    const r = await runActionFusionValidator(outside, tmp);
    expect(r.ran).toBe(false);
    expect(r.reason).toBe("path-outside-cwd");
    const r2 = await runActionFusionValidator("../../etc/passwd.json", tmp);
    expect(r2.reason).toBe("path-outside-cwd");
  });
  test("no shell interpolation of filenames", async () => {
    const marker = path.join(tmp, "pwned");
    const f = path.join(tmp, "x;touch pwned;.json");
    fs.writeFileSync(f, "{}");
    await runActionFusionValidator(f, tmp);
    expect(fs.existsSync(marker)).toBe(false);
  });
  test("timeout is enforced", async () => {
    const f = path.join(tmp, "slow.slow");
    fs.writeFileSync(f, "sleep 5\n");
    const cfg = loadSolPiConfig();
    cfg.actionFusionConfig.timeoutMs = 200;
    cfg.actionFusionConfig.defaultValidators[".slow"] = "bash {file}";
    const start = Date.now();
    const r = await runActionFusionValidator(f, tmp, cfg);
    expect(r.timedOut).toBe(true);
    expect(r.ok).toBe(false);
    expect(Date.now() - start).toBeLessThan(3000);
  });
  test("detects Edit -> Bash separation anti-pattern", () => {
    expect(detectEditThenBash(["read", "edit", "bash"])).toBe(true);
    expect(detectEditThenBash(["write", "bash"])).toBe(true);
    expect(detectEditThenBash(["ast_edit", "bash"])).toBe(true);
    expect(detectEditThenBash(["edit", "read", "bash"])).toBe(false);
    expect(detectEditThenBash(["bash", "edit"])).toBe(false);
    expect(detectEditThenBash([])).toBe(false);
  });
});

describe("ObservationPack", () => {
  const cfgFor = () => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = path.join(tmp, "obs");
    return c;
  };
  test("small output is not packed", () => {
    const r = packObservation("bash", "hello", 1, cfgFor());
    expect(r.packed).toBe(false);
    expect(r.text).toBe("hello");
  });
  test("exactly 10240 bytes is not packed, 10241 is", () => {
    expect(packObservation("bash", "a".repeat(10240), 1, cfgFor()).packed).toBe(false);
    expect(packObservation("bash", "a".repeat(10241), 1, cfgFor()).packed).toBe(true);
  });
  test("large output archived to disk with handle and head/tail excerpt", () => {
    const lines = Array.from({ length: 1000 }, (_, i) => `line-${i} ${"x".repeat(20)}`);
    const out = lines.join("\n");
    const r = packObservation("bash", out, 3, cfgFor());
    expect(r.packed).toBe(true);
    expect(r.handle).toMatch(/^#obs_[0-9a-f]{12}$/);
    expect(fs.readFileSync(r.archivePath!, "utf-8")).toBe(out);
    expect(r.compactText).toContain(r.handle!);
    expect(r.compactText).toContain("line-0");
    expect(r.compactText).toContain("line-19");
    expect(r.compactText).not.toContain("line-20 ");
    expect(r.compactText).toContain("line-999");
    expect(r.compactText).toContain("line-985");
    expect(r.compactText).not.toContain("line-984 ");
    expect(r.compactText!.length).toBeLessThan(out.length / 5);
  });
  test("full text is replayed for 2 turns, then compact", () => {
    const cfg = cfgFor();
    const out = Array.from({ length: 1000 }, (_, i) => `row-${i} ${"x".repeat(20)}`).join("\n");
    const r = packObservation("bash", out, 5, cfg);
    expect(selectObservationReplay(r, 5, cfg)).toBe(out);
    expect(selectObservationReplay(r, 6, cfg)).toBe(out);
    expect(selectObservationReplay(r, 7, cfg)).toBe(r.compactText!);
    expect(selectObservationReplay(r, 20, cfg)).toBe(r.compactText!);
  });
});

describe("Evidence-Preserving Reducer", () => {
  const cfg = () => loadSolPiConfig();
  const bigLog = () =>
    [
      ...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`),
      "--- FAIL: TestFoo (0.00s)",
      "    foo_test.go:42: expected 1, got 2",
      "FAIL\tgithub.com/x/y/pkg\t0.02s",
      "src/main.rs:17:5: error[E0308]: mismatched types",
    ].join("\n");

  test("small logs pass through (masked) unreduced", () => {
    const r = reduceEvidencePreserving("go test", "token=abc123 ok", 0, cfg());
    expect(r.reduced).toBe(false);
    expect(r.text).not.toContain("abc123");
  });
  test("large failing log extracts exit code, failed tests, file:line, quotes", () => {
    const log = bigLog();
    expect(Buffer.byteLength(log)).toBeGreaterThan(4096);
    const r = reduceEvidencePreserving("go test ./...", log, 1, cfg());
    expect(r.reduced).toBe(true);
    expect(r.fallback).toBe(false);
    expect(r.exitCode).toBe(1);
    expect(r.failedTests).toContain("TestFoo");
    expect(r.locations).toContain("foo_test.go:42");
    expect(r.locations).toContain("src/main.rs:17");
    expect(r.text).toContain("exit code: 1");
    expect(r.text).toContain("--- FAIL: TestFoo");
    expect(r.text.length).toBeLessThan(log.length / 2);
    expect(verifyQuotesInRawLog(r.quotes, log)).toBe(true);
  });
  test("fabricated candidate quote -> fail closed to deterministic raw excerpt", () => {
    const log = bigLog();
    const r = reduceEvidencePreserving("go test", log, 1, cfg(), {
      quotes: ["--- FAIL: TestFoo (0.00s)", "panic: this never happened"],
    });
    expect(r.fallback).toBe(true);
    expect(r.reason).toBe("quote-mismatch");
    expect(r.text).not.toContain("this never happened");
    expect(r.text).toContain("FAIL\tgithub.com/x/y/pkg");
    expect(r.text).toContain("exit code: 1");
  });
  test("genuine candidate quotes are accepted", () => {
    const log = bigLog();
    const r = reduceEvidencePreserving("go test", log, 1, cfg(), {
      quotes: ["    foo_test.go:42: expected 1, got 2"],
    });
    expect(r.fallback).toBe(false);
    expect(r.quotes).toContain("    foo_test.go:42: expected 1, got 2");
  });
  test("fabricated quote is tolerated when failClosed disabled", () => {
    const c = cfg();
    c.evidencePreservingReducerConfig.failClosedOnQuoteMismatch = false;
    const r = reduceEvidencePreserving("go test", bigLog(), 1, c, { quotes: ["nope-not-there"] });
    expect(r.fallback).toBe(false);
    expect(r.quotes).not.toContain("nope-not-there");
  });
  test("secrets are masked in reduced and fallback output", () => {
    const log =
      "Authorization: Bearer sk-ABCDEFGHIJKLMNOPQRSTUV\n" +
      "password=hunter2\nAPI_KEY: ghp_abcdefghijklmnopqrstuvwxyz0123456789\n" +
      "--- FAIL: TestSecret (0.00s)\n    s_test.go:9: token=zzz999 leaked\n" +
      "x".repeat(5000);
    for (const cand of [undefined, { quotes: ["bogus"] }]) {
      const r = reduceEvidencePreserving("go test", log, 1, cfg(), cand);
      for (const s of ["hunter2", "zzz999", "sk-ABCDEFGHIJKLMNOPQRSTUV", "ghp_abcdefghijklmnopqrstuvwxyz0123456789"]) {
        expect(r.text).not.toContain(s);
      }
    }
  });
  test("verifyQuotesInRawLog requires exact substrings", () => {
    expect(verifyQuotesInRawLog(["abc"], "xxabcxx")).toBe(true);
    expect(verifyQuotesInRawLog(["abd"], "xxabcxx")).toBe(false);
    expect(verifyQuotesInRawLog([""], "xx")).toBe(false);
    expect(verifyQuotesInRawLog([], "xx")).toBe(true);
  });
  test("redactSecrets masks common patterns, keeps ordinary text", () => {
    expect(redactSecrets("secret: abc")).not.toContain("abc");
    expect(redactSecrets("AKIAABCDEFGHIJKLMNOP")).not.toContain("AKIAABCDEFGHIJKLMNOP");
    expect(redactSecrets("hello world")).toBe("hello world");
  });
});

describe("Online compaction / Pricing Cliff", () => {
  test("Haiku 5.5 cliff at 90000", () => {
    const m = "anthropic/claude-haiku-5-5";
    expect(evaluateOnlineCompaction(50000, m, 12.5).level).toBe("ok");
    const w = evaluateOnlineCompaction(76500, m, 12.5);
    expect(w.level).toBe("warn");
    expect(w.cliff).toBe(90000);
    expect(w.shouldCompact).toBe(false);
    const e = evaluateOnlineCompaction(90001, m, 12.5);
    expect(e.level).toBe("exceeded");
    expect(e.shouldCompact).toBe(true);
    expect(e.message).toContain("12.5");
  });
  test("boundary: reaching the cliff (>=) is exceeded; just below is warn", () => {
    expect(evaluateOnlineCompaction(90000, "claude-haiku-5.5", 12.5).level).toBe("exceeded");
    expect(evaluateOnlineCompaction(89999, "claude-haiku-5.5", 12.5).level).toBe("warn");
    expect(evaluateOnlineCompaction(76499, "claude-haiku-5.5", 12.5).level).toBe("ok");
  });
  test("GPT-6.2 cliff at 250000", () => {
    const r = evaluateOnlineCompaction(240000, "openai/gpt-6.2-sol", 12.5);
    expect(r.cliff).toBe(250000);
    expect(r.level).toBe("warn");
    expect(evaluateOnlineCompaction(250001, "openai/gpt-6.2-sol", 12.5).level).toBe("exceeded");
  });
  test("unknown model uses 180000 default", () => {
    const r = evaluateOnlineCompaction(100000, "some/other-model", 12.5);
    expect(r.cliff).toBe(180000);
    expect(r.level).toBe("ok");
    expect(evaluateOnlineCompaction(180000, "some/other-model", 12.5).level).toBe("exceeded");
  });
  test("returns a recommendation only (pure, no side effects)", () => {
    const r = evaluateOnlineCompaction(999999, "claude-haiku-5-5", 12.5);
    expect(typeof r.shouldCompact).toBe("boolean");
    expect(r.autoApply).toBe(false);
  });
});

// ===========================================================================
// Attempt 2: hardening tests
// ===========================================================================
const sleepMs = (ms: number) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
const bytes = (s: string) => Buffer.byteLength(s);

describe("redactSecrets (extended)", () => {
  const cases: [string, string, string][] = [
    ["json password with spaces", '{"password": "my secret pass phrase"}', "my secret pass phrase"],
    ["json api_key single quote", "{'api_key': 'abc def'}", "abc def"],
    ["quoted spaced value", 'api_key = "abc def ghi"', "abc def ghi"],
    ["Authorization Basic", "Authorization: Basic dXNlcjpwYXNzd29yZA==", "dXNlcjpwYXNzd29yZA=="],
    ["Authorization Bearer", "Authorization: Bearer abcdef123456", "abcdef123456"],
    ["Authorization token scheme", "authorization: token ghx_abc123456789", "ghx_abc123456789"],
    ["url credentials", "git clone https://user:pa55w0rd@example.com/x.git", "pa55w0rd"],
    ["github_pat", "x github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz y", "github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz"],
    ["glpat", "glpat-abcdefghij0123456789", "glpat-abcdefghij0123456789"],
    ["npm token", "npm_" + "a1B2c3D4e5".repeat(4), "a1B2c3D4e5a1B2c3D4e5"],
    ["google api key", "AIza" + "SyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q", "SyA1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q"],
    ["JWT", "t=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abcDEF123_-xyz", "eyJzdWIiOiIxMjM0NTY3ODkwIn0"],
    ["ASIA", "ASIAABCDEFGHIJKLMNOP", "ASIAABCDEFGHIJKLMNOP"],
    ["AKIA", "AKIAABCDEFGHIJKLMNOP", "AKIAABCDEFGHIJKLMNOP"],
    [
      "PEM",
      "-----BEGIN RSA PRIVATE KEY-----\nMIIEowIBAAKCAQEAxyz\nABCDEF\n-----END RSA PRIVATE KEY-----",
      "MIIEowIBAAKCAQEAxyz",
    ],
  ];
  for (const [name, input, secret] of cases) {
    test(`masks ${name}`, () => {
      const out = redactSecrets(`before ${input} after`);
      expect(out).not.toContain(secret);
      expect(out).toContain("before");
    });
  }
  test("Authorization scheme word is also removed", () => {
    expect(redactSecrets("Authorization: Basic dXNlcjpwYXNz")).not.toContain("Basic");
  });
  test("host part of credential URL survives", () => {
    expect(redactSecrets("https://user:pw@example.com/x")).toContain("example.com");
  });
});

describe("loadSolPiConfig (hardening)", () => {
  test("top-level boolean flags disable nested configs", () => {
    const f = path.join(tmp, "flags.json");
    fs.writeFileSync(
      f,
      JSON.stringify({
        actionFusion: false,
        observationPack: false,
        evidencePreservingReducer: false,
        onlineContextCompact: false,
        pricingCliffAdvisory: false,
        pricingCliffAdvisoryConfig: { enabled: true },
        actionFusionConfig: { enabled: true },
        observationPackConfig: { enabled: true },
        evidencePreservingReducerConfig: { enabled: true },
        onlineContextCompactConfig: { enabled: true },
      }),
    );
    const c = loadSolPiConfig(f);
    expect(c.actionFusionConfig.enabled).toBe(false);
    expect(c.observationPackConfig.enabled).toBe(false);
    expect(c.evidencePreservingReducerConfig.enabled).toBe(false);
    expect(c.onlineContextCompactConfig.enabled).toBe(false);
    expect(c.pricingCliffAdvisoryConfig.enabled).toBe(false);
    expect(packObservation("bash", "x".repeat(20000), 1, c).packed).toBe(false);
  });
  test("prototype-pollution keys are ignored", () => {
    const f = path.join(tmp, "proto.json");
    fs.writeFileSync(f, '{"__proto__":{"polluted":true},"constructor":{"prototype":{"polluted2":true}},"observationPackConfig":{"__proto__":{"polluted3":true},"headLines":7}}');
    const c = loadSolPiConfig(f);
    expect(({} as any).polluted).toBeUndefined();
    expect(({} as any).polluted2).toBeUndefined();
    expect(({} as any).polluted3).toBeUndefined();
    expect(Object.keys(c)).not.toContain("__proto__");
    expect(c.observationPackConfig.headLines).toBe(7);
  });
  test("parse error warns (once per message); missing file is silent", () => {
    const f = path.join(tmp, "broken.json");
    fs.writeFileSync(f, "{oops");
    const warns: string[] = [];
    loadSolPiConfig(f, (m) => warns.push(m));
    expect(warns.length).toBe(1);
    expect(warns[0]).toContain("broken.json");
    const w2: string[] = [];
    loadSolPiConfig(path.join(tmp, "absent.json"), (m) => w2.push(m));
    expect(w2.length).toBe(0);
  });
  test("custom validators can be added; shipped python validators use -I", () => {
    const f = path.join(tmp, "vals.json");
    fs.writeFileSync(f, '{"actionFusionConfig":{"defaultValidators":{".zz":"true"}}}');
    const c = loadSolPiConfig(f);
    expect(c.actionFusionConfig.defaultValidators[".zz"]).toBe("true");
    expect(c.actionFusionConfig.defaultValidators[".json"]).toContain("python3");
    const shipped = loadSolPiConfig();
    expect(shipped.actionFusionConfig.defaultValidators[".py"]).toContain(" -I ");
    expect(shipped.actionFusionConfig.defaultValidators[".json"]).toContain(" -I ");
  });
});

describe("Action Fusion (hardening)", () => {
  test("python runs isolated (-I): cwd json.py shadow module is not imported", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "iso-"));
    fs.writeFileSync(path.join(d, "json.py"), `open(${JSON.stringify(path.join(d, "pwned"))}, "w").write("x")\n`);
    fs.writeFileSync(path.join(d, "a.json"), "{}");
    const r = await runActionFusionValidator("a.json", d);
    expect(r.ran).toBe(true);
    expect(r.command).toContain("-I");
    expect(fs.existsSync(path.join(d, "pwned"))).toBe(false);
  });
  test("child env is allowlisted: secrets are not inherited, PATH works", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "env-"));
    fs.writeFileSync(path.join(d, "e.envcase"), `printf '%s' "$LEAK_TOKEN" > "${path.join(d, "leak.out")}"\nprintf '%s' "$ANTHROPIC_API_KEY" >> "${path.join(d, "leak.out")}"\n`);
    process.env.LEAK_TOKEN = "leaky-1";
    process.env.ANTHROPIC_API_KEY = "leaky-2";
    try {
      const cfg = loadSolPiConfig();
      cfg.actionFusionConfig.defaultValidators[".envcase"] = "bash {file}";
      const r = await runActionFusionValidator("e.envcase", d, cfg);
      expect(r.ran && r.ok).toBe(true);
      expect(fs.readFileSync(path.join(d, "leak.out"), "utf-8")).toBe("");
    } finally {
      delete process.env.LEAK_TOKEN;
      delete process.env.ANTHROPIC_API_KEY;
    }
  });
  test("timeout kills grandchildren (process group)", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "grp-"));
    const pidFile = path.join(d, "gc.pid");
    fs.writeFileSync(path.join(d, "g.grp"), `sleep 29 &\necho $! > "${pidFile}"\nwait\n`);
    const cfg = loadSolPiConfig();
    cfg.actionFusionConfig.timeoutMs = 300;
    cfg.actionFusionConfig.defaultValidators[".grp"] = "bash {file}";
    const r = await runActionFusionValidator("g.grp", d, cfg);
    expect(r.timedOut).toBe(true);
    const pid = Number(fs.readFileSync(pidFile, "utf-8").trim());
    sleepMs(300);
    let alive = true;
    try {
      process.kill(pid, 0);
    } catch {
      alive = false;
    }
    expect(alive).toBe(false);
  });
  test("a file named '..x.json' directly under cwd is inside cwd", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "dots-"));
    fs.writeFileSync(path.join(d, "..x.json"), "{}");
    expect((await runActionFusionValidator("..x.json", d)).ran).toBe(true);
  });
  test("symlink escaping cwd is rejected", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "lnk-"));
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), "sol-pi-out-"));
    try {
      fs.writeFileSync(path.join(outside, "o.json"), "{}");
      fs.symlinkSync(path.join(outside, "o.json"), path.join(d, "l.json"));
      expect((await runActionFusionValidator("l.json", d)).reason).toBe("path-outside-cwd");
    } finally {
      fs.rmSync(outside, { recursive: true, force: true });
    }
  });
  test(".go without go.mod is skipped with reason", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "nomod-"));
    fs.writeFileSync(path.join(d, "a.go"), "package a\n");
    const r = await runActionFusionValidator("a.go", d);
    expect(r.ran).toBe(false);
    expect(r.reason).toBe("no-go-mod");
  });
  test(".rs without Cargo.toml is skipped with reason", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "nocargo-"));
    fs.writeFileSync(path.join(d, "a.rs"), "fn main(){}\n");
    expect((await runActionFusionValidator("a.rs", d)).reason).toBe("no-cargo-toml");
  });
});

describe("ObservationPack (hardening)", () => {
  const cfgAt = (dir: string) => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = dir;
    return c;
  };
  test("compact text never exceeds raw size (single huge line / no newlines)", () => {
    for (const n of [10241, 20000, 200000, 300000]) {
      const raw = "y".repeat(n);
      const r = packObservation("bash", raw, 1, cfgAt(path.join(tmp, "caps")));
      expect(r.packed).toBe(true);
      expect(bytes(r.compactText!)).toBeLessThanOrEqual(n);
      expect(bytes(r.compactText!)).toBeLessThanOrEqual(8192);
    }
  });
  test("head and tail do not overlap on short-ish logs", () => {
    const lines = Array.from({ length: 30 }, (_, i) => `L${String(i).padStart(2, "0")}-${"z".repeat(400)}`);
    const r = packObservation("bash", lines.join("\n"), 1, cfgAt(path.join(tmp, "ovl")));
    expect(r.packed).toBe(true);
    for (let i = 0; i < 30; i++) {
      const tag = `L${String(i).padStart(2, "0")}-`;
      expect(r.compactText!.split(tag).length - 1).toBeLessThanOrEqual(1);
    }
  });
  test("multibyte long lines are cut without breaking characters", () => {
    const raw = Array.from({ length: 200 }, () => "あ".repeat(300)).join("\n");
    const r = packObservation("bash", raw, 1, cfgAt(path.join(tmp, "mb")));
    expect(r.compactText).not.toContain("�");
  });
  test("archive is masked, mode 0600, dir mode 0700", () => {
    const dir = path.join(tmp, "arch1");
    const raw = "password=hunter2\n" + "x".repeat(11000);
    const r = packObservation("bash", raw, 1, cfgAt(dir));
    const body = fs.readFileSync(r.archivePath!, "utf-8");
    expect(body).not.toContain("hunter2");
    expect(fs.statSync(r.archivePath!).mode & 0o777).toBe(0o600);
    expect(fs.statSync(dir).mode & 0o777).toBe(0o700);
  });
  test("identical output reuses the existing safe archive file (no growth)", () => {
    const dir = path.join(tmp, "arch2");
    const c = cfgAt(dir);
    const raw = "q".repeat(11000);
    const a = packObservation("bash", raw, 1, c);
    const b = packObservation("bash", raw, 2, c);
    expect(b.archivePath).toBe(a.archivePath);
    expect(fs.readdirSync(dir).length).toBe(1);
  });
  test("symlinked archive dir is refused", () => {
    const real = fs.mkdtempSync(path.join(tmp, "real-"));
    fs.chmodSync(real, 0o700);
    const link = path.join(tmp, "linkdir");
    fs.symlinkSync(real, link);
    expect(() => packObservation("bash", "x".repeat(11000), 1, cfgAt(link))).toThrow(/symlink/i);
    expect(fs.readdirSync(real).length).toBe(0);
  });
  test("archive dir with loose mode is refused", () => {
    const d = path.join(tmp, "loose");
    fs.mkdirSync(d, { mode: 0o755 });
    fs.chmodSync(d, 0o755);
    expect(() => packObservation("bash", "x".repeat(11000), 1, cfgAt(d))).toThrow(/mode/i);
  });
  test("default archiveDir resolves under XDG_RUNTIME_DIR when available", () => {
    const xdg = fs.mkdtempSync(path.join(tmp, "xdg-"));
    const prev = process.env.XDG_RUNTIME_DIR;
    process.env.XDG_RUNTIME_DIR = xdg;
    try {
      expect(resolveArchiveDir(loadSolPiConfig())).toBe(path.join(xdg, "omp-obs-pack"));
    } finally {
      if (prev === undefined) delete process.env.XDG_RUNTIME_DIR;
      else process.env.XDG_RUNTIME_DIR = prev;
    }
  });
  test("without XDG_RUNTIME_DIR falls back to per-uid dir under os.tmpdir()", () => {
    const prev = process.env.XDG_RUNTIME_DIR;
    delete process.env.XDG_RUNTIME_DIR;
    try {
      expect(resolveArchiveDir(loadSolPiConfig())).toBe(path.join(os.tmpdir(), `omp-obs-pack-${process.getuid!()}`));
    } finally {
      if (prev !== undefined) process.env.XDG_RUNTIME_DIR = prev;
    }
  });
});

describe("Evidence-Preserving Reducer (hardening)", () => {
  const cfg = () => loadSolPiConfig();
  const failTail = [
    "--- FAIL: TestX (0.00s)",
    "    x_test.go:9: token=zzz999 leaked into assertion",
    "FAIL\tgithub.com/x/y\t0.01s",
  ];
  const padded = (n: number) => Array.from({ length: n }, (_, i) => `ok   pkg/p${i}\t0.01s`);

  test("returned quotes/failedTests/locations are masked, verification happens pre-mask", () => {
    const log = [...padded(300), ...failTail].join("\n");
    const r = reduceEvidencePreserving("go test", log, 1, cfg());
    expect(r.fallback).toBe(false);
    expect(r.quotes.join("\n")).not.toContain("zzz999");
    expect(r.locations.join("\n")).not.toContain("zzz999");
    expect(r.text).not.toContain("zzz999");
    expect(r.quotes.some((q) => q.includes("x_test.go:9"))).toBe(true);
    // pre-mask quotes are substrings of the raw log; masked ones intentionally are not
    expect(verifyQuotesInRawLog(r.quotes, log)).toBe(false);
  });
  test("secret inside a failed test name is masked", () => {
    const log = [...padded(300), "--- FAIL: Test_password=hunter2 (0.00s)"].join("\n");
    const r = reduceEvidencePreserving("go test", log, 1, cfg());
    expect(r.failedTests.join(",")).not.toContain("hunter2");
  });
  test("multibyte truncation at maxInputBytes does not corrupt quotes", () => {
    const c = cfg();
    c.evidencePreservingReducerConfig.maxInputBytes = 4200;
    const log = [...Array.from({ length: 400 }, () => "あ".repeat(10)), "--- FAIL: TestMB (0.00s)", "    mb_test.go:3: boom"].join("\n");
    for (let shift = 0; shift < 3; shift++) {
      const r = reduceEvidencePreserving("go test", "a".repeat(shift) + "\n" + log, 1, c);
      expect(r.text).not.toContain("�");
      expect(r.fallback).toBe(false);
      expect(r.failedTests).toContain("TestMB");
    }
  });
  test("byte caps: reduced/fallback text never exceeds raw size", () => {
    const hugeFail = "FAIL " + "x".repeat(200000);
    const a = reduceEvidencePreserving("make", hugeFail, 1, cfg());
    expect(bytes(a.text)).toBeLessThanOrEqual(bytes(hugeFail));
    expect(bytes(a.text)).toBeLessThanOrEqual(8192);
    const noNl = "z".repeat(300000);
    const b = reduceEvidencePreserving("make", noNl, 1, cfg());
    expect(b.fallback).toBe(true);
    expect(bytes(b.text)).toBeLessThanOrEqual(bytes(noNl));
    const small = "z".repeat(5000);
    expect(bytes(reduceEvidencePreserving("make", small, 1, cfg()).text)).toBeLessThanOrEqual(5000);
  });
  test("fallback head/tail use configured line counts without overlap", () => {
    const c = cfg();
    c.observationPackConfig.headLines = 3;
    c.observationPackConfig.tailLines = 2;
    const lines = Array.from({ length: 200 }, (_, i) => `R${String(i).padStart(3, "0")} ${"w".repeat(40)}`);
    const r = reduceEvidencePreserving("make", lines.join("\n"), 2, c);
    expect(r.reason).toBe("no-failure-lines");
    expect(r.fallback).toBe(true);
    expect(r.text).toContain("R000");
    expect(r.text).toContain("R002");
    expect(r.text).not.toContain("R003");
    expect(r.text).toContain("R199");
    expect(r.text).toContain("R198");
    expect(r.text).not.toContain("R197");
  });
  test("'0 failed' on a successful run is not a failure line", () => {
    const log = [...padded(300), "=== 12 passed, 0 failed in 1.2s ==="].join("\n");
    const r = reduceEvidencePreserving("pytest", log, 0, cfg());
    expect(r.quotes.length).toBe(0);
    expect(r.fallback).toBe(false);
    expect(r.text).toContain("exit code: 0");
  });
  test("non-zero exit with zero failure lines falls back (verifyExitCode)", () => {
    const r = reduceEvidencePreserving("make", padded(300).join("\n"), 2, cfg());
    expect(r.fallback).toBe(true);
    expect(r.reason).toBe("no-failure-lines");
    expect(r.text).toContain("exit code: 2");
  });
  test("pathological location-like line finishes quickly", () => {
    const log = [...padded(300), "FAIL " + "a.".repeat(100000) + ":1"].join("\n");
    const t = Date.now();
    reduceEvidencePreserving("make", log, 1, cfg());
    expect(Date.now() - t).toBeLessThan(1000);
  });
  test("whitespace-only candidate quote fails closed", () => {
    const log = [...padded(300), ...failTail].join("\n");
    const r = reduceEvidencePreserving("go test", log, 1, cfg(), { quotes: ["   "] });
    expect(r.fallback).toBe(true);
    expect(r.reason).toBe("quote-mismatch");
  });
  test("fail-closed output still masks secrets and carries exit code", () => {
    const log = [...padded(300), ...failTail].join("\n");
    const r = reduceEvidencePreserving("go test", log, 1, cfg(), { quotes: ["not in log"] });
    expect(r.text).not.toContain("zzz999");
    expect(r.text).toContain("exit code: 1");
  });
});

describe("Pricing Cliff patterns are anchored", () => {
  test("haiku-5-50 / gpt-6.20 do not match the 5.5 / 6.2 cliffs", () => {
    expect(evaluateOnlineCompaction(1, "claude-haiku-5-50", 12.5).cliff).toBe(180000);
    expect(evaluateOnlineCompaction(1, "openai/gpt-6.20", 12.5).cliff).toBe(180000);
    expect(evaluateOnlineCompaction(1, "xhaiku-5-5", 12.5).cliff).toBe(180000);
    expect(evaluateOnlineCompaction(1, "anthropic/claude-haiku-5-5-20261101", 12.5).cliff).toBe(90000);
    expect(evaluateOnlineCompaction(1, "openai/gpt-6.2-mini", 12.5).cliff).toBe(180000); // not a catalog model: default fallback
    expect(evaluateOnlineCompaction(1, "openai/gpt-6.2-astra-20261101", 12.5).cliff).toBe(250000);
  });
});

// ===========================================================================
// Attempt 3: masking order, linear time, anchoring, exit codes, archive limits,
// and the extension wiring (mock pi)
// ===========================================================================
import {
  archiveObservation,
  isBuildOrTestCommand,
  reduceAndArchive,
  resolveExitCode,
  parseThenRun,
  runThenRun,
} from "./sol-pi-core";
import { register, textSlots } from "../sol-pi";

const timed = (fn: () => unknown): number => {
  const t = performance.now();
  fn();
  return performance.now() - t;
};
const ms = (s: string) => Buffer.byteLength(s);
const bigFail = () =>
  [
    ...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`),
    "--- FAIL: TestFoo (0.00s)",
    "    foo_test.go:42: expected 1, got 2",
    "FAIL\tgithub.com/x/y/pkg\t0.02s",
  ].join("\n");
const bigPlain = () => Array.from({ length: 400 }, (_, i) => `row ${i} ${"x".repeat(30)}`).join("\n");

describe("redaction: prefixes glued to words, PGP, extra formats", () => {
  const glued: [string, string][] = [
    ["sk-", "Xsk-ABCDEFGHIJKLMNOPQRSTUV123"],
    ["ghp_", "Xghp_abcdefghijklmnopqrstuvwxyz0123456789"],
    ["AKIA", "XAKIAABCDEFGHIJKLMNOP"],
    ["ASIA", "yASIAABCDEFGHIJKLMNOP"],
    ["xoxb", "Zxo" + "xb-1234567890-abcdefghij"],
    ["glpat", "Qglpat-abcdefghij0123456789"],
    ["github_pat", "Ygithub_pat_11ABCDEFG0123456789_abcdefghijkl"],
  ];
  for (const [name, input] of glued) {
    test(`masks ${name} even when glued to a preceding word character`, () => {
      const secret = input.slice(1);
      expect(redactSecrets(`val ${input} end`)).not.toContain(secret.slice(4));
    });
  }
  test("glued token in a failed test name never reaches failedTests/quotes/text", () => {
    const log = [...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`), "--- FAIL: TestSksk-ABCDEFGHIJKLMNOPQRSTUV123 (0.00s)"].join("\n");
    const r = reduceEvidencePreserving("go test", log, 1, loadSolPiConfig());
    for (const s of [r.text, r.failedTests.join(","), r.quotes.join("\n")]) expect(s).not.toContain("ABCDEFGHIJKLMNOPQRSTUV123");
    expect(r.fallback).toBe(false);
  });
  test("PGP private key block (multi-line) is masked and surrounding text kept", () => {
    const out = redactSecrets("a\n-----BEGIN PGP PRIVATE KEY BLOCK-----\nlQOYBFsecretbody\nmore\n-----END PGP PRIVATE KEY BLOCK-----\nb");
    expect(out).not.toContain("lQOYBFsecretbody");
    expect(out).not.toContain("more");
    expect(out.startsWith("a\n")).toBe(true);
    expect(out.endsWith("\nb")).toBe(true);
    expect(out).toContain("REDACTED PRIVATE KEY");
  });
  test("unterminated private key block drops everything after BEGIN", () => {
    const out = redactSecrets("x\n-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAB3Nza\nBBBB");
    expect(out).not.toContain("AAAAB3Nza");
    expect(out).not.toContain("BBBB");
  });
  const extra: [string, string, string][] = [
    ["empty-user url", "redis://:pw1234@host:6379", "pw1234"],
    ["@ in password", "https://user:p@ss@host.example/x", "p@ss"],
    ["pwd=", "connect pwd=s3cr3tvalue now", "s3cr3tvalue"],
    ["sk_live", "k sk_live_abcdefghij1234567890", "abcdefghij1234567890"],
    ["rk_live", "k rk_live_abcdefghij1234567890", "abcdefghij1234567890"],
    ["sendgrid", "k SG.abcdefghijklmnop12.abcdefghijklmnop34", "abcdefghijklmnop12"],
    ["ya29", "t ya29.a0AbCdEfGhIjKlMnOpQrStUv", "a0AbCdEfGhIjKlMnOpQrStUv"],
    ["hf_", "t hf_" + "AbCdEfGhIj".repeat(4), "AbCdEfGhIjAbCdEfGhIj"],
    ["curl -u", "curl -u admin:hunter22 https://x", "hunter22"],
    ["--password flag", "mysql --password hunter23", "hunter23"],
    ["Cookie header", "Cookie: sessionid=abc123def456; theme=dark", "abc123def456"],
    ["Set-Cookie header", "Set-Cookie: sid=zzz987yyy; Path=/", "zzz987yyy"],
    ["X-Amz-Signature", "https://b.s3/x?X-Amz-Signature=deadbeef1234&a=1", "deadbeef1234"],
    ["escaped quote value", 'password="ab\\"cd efgh"', "cd efgh"],
    ["quoted Authorization", 'Authorization: "Bearer abc def"', "abc def"],
  ];
  for (const [name, input, secret] of extra) {
    test(`masks ${name}`, () => {
      const out = redactSecrets(input);
      expect(out).not.toContain(secret);
    });
  }
  test("a line longer than the cap is cut (with marker) before masking; nothing past the cap leaks", () => {
    const out = redactSecrets("a ".repeat(3000) + "ghp_abcdefghijklmnopqrstuvwxyz0123456789 tail");
    expect(out).not.toContain("ghp_");
    expect(out).toContain("truncated");
  });
  test("the head of a secret straddling the cut is not left behind", () => {
    const line = "a".repeat(4090) + "sk-ABCDEFGHIJKLMNOPQRSTUV";
    expect(redactSecrets(line)).not.toContain("sk-ABC");
  });
});

describe("redaction runs in linear time on adversarial 1 MB input", () => {
  const inputs: Record<string, string> = {
    "token-": "token-".repeat(175000),
    "eyJa.": "eyJa.".repeat(210000),
    "a.": "a.".repeat(525000),
    "password=\"": 'password="'.repeat(105000),
    "Bearer ": "Bearer ".repeat(150000),
    "-----BEGIN ": "-----BEGIN ".repeat(95000),
    "token- with newlines": ("token-".repeat(16) + "\n").repeat(10000),
    "eyJ run": "eyJ" + "a".repeat(1000000),
    "4000-char token- lines": ("token-".repeat(666) + "\n").repeat(250),
    "4000-char eyJa. lines": ("eyJa.".repeat(800) + "\n").repeat(250),
    "4000-char a. lines": ("a.".repeat(2000) + "\n").repeat(250),
    "4000-char unterminated quotes": ('password="'.repeat(400) + "\n").repeat(250),
  };
  for (const [name, input] of Object.entries(inputs)) {
    test(`redactSecrets(${name}) < 250ms`, () => {
      expect(timed(() => redactSecrets(input))).toBeLessThan(250);
    });
  }
  test("packObservation and reducer on adversarial input stay fast", () => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = path.join(tmp, "redos-arch");
    const adv = "token-".repeat(175000);
    expect(timed(() => packObservation("bash", adv, 1, c))).toBeLessThan(800);
    expect(timed(() => reduceEvidencePreserving("make", "FAIL " + "eyJa.".repeat(210000), 1, c))).toBeLessThan(800);
  });
});

describe("masking happens BEFORE the byte cut", () => {
  test("reducer quote: secret straddling the 512-byte line cap does not leak its head", () => {
    const secretLine = "FAIL " + "a".repeat(495) + " sk-ABCDEFGHIJKLMNOPQRSTUV1234";
    const log = [...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`), secretLine].join("\n");
    const r = reduceEvidencePreserving("go test", log, 1, loadSolPiConfig());
    expect(r.fallback).toBe(false);
    expect(r.quotes.join("\n")).not.toContain("sk-ABC");
    expect(r.text).not.toContain("sk-ABC");
  });
  test("pack compactText: secret straddling the per-line cap does not leak its head", () => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = path.join(tmp, "ord-arch");
    const first = "a".repeat(130) + " ghp_abcdefghijklmnopqrstuvwxyz0123456789";
    const raw = [first, ...Array.from({ length: 400 }, (_, i) => `row ${i} ${"x".repeat(30)}`)].join("\n");
    const r = packObservation("bash", raw, 1, c);
    expect(r.packed).toBe(true);
    expect(r.compactText).not.toContain("ghp_");
  });
  test("reducer fallback excerpt: secret straddling the per-line cap does not leak its head", () => {
    const c = loadSolPiConfig();
    // The per-line cap depends on raw size (~200 bytes here): sweep the secret's offset over 20 head
    // lines so that at least one straddles the cap whatever its exact value is.
    const heads = Array.from({ length: 20 }, (_, i) => "b".repeat(170 + 6 * i) + " xo" + "xb-1234567890-abcdefghijklmnop");
    const raw = [...heads, ...Array.from({ length: 400 }, (_, i) => `row ${i} ${"x".repeat(30)}`)].join("\n");
    const r = reduceEvidencePreserving("make", raw, 2, c);
    expect(r.fallback).toBe(true);
    expect(r.text).not.toContain("xo" + "xb-");
  });
});

describe("isBuildOrTestCommand is anchored to command segments", () => {
  const yes = ["make", "make test", "go test ./...", "cd x && make all", "FOO=1 go test ./...", "echo hi; pytest -q", "sudo make install", "cat a | cargo test", "bun test lib/", "(cd d && go build ./...)", "time nix build .#x"];
  const no = ["git log --grep make", "cat make.log", "grep go test file.txt", "echo makefile", "ls pytest_cache", "rg 'go test' src", "gomake", "cat Makefile"];
  for (const c of yes) test(`yes: ${c}`, () => expect(isBuildOrTestCommand(c)).toBe(true));
  for (const c of no) test(`no: ${c}`, () => expect(isBuildOrTestCommand(c)).toBe(false));
});

describe("reduceAndArchive keeps the raw log retrievable", () => {
  const cfgAt = (d: string) => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = d;
    return c;
  };
  test("archives the MASKED raw log first and cites handle + path", () => {
    const dir = path.join(tmp, "raa");
    const log = bigFail() + "\npassword=hunter2";
    const r = reduceAndArchive("go test ./...", log, 1, cfgAt(dir));
    expect(r.reduced).toBe(true);
    expect(r.handle).toMatch(/^#obs_[0-9a-f]{12}$/);
    expect(r.text).toContain(r.handle!);
    expect(r.text).toContain(r.archivePath!);
    const body = fs.readFileSync(r.archivePath!, "utf-8");
    expect(body).toContain("--- FAIL: TestFoo");
    expect(body).toContain("ok   pkg/p150");
    expect(body).not.toContain("hunter2");
    expect(ms(r.text)).toBeLessThan(ms(log));
  });
  test("does not archive when nothing was reduced", () => {
    const dir = path.join(tmp, "raa2");
    const r = reduceAndArchive("go test", "ok", 0, cfgAt(dir));
    expect(r.reduced).toBe(false);
    expect(fs.existsSync(dir)).toBe(false);
  });
  test("throws when the archive dir is unsafe (so callers leave the output untouched)", () => {
    const real = fs.mkdtempSync(path.join(tmp, "raa-real-"));
    const link = path.join(tmp, "raa-link");
    fs.symlinkSync(real, link);
    expect(() => reduceAndArchive("go test", bigFail(), 1, cfgAt(link))).toThrow(/symlink/i);
  });
});

describe("exit code resolution", () => {
  test("event.exitCode, result.exitCode, result.details.exitCode; otherwise undefined", () => {
    expect(resolveExitCode({ exitCode: 3 })).toBe(3);
    expect(resolveExitCode({ result: { exitCode: 2 } })).toBe(2);
    expect(resolveExitCode({ result: { details: { exitCode: 5 } } })).toBe(5);
    expect(resolveExitCode({ exitCode: 0, result: { exitCode: 9 } })).toBe(0);
    expect(resolveExitCode({})).toBeUndefined();
    expect(resolveExitCode({ result: "text" })).toBeUndefined();
    expect(resolveExitCode({ exitCode: "1" })).toBeUndefined();
  });
  test("unknown exit code is never rendered as 0 and cannot pass verifyExitCode", () => {
    const log = Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`).join("\n");
    const r = reduceEvidencePreserving("make", log, undefined, loadSolPiConfig());
    expect(r.exitCode).toBeUndefined();
    expect(r.text).toContain("exit code: unknown");
    expect(r.text).not.toContain("exit code: 0");
    expect(r.fallback).toBe(true);
    expect(r.reason).toBe("no-failure-lines");
  });
  test("exit code 0 with no failure lines is a normal (non fail-closed) reduction", () => {
    const log = Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`).join("\n");
    const r = reduceEvidencePreserving("make", log, 0, loadSolPiConfig());
    expect(r.fallback).toBe(false);
    expect(r.text).toContain("exit code: 0");
  });
});

describe("archive growth is bounded", () => {
  test("oldest files are evicted beyond maxArchiveFiles", () => {
    const dir = path.join(tmp, "prune1");
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = dir;
    c.observationPackConfig.maxArchiveFiles = 3;
    const paths: string[] = [];
    for (let i = 0; i < 5; i++) {
      paths.push(packObservation("bash", `${i}`.repeat(11000), i, c).archivePath!);
      sleepMs(8);
    }
    const left = fs.readdirSync(dir);
    expect(left.length).toBe(3);
    expect(fs.existsSync(paths[0])).toBe(false);
    expect(fs.existsSync(paths[1])).toBe(false);
    expect(fs.existsSync(paths[4])).toBe(true);
  });
  test("total bytes are bounded, the newest file always survives", () => {
    const dir = path.join(tmp, "prune2");
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = dir;
    // each archived file is ~4.1 KB (a >4096-char line is cut before masking): 5000 fits exactly one
    c.observationPackConfig.maxArchiveBytes = 5000;
    let last = "";
    for (let i = 0; i < 4; i++) {
      last = packObservation("bash", `${i}`.repeat(11000), i, c).archivePath!;
      sleepMs(8);
    }
    expect(fs.readdirSync(dir).length).toBe(1);
    expect(fs.existsSync(last)).toBe(true);
  });
  test("re-packing identical output reuses the file instead of writing another", () => {
    const dir = path.join(tmp, "prune3");
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = dir;
    const a = archiveObservation("bash", "z".repeat(11000), c);
    const b = archiveObservation("bash", "z".repeat(11000), c);
    expect(b.archivePath).toBe(a.archivePath);
    expect(fs.readdirSync(dir).length).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// Extension wiring with a mock pi
// ---------------------------------------------------------------------------
type Handler = (e: any, c: any) => Promise<unknown>;

function mockPi(cfg: ReturnType<typeof loadSolPiConfig>) {
  // pi allows several handlers per event; run them in registration order and keep the
  // last non-undefined return (e.g. the reducer returns undefined, Action Fusion returns content).
  const listeners: Record<string, Handler[]> = {};
  const cmds: Record<string, { handler: (a: string, c: any) => Promise<void> }> = {};
  const tools: Record<string, any> = {};
  const entries: { type: string; customType?: string; data?: unknown }[] = [];
  const pi = {
    on: (n: string, f: Handler) => void (listeners[n] ??= []).push(f),
    registerCommand: (n: string, d: { handler: (a: string, c: any) => Promise<void> }) => void (cmds[n] = d),
    registerTool: (t: any) => void (tools[t.name] = t),
    appendEntry: (customType: string, data: unknown) => void entries.push({ type: "custom", customType, data }),
  };
  register(pi as never, () => cfg);
  const h: Record<string, Handler> = {};
  for (const name of Object.keys(listeners)) {
    h[name] = async (e: any, c: any) => {
      let last: unknown;
      for (const f of listeners[name]!) {
        const r = await f(e, c);
        if (r !== undefined) last = r;
      }
      return last;
    };
  }
  const notes: string[] = [];
  const sessionDir = fs.mkdtempSync(path.join(tmp, "sess-"));
  const compactCalls: { internalGuidance?: string }[] = [];
  const ctx = (
    cwd: string,
    o: { usage?: { tokens: number; contextWindow: number }; branch?: { type: string; customType?: string; data?: unknown }[] } = {},
  ) => {
    const base: any = {
      cwd,
      ui: { notify: (m: string) => void notes.push(m) },
      sessionManager: {
        getSessionDir: () => sessionDir,
        getSessionId: () => "test-session",
        getBranch: () => o.branch ?? entries,
      },
      modelRegistry: { find: () => null, resolver: () => "test-key" },
      compact: async (opts: { internalGuidance?: string }) => void compactCalls.push(opts),
    };
    if (o.usage) {
      const u = o.usage;
      base.getContextUsage = () => ({ ...u, percent: (u.tokens / u.contextWindow) * 100 });
    }
    return base;
  };
  return { h, cmds, tools, entries, notes, ctx, sessionDir, compactCalls };
}
let extN = 0;
const extCfg = () => {
  const c = loadSolPiConfig();
  c.observationPackConfig.archiveDir = path.join(tmp, `ext-${extN++}`);
  // Boundary compaction is opt-in (shipped flag is false); these tests exercise it.
  c.onlineContextCompactConfig.enabled = true;
  return c;
};
const runCmd = async (m: ReturnType<typeof mockPi>, args: string, cwd: string) => {
  const before = m.notes.length;
  await m.cmds["sol-pi"].handler(args, m.ctx(cwd));
  return m.notes.slice(before).join("\n");
};
const asMsg = (role: string, content: unknown, extra: Record<string, unknown> = {}) => ({ role, content, timestamp: 1, ...extra });
const assistantMsg = (text = "ok") => asMsg("assistant", [{ type: "text", text }]);
const toolResultMsg = (text: string, id = "call-1") =>
  asMsg("toolResult", [{ type: "text", text }], { toolCallId: id, toolName: "bash" });

describe("sol-pi.ts: textSlots", () => {
  test("covers string result, result.content parts, result.text and event.content", () => {
    expect(textSlots({ result: "a" }).length).toBe(1);
    expect(textSlots({ result: { content: [{ type: "text", text: "a" }, { type: "image" }] } }).length).toBe(1);
    expect(textSlots({ result: { text: "a" } }).length).toBe(1);
    expect(textSlots({ content: [{ type: "text", text: "a" }] }).length).toBe(1);
    expect(textSlots({}).length).toBe(0);
  });
  test("a part reachable from both event.content and event.result.content appears once", () => {
    const arr = [{ type: "text", text: "a" }];
    expect(textSlots({ content: arr, result: { content: arr } }).length).toBe(1);
  });
  test("set() writes through to the original object", () => {
    const part = { type: "text", text: "a" };
    textSlots({ result: { content: [part] } })[0].set("b");
    expect(part.text).toBe("b");
  });
});

describe("sol-pi.ts: ObservationPack projection", () => {
  test("a large tool result becomes a placeholder once it has been replayed fullReplayTurns times", async () => {
    const cfg = extCfg();
    const m = mockPi(cfg);
    const raw = bigPlain();
    const env: any = { messages: [toolResultMsg(raw), assistantMsg(), assistantMsg()] };
    const res: any = await m.h.context(env, m.ctx(tmp));
    const text = res.messages[0].content[0].text as string;
    expect(text).toContain("[large tool result replaced after 2 provider requests");
    expect(text).toMatch(/obs_[0-9a-f]{24}/);
    // history keeps the raw text: only the projection is rewritten
    expect(env.messages[0].content[0].text).toBe(raw);
    expect(fs.readdirSync(cfg.observationPackConfig.archiveDir).length).toBe(1);
    expect(await runCmd(m, "stats", tmp)).toContain("1 packed");
  });
  test("inside the full-replay window the projection is untouched", async () => {
    const cfg = extCfg();
    const m = mockPi(cfg);
    const raw = bigPlain();
    const env: any = { messages: [toolResultMsg(raw), assistantMsg()] };
    const res: any = await m.h.context(env, m.ctx(tmp));
    expect(res).toBeUndefined();
    expect(env.messages[0].content[0].text).toBe(raw);
    expect(fs.existsSync(cfg.observationPackConfig.archiveDir)).toBe(false);
  });
  test("the placeholder carries a head/tail excerpt of the masked archive", async () => {
    const m = mockPi(extCfg());
    const raw = bigPlain();
    const res: any = await m.h.context({ messages: [toolResultMsg(raw), assistantMsg(), assistantMsg()] }, m.ctx(tmp));
    const text = res.messages[0].content[0].text as string;
    // first and last source lines are visible without a recall round-trip
    expect(text).toContain("row 0 ");
    expect(text).toContain("row 399 ");
    expect(text).toMatch(/… \(\d+ lines omitted\) …/);
    // the excerpt is bounded: far smaller than the 10 KiB+ raw result
    expect(Buffer.byteLength(text)).toBeLessThan(4096);
  });
  test("a failed tool result is never packed (it is evidence)", async () => {
    const m = mockPi(extCfg());
    const raw = bigPlain();
    const failed = { ...toolResultMsg(raw), isError: true };
    const res: any = await m.h.context({ messages: [failed, assistantMsg(), assistantMsg()] }, m.ctx(tmp));
    expect(res).toBeUndefined();
    expect(failed.content[0].text).toBe(raw);
  });
  test("small results and evidence receipts are never packed", async () => {
    const m = mockPi(extCfg());
    const receipt = `sol_pi_evidence_receipt_v1\n${"y".repeat(20000)}`;
    for (const text of ["tiny", receipt]) {
      const res: any = await m.h.context({ messages: [toolResultMsg(text), assistantMsg(), assistantMsg()] }, m.ctx(tmp));
      expect(res).toBeUndefined();
    }
  });
  test("packing the same id twice reuses the archive file", async () => {
    const cfg = extCfg();
    const m = mockPi(cfg);
    const raw = bigPlain();
    for (let i = 0; i < 2; i++) {
      await m.h.context({ messages: [toolResultMsg(raw), assistantMsg(), assistantMsg()] }, m.ctx(tmp));
    }
    expect(fs.readdirSync(cfg.observationPackConfig.archiveDir).length).toBe(1);
  });
  test("obs_recall pages the archived observation", async () => {
    const m = mockPi(extCfg());
    const raw = bigPlain();
    const res: any = await m.h.context({ messages: [toolResultMsg(raw), assistantMsg(), assistantMsg()] }, m.ctx(tmp));
    const id = /obs_[0-9a-f]{24}/.exec(res.messages[0].content[0].text)![0];
    const out: any = await m.tools.obs_recall.execute("c1", { id, offset: 1, limit: 5 }, undefined, undefined, m.ctx(tmp));
    const text = out.content[0].text as string;
    expect(text).toContain(`obs ${id}: lines 1-5`);
    expect(text).toContain("row 0 ");
    expect(text).toContain("more lines available");
  });
});

describe("sol-pi.ts: Evidence-Preserving Reducer wiring", () => {
  test("tags the reducer output with the deterministic excerpt when no provider is configured", async () => {
    const m = mockPi(extCfg());
    const raw = bigFail();
    const ev: any = { toolName: "bash", input: { command: "go test ./..." }, exitCode: 1, result: raw };
    await m.h.tool_result(ev, m.ctx(tmp));
    expect(ev.result).toBe(raw); // untouched: reduction needs a provider, never silently lost
  });
  test("a build/test log is deterministically reduced when the provider call fails", async () => {
    const cfg = extCfg();
    const m = mockPi(cfg);
    const raw = bigFail();
    const ev: any = { toolName: "bash", input: { command: "go test ./..." }, exitCode: 1, result: raw };
    const c: any = m.ctx(tmp);
    c.modelRegistry.find = () => ({ id: "fake" }); // forces the provider path (the test stub fails)
    await m.h.tool_result(ev, c);
    expect(ev.result).not.toBe(raw);
    expect(ev.result).toContain("exit code: 1");
    expect(ev.result).toContain("--- FAIL: TestFoo");
    expect(ev.result).toMatch(/\[raw log archived: #obs_[0-9a-f]{12} → /);
    expect(m.notes.join("\n")).toContain("provider reduction failed");
    expect(await runCmd(m, "stats", tmp)).toContain("1 fallbacks");
  });
  test("non-build commands and small logs are untouched", async () => {
    const m = mockPi(extCfg());
    for (const ev of [
      { toolName: "bash", input: { command: "cat make.log" }, exitCode: 0, result: bigFail() },
      { toolName: "bash", input: { command: "go test" }, exitCode: 1, result: "tiny" },
      { toolName: "read", input: {}, exitCode: 1, result: bigFail() },
    ]) {
      const before = JSON.stringify(ev.result);
      await m.h.tool_result(ev as any, m.ctx(tmp));
      expect(JSON.stringify(ev.result)).toBe(before);
    }
    expect(await runCmd(m, "stats", tmp)).toContain("Reducer: 0 applied");
  });
  test("a failed archive leaves the output untouched and says 'reducer'", async () => {
    const real = fs.mkdtempSync(path.join(tmp, "unsafe-real-"));
    const link = path.join(tmp, `unsafe-link-${extN++}`);
    fs.symlinkSync(real, link);
    const cfg = extCfg();
    cfg.observationPackConfig.archiveDir = link;
    const m = mockPi(cfg);
    const raw = bigFail();
    const ev: any = { toolName: "bash", input: { command: "go test" }, exitCode: 1, result: raw };
    const c: any = m.ctx(tmp);
    c.modelRegistry.find = () => ({ id: "fake" });
    await m.h.tool_result(ev, c);
    expect(ev.result).toBe(raw);
    expect(m.notes.join("\n")).toContain("reducer");
  });
});

describe("sol-pi.ts: turn_end token accounting / session_start", () => {
  const usage = (u: object, model = "anthropic/claude-haiku-5-5") => ({ message: { model, usage: u } });
  test("cache write tokens are counted (input + cache read + cache write)", async () => {
    const m = mockPi(extCfg());
    await m.h.turn_end(usage({ input: 40000, cacheRead: 30000 }), m.ctx(tmp));
    expect(m.notes.join("\n")).not.toContain("Pricing Cliff reached");
    await m.h.turn_end(usage({ input: 40000, cacheRead: 30000, cacheWrite: 25000 }), m.ctx(tmp));
    expect(m.notes.join("\n")).toContain("Pricing Cliff reached for anthropic/claude-haiku-5-5: 95000 >= 90000");
  });
  test("totalTokens is used when the buckets are absent", async () => {
    const m = mockPi(extCfg());
    await m.h.turn_end(usage({ totalTokens: 95000 }), m.ctx(tmp));
    expect(m.notes.join("\n")).toContain("95000 >= 90000");
  });
  test("warn level at 85% and no auto action", async () => {
    const m = mockPi(extCfg());
    await m.h.turn_end(usage({ input: 80000 }), m.ctx(tmp));
    expect(m.notes.join("\n")).toContain("Approaching Pricing Cliff");
  });
  test("the advisory kill switch silences the notice", async () => {
    const cfg = extCfg();
    cfg.pricingCliffAdvisoryConfig.enabled = false;
    const m = mockPi(cfg);
    await m.h.turn_end(usage({ input: 200000 }), m.ctx(tmp));
    expect(m.notes.length).toBe(0);
  });
  test("session_start resets counters, stats and the last advice", async () => {
    const m = mockPi(extCfg());
    await m.h.context({ messages: [toolResultMsg(bigPlain()), assistantMsg(), assistantMsg()] }, m.ctx(tmp));
    await m.h.turn_end(usage({ input: 95000 }), m.ctx(tmp));
    expect(await runCmd(m, "stats", tmp)).toContain("1 packed");
    expect(await runCmd(m, "status", tmp)).toContain("Pricing Cliff reached");
    await m.h.session_start({}, m.ctx(tmp));
    expect(await runCmd(m, "stats", tmp)).toContain("0 packed");
    const st = await runCmd(m, "status", tmp);
    expect(st).not.toContain("Pricing Cliff");
    expect(st).toContain("Plan: 0 steps");
  });
});

describe("sol-pi.ts: plan state and correction tracking", () => {
  test("update_plan normalizes, keeps completed steps terminal and returns diagnostics", async () => {
    const m = mockPi(extCfg());
    await m.h.session_start({}, m.ctx(tmp));
    const step = m.tools.update_plan;
    const first: any = await step.execute("c1", { plan: [{ step: "wire the projection", status: "completed" }, { step: "add tests", status: "in_progress" }] }, undefined, undefined, m.ctx(tmp));
    expect(first.content[0].text).toContain("[x] wire the projection");
    const second: any = await step.execute("c2", { plan: [{ step: "wire the projection", status: "pending" }, { step: "add tests", status: "completed" }] }, undefined, undefined, m.ctx(tmp));
    expect(second.content[0].text).toContain("cannot reopen a completed step");
    expect(second.content[0].text).toContain("[x] wire the projection");
    expect(m.entries.some((e) => e.customType === "sol_pi_online_state")).toBe(true);
  });
  test("the active plan is appended to the system prompt; no plan -> no replacement", async () => {
    const m = mockPi(extCfg());
    const empty: any = await m.h.before_agent_start({ systemPrompt: ["base"] }, m.ctx(tmp));
    expect(empty).toBeUndefined();
    await m.tools.update_plan.execute("c1", { plan: [{ step: "wire the projection", status: "in_progress" }] }, undefined, undefined, m.ctx(tmp));
    const res: any = await m.h.before_agent_start({ systemPrompt: ["base"] }, m.ctx(tmp));
    expect(res.systemPrompt.length).toBe(2);
    expect(res.systemPrompt[0]).toBe("base");
    expect(res.systemPrompt[1]).toContain("[>] wire the projection");
  });
  test("plan state survives a session restart (loaded from the branch)", async () => {
    const first = mockPi(extCfg());
    await first.h.session_start({}, first.ctx(tmp));
    await first.tools.update_plan.execute("c1", { plan: [{ step: "kept across restart", status: "in_progress" }] }, undefined, undefined, first.ctx(tmp));
    const cfg = extCfg();
    const second = mockPi(cfg);
    const branch = first.entries.map((e) => ({ ...e }));
    await second.h.session_start({}, second.ctx(tmp, { branch }));
    expect(await runCmd(second, "status", tmp)).toContain("Plan: 1 steps");
  });
  test("a correction in user input is counted", async () => {
    const m = mockPi(extCfg());
    await m.h.session_start({}, m.ctx(tmp));
    await m.h.input({ text: "違う、そうではなく agent/v1 の方針で", source: "interactive" }, m.ctx(tmp));
    await m.h.input({ text: "continue", source: "interactive" }, m.ctx(tmp));
    await m.h.input({ text: "that's wrong", source: "rpc" }, m.ctx(tmp));
    expect(await runCmd(m, "status", tmp)).toContain("corrections 1");
  });
});

describe("sol-pi.ts: boundary compaction", () => {
  const bigMessages = () =>
    Array.from({ length: 100 }, (_, i) => assistantMsg(`step ${i} ${"x".repeat(8000)}`));
  const usageTurn = (output: number) => ({ message: { model: "anthropic/claude-haiku-5-5", usage: { output, input: 100000 } } });
  test("compacts once at a terminal agent_end when the request budget is low and the archive is large", async () => {
    const cfg = extCfg();
    const m = mockPi(cfg);
    await m.h.session_start({}, m.ctx(tmp));
    const c = m.ctx(tmp, { usage: { tokens: 195000, contextWindow: 200000 } });
    await m.h.context({ messages: bigMessages() }, c);
    await m.h.turn_end(usageTurn(1000), c);
    await m.h.turn_end(usageTurn(1000), c);
    await m.h.agent_end({ willContinue: false, awaitingAsyncWork: false }, c);
    expect(m.compactCalls.length).toBe(1);
    expect(m.compactCalls[0].internalGuidance).toContain("obs_");
    expect(await runCmd(m, "status", tmp)).toContain("done 1, pending false");
  });
  test("a continuing turn (willContinue / awaitingAsyncWork) is never compacted", async () => {
    const m = mockPi(extCfg());
    await m.h.session_start({}, m.ctx(tmp));
    const c = m.ctx(tmp, { usage: { tokens: 195000, contextWindow: 200000 } });
    await m.h.context({ messages: bigMessages() }, c);
    await m.h.turn_end(usageTurn(1000), c);
    await m.h.turn_end(usageTurn(1000), c);
    await m.h.agent_end({ willContinue: true }, c);
    await m.h.agent_end({ awaitingAsyncWork: true }, c);
    expect(m.compactCalls.length).toBe(0);
  });
  test("compactOnSubtaskBoundary=false defers compaction from agent_end", async () => {
    const cfg = extCfg();
    cfg.onlineContextCompactConfig.compactOnSubtaskBoundary = false;
    const m = mockPi(cfg);
    await m.h.session_start({}, m.ctx(tmp));
    const c = m.ctx(tmp, { usage: { tokens: 195000, contextWindow: 200000 } });
    await m.h.context({ messages: bigMessages() }, c);
    await m.h.turn_end(usageTurn(1000), c);
    await m.h.turn_end(usageTurn(1000), c);
    await m.h.agent_end({ willContinue: false }, c);
    expect(m.compactCalls.length).toBe(0);
    await m.h.session_stop({}, c);
    expect(m.compactCalls.length).toBe(1);
  });
  test("an unneeded native compaction is cancelled; the pending one is allowed", async () => {
    const m = mockPi(extCfg());
    await m.h.session_start({}, m.ctx(tmp));
    const roomy = m.ctx(tmp, { usage: { tokens: 50000, contextWindow: 200000 } });
    expect(await m.h.session_before_compact({}, roomy)).toEqual({ cancel: true });
    const full = m.ctx(tmp, { usage: { tokens: 195000, contextWindow: 200000 } });
    expect(await m.h.session_before_compact({}, full)).toBeUndefined();
  });
  test("a disabled policy never compacts", async () => {
    const cfg = extCfg();
    cfg.onlineContextCompactConfig.enabled = false;
    const m = mockPi(cfg);
    await m.h.session_start({}, m.ctx(tmp));
    const c = m.ctx(tmp, { usage: { tokens: 199000, contextWindow: 200000 } });
    await m.h.context({ messages: bigMessages() }, c);
    await m.h.turn_end(usageTurn(1000), c);
    await m.h.agent_end({ willContinue: false }, c);
    expect(m.compactCalls.length).toBe(0);
  });
});

describe("sol-pi.ts: Action Fusion wiring", () => {
  const mkdir = (p: string) => fs.mkdtempSync(path.join(tmp, p));
  test("invalid edit -> notification; a following bash after the edit gets a targeted warning", async () => {
    const d = mkdir("fx-");
    fs.writeFileSync(path.join(d, "bad.json"), "{oops");
    const m = mockPi(extCfg());
    await m.h.tool_call({ toolName: "write" }, m.ctx(d));
    await m.h.tool_result({ toolName: "write", input: { path: "bad.json" }, result: "ok" }, m.ctx(d));
    expect(m.notes.join("\n")).toContain("validator failed for bad.json");
    expect(m.notes.join("\n")).not.toContain("Previous edit failed");
    await m.h.tool_call({ toolName: "bash" }, m.ctx(d));
    expect(m.notes.join("\n")).toContain("Previous edit failed its validator");
  });
  test("file_path is understood as well", async () => {
    const d = mkdir("fx2-");
    fs.writeFileSync(path.join(d, "bad.json"), "{oops");
    const m = mockPi(extCfg());
    await m.h.tool_result({ toolName: "edit", input: { file_path: "bad.json" }, result: "ok" }, m.ctx(d));
    expect(m.notes.join("\n")).toContain("validator failed for bad.json");
  });
  test("ast_edit / multi-header hashline edit: every explicit file in paths[] is validated, globs and dirs are skipped", async () => {
    const d = mkdir("fx-multi-");
    fs.writeFileSync(path.join(d, "good.json"), "{}");
    fs.writeFileSync(path.join(d, "bad1.json"), "{oops");
    fs.writeFileSync(path.join(d, "bad2.json"), "{oops");
    fs.mkdirSync(path.join(d, "sub.json"));
    const m = mockPi(extCfg());
    await m.h.tool_call({ toolName: "ast_edit" }, m.ctx(d));
    await m.h.tool_result({ toolName: "ast_edit", input: { ops: [], paths: ["good.json", "bad1.json", "*.json", "sub.json/", "bad2.json"] }, result: "ok" }, m.ctx(d));
    const notes = m.notes.join("\n");
    expect(notes).toContain("validator failed for bad1.json");
    expect(notes).toContain("validator failed for bad2.json");
    expect(notes).not.toContain("validator failed for good.json");
    expect(notes).not.toContain("*.json");
    await m.h.tool_call({ toolName: "bash" }, m.ctx(d));
    expect(m.notes.join("\n")).toContain("Previous edit failed its validator");
  });
  test("multi-file edit where only an EARLIER file fails still marks the edit as failed", async () => {
    const d = mkdir("fx-multi2-");
    fs.writeFileSync(path.join(d, "bad.json"), "{oops");
    fs.writeFileSync(path.join(d, "good.json"), "{}");
    const m = mockPi(extCfg());
    await m.h.tool_call({ toolName: "edit" }, m.ctx(d));
    await m.h.tool_result({ toolName: "edit", input: { input: "x", paths: ["bad.json", "good.json"] }, result: "ok" }, m.ctx(d));
    await m.h.tool_call({ toolName: "bash" }, m.ctx(d));
    expect(m.notes.join("\n")).toContain("Previous edit failed its validator");
  });
  test("a valid edit followed by bash is silent", async () => {
    const d = mkdir("fx3-");
    fs.writeFileSync(path.join(d, "good.json"), "{}");
    const m = mockPi(extCfg());
    await m.h.tool_call({ toolName: "write" }, m.ctx(d));
    await m.h.tool_result({ toolName: "write", input: { path: "good.json" }, result: "ok" }, m.ctx(d));
    await m.h.tool_call({ toolName: "bash" }, m.ctx(d));
    expect(m.notes.length).toBe(0);
  });
  test("a validator timeout is inconclusive: reported, but no 'previous edit failed' warning", async () => {
    const d = mkdir("fx4-");
    fs.writeFileSync(path.join(d, "s.slow"), "sleep 5\n");
    const cfg = extCfg();
    cfg.actionFusionConfig.timeoutMs = 200;
    cfg.actionFusionConfig.defaultValidators[".slow"] = "bash {file}";
    const m = mockPi(cfg);
    await m.h.tool_call({ toolName: "write" }, m.ctx(d));
    await m.h.tool_result({ toolName: "write", input: { path: "s.slow" }, result: "ok" }, m.ctx(d));
    expect(m.notes.join("\n")).toContain("timed out");
    await m.h.tool_call({ toolName: "bash" }, m.ctx(d));
    expect(m.notes.join("\n")).not.toContain("Previous edit failed");
  });
  test("a filesystem error (ELOOP) is reported instead of crashing the handler", async () => {
    const d = mkdir("fx5-");
    fs.symlinkSync(path.join(d, "loop.json"), path.join(d, "loop.json"));
    const m = mockPi(extCfg());
    await m.h.tool_result({ toolName: "write", input: { path: "loop.json" }, result: "ok" }, m.ctx(d));
    expect(m.notes.join("\n")).toContain("validator error for loop.json");
  });
  test("/sol-pi verify survives a filesystem error", async () => {
    const d = mkdir("fx6-");
    fs.symlinkSync(path.join(d, "loop.json"), path.join(d, "loop.json"));
    const m = mockPi(extCfg());
    await m.h.tool_result({ toolName: "write", input: { path: "loop.json" }, result: "ok" }, m.ctx(d));
    expect(await runCmd(m, "verify", d)).toContain("error");
  });
  test("a failed validator result is fused into the tool result (barrier)", async () => {
    const d = mkdir("fx7-");
    fs.writeFileSync(path.join(d, "bad.json"), "{oops");
    const m = mockPi(extCfg());
    const res: any = await m.h.tool_result(
      { toolName: "write", input: { path: "bad.json" }, result: { content: [{ type: "text", text: "ok" }] } },
      m.ctx(d),
    );
    const texts = res.content.map((p: any) => p.text).join("\n");
    expect(texts).toContain("action-fusion-validation-failed");
    expect(texts).toContain("bad.json");
  });
});

// ===========================================================================
// Attempt 4: JSON-escaped keys, header ordering on every path, env allowlist,
// input cap, unterminated/long values, masked extraction, extra patterns
// ===========================================================================
describe("JSON-escaped keys and values are masked", () => {
  const cases: [string, string, string][] = [
    ["escaped json password", String.raw`{\"password\":\"S3cretValue\"}`, "S3cretValue"],
    ["escaped json token with spaces", String.raw`"{\"token\": \"abc def ghi\"}"`, "abc def ghi"],
    ["go %q of a json body", String.raw`got "{\"api_key\":\"AbCdEf12 34\"}"`, "AbCdEf12 34"],
    ["double-escaped", String.raw`{\\\"password\\\":\\\"S3cretDouble\\\"}`, "S3cretDouble"],
    ["nested structure value", String.raw`{\"token\":{\"value\":\"a b c\"}}`, "a b c"],
    ["escaped Authorization", String.raw`{\"Authorization\":\"Bearer abcdef123456\"}`, "abcdef123456"],
    ["escaped secret key, array value", String.raw`{\"secret\":[\"s1 s2\",\"s3\"]}`, "s1 s2"],
  ];
  for (const [name, input, secret] of cases) {
    test(`masks ${name}`, () => {
      const out = redactSecrets(`x ${input} y`);
      expect(out).not.toContain(secret);
      expect(out.startsWith("x ")).toBe(true);
    });
  }
  test("the key itself and the surrounding structure stay readable", () => {
    expect(redactSecrets(String.raw`{\"password\":\"S3cretValue\"}`)).toBe(String.raw`{\"password\":***}`);
  });
  test("escaped-JSON secret inside a failing log line never reaches the reducer output", () => {
    const log = [...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`), String.raw`FAIL got {\"password\":\"S3cretValue\"} want x`].join("\n");
    const r = reduceEvidencePreserving("go test", log, 1, loadSolPiConfig());
    expect(r.fallback).toBe(false);
    for (const s of [r.text, r.quotes.join("\n")]) expect(s).not.toContain("S3cretValue");
  });
});

describe("quoted values that are too long / unterminated, and bare values with separators", () => {
  test("a 520-char quoted value is masked up to the end of the line", () => {
    const out = redactSecrets(`password="${"x".repeat(520)} tail-secret" next`);
    expect(out).not.toContain("tail-secret");
    expect(out).not.toContain("xxxxx");
  });
  test("an unterminated quote masks to the end of the line", () => {
    const out = redactSecrets('password="abc def ghi');
    expect(out).not.toContain("def");
    expect(out).not.toContain("ghi");
  });
  test("bare values run to the next whitespace, commas and semicolons included", () => {
    expect(redactSecrets("password=abc,def123")).not.toContain("def123");
    expect(redactSecrets("token=abc;def456 ok")).not.toContain("def456");
    expect(redactSecrets("token=abc;def456 ok")).toContain(" ok");
  });
  test("a following line is untouched by an unterminated quote", () => {
    const out = redactSecrets('password="abc\nnext line stays');
    expect(out.split("\n")[1]).toBe("next line stays");
  });
});

describe("header and every other path: mask the whole text, then cut", () => {
  const SECRET = " sk-ABCDEFGHIJKLMNOPQRSTUV123";
  const log = [...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`), "FAIL github.com/x/y"].join("\n");
  test("command header: a secret straddling the 256-byte cut does not leak its head", () => {
    for (let off = 200; off <= 260; off += 2) {
      const r = reduceEvidencePreserving("go test " + "x".repeat(off) + SECRET, log, 1, loadSolPiConfig());
      expect(r.text).not.toContain("sk-ABC");
    }
  });
  test("fail-closed / fallback header too", () => {
    for (let off = 200; off <= 260; off += 2) {
      const r = reduceEvidencePreserving("go test " + "x".repeat(off) + SECRET, Array.from({ length: 600 }, (_, i) => `ok pkg/p${i}`).join("\n"), 1, loadSolPiConfig());
      expect(r.fallback).toBe(true);
      expect(r.text).not.toContain("sk-ABC");
    }
  });
  test("quotes: secret straddling the 512-byte cut (sweep)", () => {
    for (let off = 470; off <= 520; off += 2) {
      const l = [...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`), "FAIL " + "x".repeat(off) + SECRET].join("\n");
      const r = reduceEvidencePreserving("go test", l, 1, loadSolPiConfig());
      expect(r.quotes.join("\n")).not.toContain("sk-ABC");
      expect(r.text).not.toContain("sk-ABC");
    }
  });
  test("failedTests and locations never contain any part of a secret", () => {
    const l = [...Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`), "--- FAIL: TestA" + SECRET.trim() + " (0.00s)", "    a_test.go:3: boom" + SECRET].join("\n");
    const r = reduceEvidencePreserving("go test", l, 1, loadSolPiConfig());
    for (const s of [r.failedTests.join(","), r.locations.join(","), r.text]) expect(s).not.toContain("ABCDEFGHIJKLMNOPQRSTUV123");
  });
  test("pack compactText: secret straddling the per-line cap (offset sweep over 20 head lines)", () => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = path.join(tmp, "ord4-arch");
    const heads = Array.from({ length: 20 }, (_, i) => "b".repeat(100 + 8 * i) + " xo" + "xb-1234567890-abcdefghijklmnop");
    const raw = [...heads, ...Array.from({ length: 400 }, (_, i) => `row ${i} ${"x".repeat(30)}`)].join("\n");
    expect(packObservation("bash", raw, 1, c).compactText).not.toContain("xo" + "xb-");
  });
});

describe("validator environment allowlist", () => {
  test("Go private-module / proxy / TLS settings pass through; credentials do not", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "env4-"));
    const out = path.join(d, "env.out");
    fs.writeFileSync(path.join(d, "e.envcase"), `env > "${out}"\n`);
    const set: Record<string, string> = {
      GOPRIVATE: "corp.example/*", GONOPROXY: "corp.example", GONOSUMDB: "corp.example", GOPROXY: "https://proxy.corp.example",
      GOSUMDB: "off", GOINSECURE: "corp.example", GOENV: "/home/u/.config/go/env",
      HTTPS_PROXY: "http://p:3128", HTTP_PROXY: "http://p:3128", NO_PROXY: "localhost", https_proxy: "http://p:3128",
      http_proxy: "http://p:3128", no_proxy: "localhost", SSL_CERT_FILE: "/etc/ssl/c.pem", SSL_CERT_DIR: "/etc/ssl/certs",
      ANTHROPIC_API_KEY: "leak-1", GITHUB_TOKEN: "leak-2", AWS_SECRET_ACCESS_KEY: "leak-3", NPM_TOKEN: "leak-4",
    };
    const prev: Record<string, string | undefined> = {};
    for (const [k, v] of Object.entries(set)) {
      prev[k] = process.env[k];
      process.env[k] = v;
    }
    try {
      const cfg = loadSolPiConfig();
      cfg.actionFusionConfig.defaultValidators[".envcase"] = "bash {file}";
      const r = await runActionFusionValidator("e.envcase", d, cfg);
      expect(r.ran && r.ok).toBe(true);
      const env = Object.fromEntries(fs.readFileSync(out, "utf-8").split("\n").filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
      for (const k of ["GOPRIVATE", "GONOPROXY", "GONOSUMDB", "GOPROXY", "GOSUMDB", "GOINSECURE", "GOENV", "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR"]) {
        expect(env[k]).toBe(set[k]);
      }
      for (const k of ["ANTHROPIC_API_KEY", "GITHUB_TOKEN", "AWS_SECRET_ACCESS_KEY", "NPM_TOKEN"]) expect(env[k]).toBeUndefined();
    } finally {
      for (const [k, v] of Object.entries(prev)) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    }
  });
});

describe("input cap keeps redaction cost independent of output size", () => {
  test("1 MB of bare newlines is fast", () => {
    expect(timed(() => redactSecrets("\n".repeat(1_000_000)))).toBeLessThan(300);
  });
  test("1 MB of trigger-word lines is fast", () => {
    // worst case: every line fires the full pattern list (~240 ms measured at the 512 KB input cap)
    expect(timed(() => redactSecrets("key\n".repeat(250_000)))).toBeLessThan(700);
    expect(timed(() => redactSecrets("token=a\n".repeat(125_000)))).toBeLessThan(700);
  });
  test("2 MB with secrets in head and tail: both masked, middle replaced by a marker", () => {
    const filler = "line of filler text\n".repeat(110_000);
    const out = redactSecrets(`password=head-secret\n${filler}${filler}password=tail-secret\n`);
    expect(out).not.toContain("head-secret");
    expect(out).not.toContain("tail-secret");
    expect(out).toContain("chars omitted before redaction");
    expect(out.length).toBeLessThan(600_000);
  });
  test("reducer + archive of a 1 MB newline-only log stays fast", () => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = path.join(tmp, "cap4-arch");
    expect(timed(() => reduceAndArchive("make", "\n".repeat(1_000_000), 1, c))).toBeLessThan(800);
  });
  test("the prefilter never hides a secret category (one sample per trigger family)", () => {
    const samples = [
      "Cookie: a=b1234", "authorization: Basic Zm9vOmJhcg==", "token=aaaa1111", "x api_key=aaaa1111", "secret=aaaa1111", "pass=aaaa1111",
      "pwd=aaaa1111", "credential=aaaa1111", "auth=aaaa1111", "bearer=aaaa1111", "http://u:p4ss@h/", "curl -uadmin:pw99 h", "curl --cookie a=b1234",
      "curl -b a=b1234", "mysql -pS3cr3t db", "mariadb --x -pS3cr3t db", "X-Amz-Signature=beef12345", "Signature=beef12345678",
      "github_pat_" + "A1".repeat(15), "glpat-" + "a1".repeat(12), "glsa_" + "a1".repeat(12), "npm_" + "a1".repeat(18), "AIza" + "a1".repeat(18) + "a",
      "eyJhbGci.eyJzdWIi.sigsig", "AKIA" + "ABCDEFGHIJKLMNOP", "ASIA" + "ABCDEFGHIJKLMNOP", "rk_live_" + "a1".repeat(8), "sk-" + "a1".repeat(12),
      "SG." + "a1".repeat(10) + "." + "b2".repeat(10), "ya29." + "a1".repeat(12), "hf_" + "a1".repeat(16), "ghs_" + "a1".repeat(12), "xo" + "xp-" + "1".repeat(12),
    ];
    for (const s of samples) {
      const out = redactSecrets(s);
      expect(out === s).toBe(false);
    }
  });
});

describe("locations and failedTests are extracted from MASKED lines", () => {
  const ok = Array.from({ length: 300 }, (_, i) => `ok   pkg/p${i}\t0.01s`);
  test("a secret that looks like a file name is not a location", () => {
    const r = reduceEvidencePreserving("go test", [...ok, "FAIL token=hunter2.txt:12"].join("\n"), 1, loadSolPiConfig());
    expect(r.locations.join(",")).not.toContain("hunter2");
    expect(r.text).not.toContain("hunter2");
  });
  test("a >200-char token cannot be sliced into a location fragment", () => {
    const r = reduceEvidencePreserving("go test", [...ok, "FAIL sk-" + "A".repeat(300) + "/x.go:7"].join("\n"), 1, loadSolPiConfig());
    expect(r.locations.join(",")).not.toContain("AAAA");
    expect(r.text).not.toContain("AAAA");
  });
  test("a secret in a test name is masked in failedTests", () => {
    const r = reduceEvidencePreserving("go test", [...ok, "--- FAIL: Test_token=abc123 (0.00s)"].join("\n"), 1, loadSolPiConfig());
    expect(r.failedTests.join(",")).not.toContain("abc123");
  });
  test("ordinary locations and test names are still extracted", () => {
    const r = reduceEvidencePreserving("go test", [...ok, "--- FAIL: TestFoo (0.00s)", "    foo_test.go:42: boom"].join("\n"), 1, loadSolPiConfig());
    expect(r.failedTests).toContain("TestFoo");
    expect(r.locations).toContain("foo_test.go:42");
  });
});

describe("additional secret patterns (best-effort) and non-secrets that must survive", () => {
  const secrets: [string, string, string][] = [
    ["pass=", "login pass=hunter9 now", "hunter9"],
    ["DB_PASS=", "DB_PASS=hunter9", "hunter9"],
    ["key=", "request key=abcd1234efgh", "abcd1234efgh"],
    ["auth=", "url?auth=abcd1234efgh", "abcd1234efgh"],
    ["bearer=", "bearer=abcd1234efgh", "abcd1234efgh"],
    ["mysql -p<pw>", "mysql -u root -phunter9 db", "hunter9"],
    ["glsa_", "glsa_" + "AbCd1234".repeat(3), "AbCd1234AbCd1234"],
    ["curl -b", "curl -b sid=abc123def http://x", "abc123def"],
    ["curl --cookie", "curl --cookie sid=abc123def http://x", "abc123def"],
    ["Digest", 'Authorization: Digest username="u", response="deadbeefcafe0123"', "deadbeefcafe0123"],
    ["AWS4 header", "Authorization: AWS4-HMAC-SHA256 Credential=AKIAXX/20260101/x, Signature=0123456789abcdef0123456789abcdef", "0123456789abcdef0123456789abcdef"],
    ["bare Signature=", "x Signature=0123456789abcdef0123", "0123456789abcdef0123"],
    ["-uuser:pw", "curl -uadmin:pw99xx h", "pw99xx"],
  ];
  for (const [name, input, secret] of secrets) {
    test(`masks ${name}`, () => expect(redactSecrets(input)).not.toContain(secret));
  }
  for (const keep of ["12 passed: 3 tests", "author: bob", "keyboard=1", "=== 12 passed, 0 failed in 1.2s ===", "ok   pkg/p1\t0.01s"]) {
    test(`leaves "${keep}" untouched`, () => expect(redactSecrets(keep)).toBe(keep));
  }
});

describe("cut points, PEM limits, archive dir validation", () => {
  test("a token starting just before the cut is dropped, not left as a head fragment (offset sweep)", () => {
    for (let off = 4060; off <= 4094; off += 2) {
      const out = redactSecrets(" ".repeat(off) + 'k="' + "ghp_" + "a".repeat(36));
      expect(out).not.toContain("ghp_");
    }
  });
  test("a PEM block longer than 200 lines stops being dropped: marker, and later lines are masked normally", () => {
    const body = Array.from({ length: 250 }, (_, i) => `BODY${i}`).join("\n");
    const out = redactSecrets(`-----BEGIN PRIVATE KEY-----\n${body}\nafter password=zzz-secret`);
    expect(out).toContain("masking resumed");
    expect(out).not.toContain("zzz-secret");
    expect(out).not.toContain("BODY5\n");
  });
  test("relative archiveDir is rejected", () => {
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = "relative/dir";
    expect(() => packObservation("bash", "x".repeat(11000), 1, c)).toThrow(/absolute/);
  });
});

// ===========================================================================
// Attempt 5: input-cap cut inside a PEM block, `:=` / `=>` operators,
// Node-side validator timeout, short archive writes
// ===========================================================================
import { spyOn } from "bun:test";

describe("input cap: a cut inside a private key block never leaves key body lines", () => {
  const KEEP = 256 * 1024; // REDACT_KEEP
  const keyLines = (withEnd: boolean, begin = "-----BEGIN RSA PRIVATE KEY-----", end = "-----END RSA PRIVATE KEY-----") =>
    [begin, ...Array.from({ length: 30 }, (_, i) => `KEYBODY${String(i).padStart(2, "0")}${"A1b2".repeat(15)}`), ...(withEnd ? [end] : [])].join("\n");
  const filler = (n: number) => "filler line of ordinary text\n".repeat(Math.ceil(n / 29)).slice(0, n);
  /** text whose tail cut (len - KEEP) lands at `d` chars after the start of the key */
  const build = (key: string, d: number) => {
    const post = KEEP - key.length - 1 + d;
    return `${filler(300_000)}\n${key}\n${filler(post)}`;
  };
  const sweep = (key: string) => [-100, 0, 15, 31, 33, 600, 1200, key.length - 35, key.length - 15, key.length - 1, key.length, key.length + 3];

  for (const withEnd of [true, false]) {
    test(`redactSecrets: cut at key start/middle/end/BEGIN line/END line (${withEnd ? "terminated" : "unterminated"} key)`, () => {
      const key = keyLines(withEnd);
      for (const d of sweep(key)) {
        const text = build(key, d);
        expect(text.length).toBeGreaterThan(512 * 1024);
        const out = redactSecrets(text);
        expect(out).not.toContain("KEYBODY");
      }
    });
  }
  test("terminated key whose body is NOT base64-like (armor headers, spaces): the END line rule drops it", () => {
    const body = Array.from({ length: 30 }, (_, i) => `KEYBODY${String(i).padStart(2, "0")}: not base64, has spaces`);
    const key = ["-----BEGIN PGP PRIVATE KEY BLOCK-----", ...body, "-----END PGP PRIVATE KEY BLOCK-----"].join("\n");
    for (const d of sweep(key)) expect(redactSecrets(build(key, d))).not.toContain("KEYBODY");
  });
  test("PGP armoured key (BLOCK) is handled the same way", () => {
    const key = keyLines(true, "-----BEGIN PGP PRIVATE KEY BLOCK-----", "-----END PGP PRIVATE KEY BLOCK-----");
    for (const d of sweep(key)) expect(redactSecrets(build(key, d))).not.toContain("KEYBODY");
  });
  test("a cut that leaves a trailing key fragment only (END line after) drops up to the END line, keeps what follows", () => {
    const key = keyLines(true);
    const out = redactSecrets(build(key, 600) + "\nafter-key marker line");
    expect(out).not.toContain("KEYBODY");
    expect(out).toContain("after-key marker line");
  });
  test("packObservation: archive and compact text contain no key body", () => {
    const key = keyLines(true);
    for (const d of [15, 600, key.length - 15]) {
      const c = loadSolPiConfig();
      c.observationPackConfig.archiveDir = path.join(tmp, `pem5-pack-${d}`);
      const r = packObservation("bash", build(key, d), 1, c);
      expect(r.packed).toBe(true);
      expect(fs.readFileSync(r.archivePath!, "utf-8")).not.toContain("KEYBODY");
      expect(r.compactText).not.toContain("KEYBODY");
    }
  });
  test("reduceAndArchive: archive and reduced text contain no key body", () => {
    const key = keyLines(false);
    for (const d of [15, 600, key.length - 15]) {
      const c = loadSolPiConfig();
      c.observationPackConfig.archiveDir = path.join(tmp, `pem5-red-${d}`);
      const r = reduceAndArchive("make", build(key, d), 2, c);
      expect(r.reduced).toBe(true);
      expect(fs.readFileSync(r.archivePath!, "utf-8")).not.toContain("KEYBODY");
      expect(r.text).not.toContain("KEYBODY");
    }
  });
});

describe("assignment operators `:=`, `=>`, `==` and value wrappers", () => {
  const cases: [string, string][] = [
    ['password := "hunter2xyz"', "hunter2xyz"],
    ['"password" => "x1y2z3"', "x1y2z3"],
    ["'api_key' => 'k1k2k3'", "k1k2k3"],
    ['password = ( "p1p2p3" )', "p1p2p3"],
    ["password: !!str p4p5p6", "p4p5p6"],
    ['token == "t7t8t9"', "t7t8t9"],
    ['secret=>"s1s2s3"', "s1s2s3"],
    ["$password := hunter9z", "hunter9z"],
    ["password=>(\"q1q2q3\")", "q1q2q3"],
  ];
  for (const [input, secret] of cases) {
    test(`masks ${input}`, () => {
      const out = redactSecrets(`x ${input} y`);
      expect(out).not.toContain(secret);
      expect(out.startsWith("x ")).toBe(true);
    });
  }
  test("the key name stays readable", () => {
    expect(redactSecrets('password := "hunter2xyz"')).toContain("password");
  });
});

describe("validator: Node-side timeout backstop", () => {
  test("a grandchild that escaped the process group and holds stdout cannot stall past timeoutMs + 2s", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "bk-"));
    fs.writeFileSync(path.join(d, "s.bk"), "setsid sleep 9 &\n");
    const cfg = loadSolPiConfig();
    cfg.actionFusionConfig.timeoutMs = 500;
    cfg.actionFusionConfig.defaultValidators[".bk"] = "bash {file}";
    const t = performance.now();
    const r = await runActionFusionValidator("s.bk", d, cfg);
    const elapsed = performance.now() - t;
    expect(r.timedOut).toBe(true);
    expect(r.ok).toBe(false);
    expect(elapsed).toBeLessThan(5000);
  });
});

describe("archive: short writes are detected", () => {
  test("a short write throws, and no truncated archive file is left behind", () => {
    const dir = path.join(tmp, "short1");
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = dir;
    const orig = fs.writeSync;
    const spy = spyOn(fs, "writeSync").mockImplementation(((fd: number, buf: Buffer) => orig(fd, buf, 0, 5)) as never);
    try {
      expect(() => packObservation("bash", "x".repeat(11000), 1, c)).toThrow(/short write to archive \(5 of \d+ bytes\)/);
    } finally {
      spy.mockRestore();
    }
    expect(fs.readdirSync(dir).length).toBe(0);
  });
  test("a write that throws also leaves no file behind", () => {
    const dir = path.join(tmp, "short2");
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = dir;
    const spy = spyOn(fs, "writeSync").mockImplementation((() => {
      throw Object.assign(new Error("ENOSPC: no space left on device"), { code: "ENOSPC" });
    }) as never);
    try {
      expect(() => packObservation("bash", "x".repeat(11000), 1, c)).toThrow(/ENOSPC/);
    } finally {
      spy.mockRestore();
    }
    expect(fs.readdirSync(dir).length).toBe(0);
  });
  test("a normal write still succeeds afterwards", () => {
    const dir = path.join(tmp, "short3");
    const c = loadSolPiConfig();
    c.observationPackConfig.archiveDir = dir;
    const r = packObservation("bash", "x".repeat(11000), 1, c);
    expect(fs.statSync(r.archivePath!).size).toBeGreaterThan(0);
  });
});


// ---------------------------------------------------------------------------
// T16: Pricing Cliff single source / own advisory flag / async + scoped + sandboxed validator
// ---------------------------------------------------------------------------
describe("Pricing Cliff: single source = catalog.json compaction_threshold", () => {
  test("shipped sol-pi.json has no pricingCliffs list; thresholds come from the catalog", () => {
    const raw = JSON.parse(fs.readFileSync(path.resolve(import.meta.dir, "..", "..", "sol-pi.json"), "utf-8"));
    expect(raw.onlineContextCompactConfig.pricingCliffs).toBeUndefined();
    const cat = JSON.parse(fs.readFileSync(path.resolve(import.meta.dir, "..", "..", "..", "..", "models", "catalog.json"), "utf-8"));
    const cfg = loadSolPiConfig();
    for (const [id, m] of Object.entries(cat.models as Record<string, any>)) {
      if (typeof m.compaction_threshold === "number") expect(pricingCliffFor(id, cfg)).toBe(m.compaction_threshold);
    }
    expect(pricingCliffFor("anthropic/claude-haiku-5-5", cfg)).toBe(90000);
    expect(pricingCliffFor("openai/gpt-6.2-sol", cfg)).toBe(250000);
    expect(pricingCliffFor("openai/gpt-6.2-astra", cfg)).toBe(250000);
    expect(pricingCliffFor("anthropic/claude-sonnet-5-5", cfg)).toBe(180000);
    expect(cfg.onlineContextCompactConfig.tokenPressureThreshold).toBe(180000);
  });
  test("a pinned catalog wins; a legacy pricingCliffs list in a user sol-pi.json is ignored", () => {
    const f = path.join(tmp, "legacy-cliffs.json");
    fs.writeFileSync(f, JSON.stringify({ onlineContextCompactConfig: { pricingCliffs: [{ pattern: "haiku-5[.-]5", tokens: 1 }] } }));
    const cfg = loadSolPiConfig(f);
    try {
      setPricingCliffCatalog({ models: { "x/foo-1": { model_id: "foo-1", compaction_threshold: 1234 } } });
      expect(pricingCliffFor("x/foo-1", cfg)).toBe(1234);
      expect(pricingCliffFor("foo-1-20261101", cfg)).toBe(1234);
      expect(pricingCliffFor("anthropic/claude-haiku-5-5", cfg)).toBe(180000);
      setPricingCliffCatalog(null);
      expect(pricingCliffFor("x/foo-1", cfg)).toBe(180000);
    } finally {
      setPricingCliffCatalog(undefined);
    }
    expect(pricingCliffFor("anthropic/claude-haiku-5-5", cfg)).toBe(90000);
  });
  test("respectPricingCliffs=false falls back to the default threshold", () => {
    const cfg = loadSolPiConfig();
    cfg.onlineContextCompactConfig.respectPricingCliffs = false;
    expect(pricingCliffFor("anthropic/claude-haiku-5-5", cfg)).toBe(180000);
  });
});

describe("Pricing Cliff advisory has its own flag (onlineContextCompact kill switch does not gate it)", () => {
  test("shipped config: onlineContextCompact=false but advisory on -> turn_end still warns", async () => {
    const cfg = loadSolPiConfig();
    expect(cfg.onlineContextCompactConfig.enabled).toBe(false);
    expect(cfg.pricingCliffAdvisoryConfig.enabled).toBe(true);
    cfg.observationPackConfig.archiveDir = path.join(tmp, `ext-${extN++}`);
    const m = mockPi(cfg);
    await m.h.turn_end({ message: { model: "anthropic/claude-haiku-5-5", usage: { input: 95000 } } }, m.ctx(tmp));
    expect(m.notes.join("\n")).toContain("Pricing Cliff reached");
  });
});

const fakeBin = (dir: string, name: string, body: string) => {
  fs.mkdirSync(dir, { recursive: true });
  const f = path.join(dir, name);
  fs.writeFileSync(f, `#!/bin/bash\n${body}\n`, { mode: 0o755 });
  return f;
};
const withPath = async <T>(extra: string, fn: () => Promise<T>): Promise<T> => {
  const prev = process.env.PATH;
  process.env.PATH = `${extra}:${prev}`;
  try {
    return await fn();
  } finally {
    process.env.PATH = prev;
  }
};

describe("Action Fusion: asynchronous execution", () => {
  test("the event loop keeps ticking while a validator runs", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "async-"));
    fs.writeFileSync(path.join(d, "s.slow"), "sleep 0.8\n");
    const cfg = loadSolPiConfig();
    cfg.actionFusionConfig.defaultValidators[".slow"] = "bash {file}";
    let ticks = 0;
    const iv = setInterval(() => ticks++, 50);
    const p = runActionFusionValidator("s.slow", d, cfg);
    expect(p).toBeInstanceOf(Promise);
    const r = await p;
    clearInterval(iv);
    expect(r.ok).toBe(true);
    expect(ticks).toBeGreaterThanOrEqual(6);
  });
});

describe("Action Fusion: scoped to the edited package", () => {
  test("go vet runs on the edited package, not ./...", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "gov-"));
    fs.mkdirSync(path.join(d, "pkg", "sub"), { recursive: true });
    fs.writeFileSync(path.join(d, "go.mod"), "module x\n");
    fs.writeFileSync(path.join(d, "pkg", "sub", "a.go"), "package sub\n");
    fs.writeFileSync(path.join(d, "top.go"), "package x\n");
    const out = path.join(d, "argv.out");
    const bin = path.join(d, "bin");
    fakeBin(bin, "go", `printf '%s ' "$@" > "${out}"`);
    await withPath(bin, async () => {
      expect((await runActionFusionValidator("pkg/sub/a.go", d)).ok).toBe(true);
      expect(fs.readFileSync(out, "utf-8").trim()).toBe("vet ./pkg/sub");
      expect((await runActionFusionValidator("top.go", d)).ok).toBe(true);
      expect(fs.readFileSync(out, "utf-8").trim()).toBe("vet .");
    });
  });

  test("goValidatorEnv: strips tool-injection flags, keeps the rest, adds -mod=readonly only when no -mod is given", () => {
    expect(goValidatorEnv(undefined)).toEqual({ GOENV: "off", GOPROXY: "off", GOTOOLCHAIN: "local", GOFLAGS: "-mod=readonly" });
    expect(goValidatorEnv("-toolexec=/tmp/evil -tags=ngt -race").GOFLAGS).toBe("-tags=ngt -race -mod=readonly");
    expect(goValidatorEnv("-exec=/tmp/evil -vettool=/tmp/v").GOFLAGS).toBe("-mod=readonly");
    expect(goValidatorEnv("-mod=vendor -tags=x").GOFLAGS).toBe("-mod=vendor -tags=x");
    expect(goValidatorEnv("  -mod=mod   ").GOFLAGS).toBe("-mod=mod");
    // -toolexecfoo is some other (invalid) flag name, not -toolexec: kept as-is
    expect(goValidatorEnv("-toolexecfoo=1").GOFLAGS).toBe("-toolexecfoo=1 -mod=readonly");
    // cmd/go accepts --flag and quoted tokens in GOFLAGS: normalise the name, and drop any quoted value wholesale
    expect(goValidatorEnv("--toolexec=/tmp/evil -tags=x").GOFLAGS).toBe("-tags=x -mod=readonly");
    expect(goValidatorEnv("--exec=/tmp/e --vettool=/tmp/v").GOFLAGS).toBe("-mod=readonly");
    expect(goValidatorEnv("'-toolexec=/tmp/evil' -tags=x").GOFLAGS).toBe("-mod=readonly");
    expect(goValidatorEnv('"-toolexec=/tmp/a b" -tags=x').GOFLAGS).toBe("-mod=readonly");
    expect(goValidatorEnv("--mod=vendor").GOFLAGS).toBe("--mod=vendor");
  });

  test("go vet runs with the proxy and toolchain download closed and tool injection stripped; cgo is left as the user set it", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "goenv-"));
    fs.writeFileSync(path.join(d, "go.mod"), "module x\n");
    fs.writeFileSync(path.join(d, "a.go"), "package x\n");
    const out = path.join(d, "env.out");
    const bin = path.join(d, "bin");
    fakeBin(bin, "go", `printf '%s|%s|%s|%s|%s' "$CGO_ENABLED" "$GOPROXY" "$GOTOOLCHAIN" "$GOFLAGS" "$GOENV" > "${out}"`);
    const saved = { CGO_ENABLED: process.env.CGO_ENABLED, GOPROXY: process.env.GOPROXY, GOTOOLCHAIN: process.env.GOTOOLCHAIN, GOFLAGS: process.env.GOFLAGS, GOENV: process.env.GOENV };
    Object.assign(process.env, { CGO_ENABLED: "1", GOPROXY: "https://proxy.example", GOTOOLCHAIN: "auto", GOFLAGS: "-toolexec=/tmp/evil -tags=ngt", GOENV: "/tmp/evil-go-env" });
    try {
      await withPath(bin, async () => {
        expect((await runActionFusionValidator("a.go", d)).ok).toBe(true);
      });
      // CGO_ENABLED is not on the child-env allowlist, so it is neither forced to 0 nor forwarded: Go's own default applies.
      expect(fs.readFileSync(out, "utf-8")).toBe("|off|local|-tags=ngt -mod=readonly|off");
    } finally {
      for (const [k, v] of Object.entries(saved)) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    }
  });
});

describe("Action Fusion: build-definition files never run build-executing validators", () => {
  const cases: [string, string, string][] = [
    ["build.rs", ".rs", "cargo check --quiet"],
    [".cargo/hook.rs", ".rs", "cargo check --quiet"],
    ["x.mk", ".mk", "make -n -f {file}"],
    ["Makefile", "", "make -n -f {file}"],
    ["go.mod", ".mod", "go mod verify"],
    ["go.work", ".work", "go work sync"],
    ["Cargo.toml", ".toml", "cargo metadata"],
    ["Cargo.lock", ".lock", "cargo metadata"],
  ];
  for (const [name, ext, spec] of cases) {
    test(`${name} -> skipped-build-file (validator and sandbox never invoked)`, async () => {
      const d = fs.mkdtempSync(path.join(tmp, "bd-"));
      fs.writeFileSync(path.join(d, "Cargo.toml"), "[package]\n");
      fs.writeFileSync(path.join(d, "go.mod"), "module x\n");
      fs.mkdirSync(path.dirname(path.join(d, name)), { recursive: true });
      if (name !== "Cargo.toml" && name !== "go.mod") fs.writeFileSync(path.join(d, name), "x\n");
      const marks = path.join(d, "marks");
      fs.mkdirSync(marks);
      const bin = path.join(d, "bin");
      for (const t of ["cargo", "make", "go"]) fakeBin(bin, t, `touch "${marks}/${t}"`);
      const sb = fakeBin(bin, "fake-sandbox", `touch "${marks}/sandbox"`);
      const cfg = loadSolPiConfig();
      cfg.actionFusionConfig.defaultValidators[ext] = spec;
      const r = await withPath(bin, () => runActionFusionValidator(name, d, cfg, { sandboxBin: sb, netns: true }));
      expect(r.ran).toBe(false);
      expect(r.reason).toBe("skipped-build-file");
      expect(fs.readdirSync(marks)).toEqual([]);
    });
  }
  test("a Makefile whose parse would run code (make -n -f) is not executed", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "mk-"));
    fs.writeFileSync(path.join(d, "x.mk"), `x := $(shell touch "${path.join(d, "PWNED")}")\nall:\n`);
    const cfg = loadSolPiConfig();
    cfg.actionFusionConfig.defaultValidators[".mk"] = "make -n -f {file}";
    const r = await runActionFusionValidator("x.mk", d, cfg);
    expect(r.reason).toBe("skipped-build-file");
    expect(fs.existsSync(path.join(d, "PWNED"))).toBe(false);
  });
  test("non-executing validators (json.tool on package.json, py_compile on setup.py) still run", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "ne-"));
    fs.writeFileSync(path.join(d, "package.json"), "{ bad");
    fs.writeFileSync(path.join(d, "setup.py"), "x = 1\n");
    expect((await runActionFusionValidator("package.json", d)).ok).toBe(false);
    expect((await runActionFusionValidator("setup.py", d)).ran).toBe(true);
  });
  test("isBuildDefinitionFile: .cargo/ segment and *.mk only", () => {
    expect(isBuildDefinitionFile(path.join(tmp, ".cargo", "config.toml"), tmp)).toBe(true);
    expect(isBuildDefinitionFile(path.join(tmp, "a", "x.mk"), tmp)).toBe(true);
    expect(isBuildDefinitionFile(path.join(tmp, "a", "main.rs"), tmp)).toBe(false);
  });
});

describe("Action Fusion: cargo-class validators only through pa-sandbox", () => {
  const setup = () => {
    const d = fs.mkdtempSync(path.join(tmp, "sbx-"));
    fs.mkdirSync(path.join(d, "src"));
    fs.writeFileSync(path.join(d, "Cargo.toml"), "[package]\n");
    fs.writeFileSync(path.join(d, "src", "lib.rs"), "\n");
    const bin = path.join(d, "bin");
    const log = path.join(d, "sandbox.log");
    const mark = path.join(d, "cargo.ran");
    fakeBin(bin, "cargo", `touch "${mark}"; echo checked`);
    return { d, bin, log, mark };
  };
  test("runs as `<pa-sandbox> -- cargo check ...` from the Cargo.toml root", async () => {
    const { d, bin, log, mark } = setup();
    const sb = fakeBin(bin, "fake-sandbox", `printf '%s\\n' "$@" > "${log}"; shift; exec "$@"`);
    const r = await withPath(bin, () => runActionFusionValidator("src/lib.rs", d, loadSolPiConfig(), { sandboxBin: sb, netns: true }));
    expect(r.ran && r.ok).toBe(true);
    expect(r.command?.slice(0, 6)).toEqual(["unshare", "-rn", "--", sb, "--", "cargo"]);
    expect(fs.readFileSync(log, "utf-8").split("\n").slice(0, 3)).toEqual(["--", "cargo", "check"]);
    expect(fs.existsSync(mark)).toBe(true);
  });
  test("pa-sandbox unavailable -> skipped, cargo is never run unsandboxed", async () => {
    const { d, bin, mark } = setup();
    const r = await withPath(bin, () => runActionFusionValidator("src/lib.rs", d, loadSolPiConfig(), { sandboxBin: null, netns: true }));
    expect(r.ran).toBe(false);
    expect(r.ok).toBe(true);
    expect(r.reason).toBe("sandbox-unavailable");
    expect(fs.existsSync(mark)).toBe(false);
  });
  test("pa-sandbox refusing to start is inconclusive, not a validator failure", async () => {
    const { d, bin, mark } = setup();
    const sb = fakeBin(bin, "refusing-sandbox", `echo "pa-sandbox: workspace has no .git" >&2; exit 70`);
    const r = await withPath(bin, () => runActionFusionValidator("src/lib.rs", d, loadSolPiConfig(), { sandboxBin: sb, netns: true }));
    expect(r.ran).toBe(false);
    expect(r.ok).toBe(true);
    expect(r.reason).toBe("sandbox-unavailable");
    expect(fs.existsSync(mark)).toBe(false);
  });
  test("go and bash validators are not routed through the sandbox", async () => {
    const d = fs.mkdtempSync(path.join(tmp, "nosb-"));
    fs.writeFileSync(path.join(d, "a.json"), "{}");
    const r = await runActionFusionValidator("a.json", d, loadSolPiConfig(), { sandboxBin: null, netns: true });
    expect(r.ran && r.ok).toBe(true);
  });
});

const haveNetns = await netnsAvailable();
describe("Action Fusion: build-class validators run without network (unshare -rn)", () => {
  const skipIfNo = haveNetns ? test : test.skip; // SKIP is shown when user namespaces are unavailable
  const mk = (n: string) => {
    const d = fs.mkdtempSync(path.join(tmp, n));
    fs.mkdirSync(path.join(d, "src"));
    fs.writeFileSync(path.join(d, "Cargo.toml"), "[package]\n");
    fs.writeFileSync(path.join(d, "src", "lib.rs"), "\n");
    return d;
  };
  test("no network namespace support -> skipped with reason no-netns, nothing is run", async () => {
    const d = mk("nons-");
    const bin = path.join(d, "bin");
    fakeBin(bin, "cargo", `touch "${d}/cargo.ran"`);
    const sb = fakeBin(bin, "fake-sandbox", `touch "${d}/sandbox.ran"; shift; exec "$@"`);
    const r = await withPath(bin, () => runActionFusionValidator("src/lib.rs", d, loadSolPiConfig(), { sandboxBin: sb, netns: false }));
    expect(r.ran).toBe(false);
    expect(r.ok).toBe(true);
    expect(r.reason).toBe("no-netns");
    expect(fs.existsSync(path.join(d, "cargo.ran"))).toBe(false);
    expect(fs.existsSync(path.join(d, "sandbox.ran"))).toBe(false);
  });
  skipIfNo("a cargo-class validator cannot reach a loopback listener (real network namespace)", async () => {
    const d = mk("net-");
    const srv = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {}, open() {} } });
    const out = path.join(d, "net.out");
    const bin = path.join(d, "bin");
    fakeBin(bin, "cargo", `python3 -I -c "import socket\ntry:\n socket.create_connection(('127.0.0.1',${srv.port}),1); open('${out}','w').write('CONNECTED')\nexcept OSError:\n open('${out}','w').write('BLOCKED')"`);
    const sb = fakeBin(bin, "fake-sandbox", `shift; exec "$@"`);
    try {
      const r = await withPath(bin, () => runActionFusionValidator("src/lib.rs", d, loadSolPiConfig(), { sandboxBin: sb }));
      expect(r.ran && r.ok).toBe(true);
      expect(fs.readFileSync(out, "utf-8")).toBe("BLOCKED");
      const ctl = Bun.spawnSync(["python3", "-I", "-c", `import socket;socket.create_connection(('127.0.0.1',${srv.port}),1);print('CONNECTED')`]);
      expect(ctl.stdout.toString().trim()).toBe("CONNECTED"); // control: reachable without the namespace
    } finally {
      srv.stop(true);
    }
  });
});

// ===========================================================================
// Action Fusion: then_run (fused follow-up command)
// ===========================================================================
describe("then_run core", () => {
  const mkFile = (name: string, body = "package x\n") => {
    const d = fs.mkdtempSync(path.join(tmp, "thenrun-"));
    const f = path.join(d, name);
    fs.writeFileSync(f, body);
    return { d, f };
  };
  test("parseThenRun accepts a string and { command, timeout }, rejects blanks", () => {
    expect(parseThenRun("  go test ./...  ")).toEqual({ command: "go test ./..." });
    expect(parseThenRun({ command: "make", timeout: 5 })).toEqual({ command: "make", timeout: 5 });
    expect(parseThenRun({ command: "make", timeout: -1 })).toEqual({ command: "make" });
    expect(parseThenRun("   ")).toBeUndefined();
    expect(parseThenRun({})).toBeUndefined();
    expect(parseThenRun(42)).toBeUndefined();
  });
  test("a successful command reports [then_run:succeeded] with its output", async () => {
    const { d } = mkFile("a.go");
    const r = await runThenRun({ filePath: path.join(d, "a.go"), cwd: d, spec: { command: "echo fused-ok" } });
    expect(r.status).toBe("succeeded");
    expect(r.marker).toBe("[then_run:succeeded]");
    expect(r.output).toContain("fused-ok");
  });
  test("a failing command reports [then_run:failed] with the exit code and output", async () => {
    const { d, f } = mkFile("b.go");
    const r = await runThenRun({ filePath: f, cwd: d, spec: { command: "echo boom; exit 3" } });
    expect(r.status).toBe("failed");
    expect(r.marker).toBe("[then_run:failed]");
    expect(r.exitCode).toBe(3);
    expect(r.output).toContain("boom");
  });
  test("a changed file between mutation and command skips the command", async () => {
    const { d, f } = mkFile("c.go");
    const log = path.join(d, "ran.log");
    const r = await runThenRun({
      filePath: f,
      cwd: d,
      spec: { command: `echo ran >> ${JSON.stringify(log)}` },
      beforeCommand: async () => void fs.writeFileSync(f, "package y\n// mutated elsewhere\n"),
    });
    expect(r.status).toBe("skipped");
    expect(r.marker).toBe("[then_run:skipped]");
    expect(fs.existsSync(log)).toBe(false);
  });
  test("fused operations on the same file are serialized (no interleaving)", async () => {
    const { d, f } = mkFile("d.go");
    const log = path.join(d, "order.log");
    const cmd = `echo start >> ${JSON.stringify(log)}; sleep 0.15; echo end >> ${JSON.stringify(log)}`;
    await Promise.all([
      runThenRun({ filePath: f, cwd: d, spec: { command: cmd } }),
      runThenRun({ filePath: f, cwd: d, spec: { command: cmd } }),
    ]);
    expect(fs.readFileSync(log, "utf-8").trim().split("\n")).toEqual(["start", "end", "start", "end"]);
  });
  test("a timeout is reported as failed with the timeout marker", async () => {
    const { d, f } = mkFile("e.go");
    const r = await runThenRun({ filePath: f, cwd: d, spec: { command: "sleep 5", timeout: 1 }, timeoutMs: 1000 });
    expect(r.status).toBe("failed");
    expect(r.timedOut).toBe(true);
  });
  test("output is capped at maxOutputChars", async () => {
    const { d, f } = mkFile("f.go");
    const r = await runThenRun({ filePath: f, cwd: d, spec: { command: "seq 1 2000" }, maxOutputChars: 100 });
    expect(r.status).toBe("succeeded");
    expect(r.output.length).toBeLessThan(200);
    expect(r.output).toContain("truncated");
  });
});

describe("sol-pi.ts: then_run wiring", () => {
  const writeFile = (d: string, name: string) => {
    const f = path.join(d, name);
    fs.writeFileSync(f, "package x\n");
    return f;
  };
  const editEvent = (file: string, thenRun: unknown, extra: Record<string, unknown> = {}) => ({
    toolName: "edit",
    input: { path: file, ...(thenRun === undefined ? {} : { then_run: thenRun }) },
    toolCallId: "call-then",
    ...extra,
  });
  const merged = (res: any) =>
    [res?.content ?? []].flat().filter((p: any) => p?.type === "text").map((p: any) => p.text).join("\n");

  test("edit + then_run: command runs, marker and output follow the edit result", async () => {
    const m = mockPi(extCfg());
    const d = fs.mkdtempSync(path.join(tmp, "trw-"));
    const f = writeFile(d, "ok.json");
    const ev: any = editEvent(f, "echo fused-ok", { content: [{ type: "text", text: "edit applied" }] });
    const res: any = await m.h.tool_result(ev, m.ctx(d));
    const text = merged(res);
    expect(text).toContain("edit applied");
    expect(text).toContain("[then_run:succeeded]");
    expect(text).toContain("fused-ok");
    expect(res.isError).toBeUndefined();
  });
  test("a failing command keeps the edit result and marks [then_run:failed]", async () => {
    const m = mockPi(extCfg());
    const d = fs.mkdtempSync(path.join(tmp, "trw-"));
    const f = writeFile(d, "fail.json");
    const ev: any = editEvent(f, { command: "echo nope; exit 7" }, { content: [{ type: "text", text: "edit applied" }] });
    const res: any = await m.h.tool_result(ev, m.ctx(d));
    const text = merged(res);
    expect(text).toContain("edit applied");
    expect(text).toContain("[then_run:failed] (exit code 7)");
    // upstream reports the fused failure as a failed tool result
    expect(res.isError).toBe(true);
  });
  test("a failed mutation skips the command ([then_run:skipped], nothing runs)", async () => {
    const m = mockPi(extCfg());
    const d = fs.mkdtempSync(path.join(tmp, "trw-"));
    const f = writeFile(d, "skip.json");
    const log = path.join(d, "ran.log");
    const ev: any = editEvent(f, `echo ran >> ${JSON.stringify(log)}`, { isError: true, content: [{ type: "text", text: "edit failed" }] });
    const res: any = await m.h.tool_result(ev, m.ctx(d));
    const text = merged(res);
    expect(text).toContain("[then_run:skipped]");
    expect(fs.existsSync(log)).toBe(false);
    expect(res.isError).toBe(true);
  });
  test("then_run is inert when actionFusion.thenRun.enabled is false", async () => {
    const cfg = extCfg();
    cfg.actionFusionConfig.thenRun.enabled = false;
    const m = mockPi(cfg);
    const d = fs.mkdtempSync(path.join(tmp, "trw-"));
    const f = writeFile(d, "off.json");
    const text = merged(await m.h.tool_result(editEvent(f, "echo fused-ok", { content: [{ type: "text", text: "edit applied" }] }), m.ctx(d)));
    expect(text).not.toContain("[then_run:");
  });
});
