// Unit tests for the supermemory adapter (agent/hooks/pi/lib/memory-adapter.ts).
// The adapter lives beside shared.ts in the hooks tree; this test imports it via a
// cross-tree relative path. All I/O is exercised through an injected fake fetch, so
// the suite never touches the network or global state.
import {
  resolveSupermemoryConfig,
  isValidLoopbackEndpoint,
  buildSearchRequest,
  parseSearchResults,
  buildDocumentPayload,
  formatMemoryInjection,
  searchMemories,
  addMemory,
  isAvailable,
  type FetchLike,
} from "../../../../hooks/pi/lib/memory-adapter";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

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

function fakeFetch(spec: {
  status?: number;
  json?: unknown;
  capture?: (url: string, init?: { method?: string; headers?: Record<string, string>; body?: string }) => void;
  throwErr?: boolean;
}): FetchLike {
  return async (url, init) => {
    spec.capture?.(url, init);
    if (spec.throwErr) throw new Error("network down");
    const status = spec.status ?? 200;
    return {
      ok: status >= 200 && status < 300,
      status,
      json: async () => spec.json ?? {},
      text: async () => JSON.stringify(spec.json ?? {}),
    };
  };
}

// --- resolveSupermemoryConfig ---
{
  const cfg = resolveSupermemoryConfig({}, "/nonexistent/env/file");
  check("config defaults to localhost:6767", cfg.endpoint === "http://localhost:6767");
  check("config apiKey null when unset", cfg.apiKey === null);

  const cfg2 = resolveSupermemoryConfig({ SUPERMEMORY_API_URL: "http://127.0.0.1:9/", SUPERMEMORY_API_KEY: "sm_abc" }, "/nope");
  check("env endpoint wins and trailing slash trimmed", cfg2.endpoint === "http://127.0.0.1:9");
  check("env apiKey used", cfg2.apiKey === "sm_abc");

  // env file fallback
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "sm-cfg-"));
  const ef = path.join(tmp, "env");
  fs.writeFileSync(ef, "SUPERMEMORY_API_KEY=sm_fromfile\nOPENAI_MODEL=x\n");
  const cfg3 = resolveSupermemoryConfig({}, ef);
  check("env file supplies apiKey when env unset", cfg3.apiKey === "sm_fromfile");
  fs.rmSync(tmp, { recursive: true, force: true });
}

// --- isValidLoopbackEndpoint / SSRF guard (mirrors supermemory.sh's sm__validate_endpoint) ---
{
  check("loopback: localhost", isValidLoopbackEndpoint("http://localhost:6767") === true);
  check("loopback: 127.0.0.1 no port", isValidLoopbackEndpoint("http://127.0.0.1") === true);
  check("loopback: [::1] with port", isValidLoopbackEndpoint("http://[::1]:6767") === true);
  check("loopback: trailing slash ok", isValidLoopbackEndpoint("http://localhost:6767/") === true);
  check("rejects non-loopback hostname", isValidLoopbackEndpoint("http://example.com") === false);
  check("rejects non-loopback IP", isValidLoopbackEndpoint("http://192.168.1.5:6767") === false);
  check("rejects 0.0.0.0 (non-loopback)", isValidLoopbackEndpoint("http://0.0.0.0:6767") === false);
  check("rejects https scheme", isValidLoopbackEndpoint("https://localhost:6767") === false);
  check("rejects userinfo", isValidLoopbackEndpoint("http://user@localhost:6767") === false);
  check("rejects path suffix", isValidLoopbackEndpoint("http://localhost:6767/v1") === false);
  check("rejects query suffix", isValidLoopbackEndpoint("http://localhost:6767?x=1") === false);
  check("rejects out-of-range port", isValidLoopbackEndpoint("http://localhost:99999") === false);
  check("rejects port 0", isValidLoopbackEndpoint("http://localhost:0") === false);

  // resolveSupermemoryConfig must refuse (not silently fall back), matching the bash
  // sm_endpoint contract: a configured-but-invalid endpoint yields "" (a sentinel every
  // exported async helper below checks and treats as "no server configured"), not the
  // default endpoint.
  const evil = resolveSupermemoryConfig({ SUPERMEMORY_API_URL: "http://evil.example.com" }, "/nope");
  check("config refuses (not silently defaults) a non-loopback env endpoint", evil.endpoint === "");

  const evilFileTmp = fs.mkdtempSync(path.join(os.tmpdir(), "sm-cfg-evil-"));
  const evilFile = path.join(evilFileTmp, "env");
  fs.writeFileSync(evilFile, "SUPERMEMORY_API_URL=http://evil.example.com\n");
  const evilFromFile = resolveSupermemoryConfig({}, evilFile);
  check("config refuses a non-loopback endpoint from the env file too", evilFromFile.endpoint === "");
  fs.rmSync(evilFileTmp, { recursive: true, force: true });
}

// --- buildSearchRequest ---
{
  const cfg = { endpoint: "http://h:1", apiKey: null };
  const r = buildSearchRequest(cfg, "vald", ["claude-memory"], 8);
  check("search url points at /v4/search", r.url === "http://h:1/v4/search");
  const body = JSON.parse(r.body);
  check("search body carries q", body.q === "vald");
  check("search body carries containerTags", Array.isArray(body.containerTags) && body.containerTags[0] === "claude-memory");
  check("search limit clamped to <=50", JSON.parse(buildSearchRequest(cfg, "x", [], 999).body).limit === 50);
  check("search omits containerTags when no tags", JSON.parse(buildSearchRequest(cfg, "x", []).body).containerTags === undefined);
}

// --- parseSearchResults ---
{
  const parsed = parseSearchResults({
    results: [
      { id: "a", memory: "vald is an ANN engine.", score: 0.9 },
      { content: "fallback content field", documentId: "d1" },
      { memory: "   " }, // blank → skipped
      { nope: true }, // no memory → skipped
      "garbage",
    ],
  });
  check("parses memory + content fields, skips blanks/garbage", parsed.length === 2);
  check("first parsed memory text correct", parsed[0].memory === "vald is an ANN engine.");
  check("content field used as memory when memory absent", parsed[1].memory === "fallback content field");
  check("non-object json → []", parseSearchResults(null).length === 0 && parseSearchResults({ results: "x" }).length === 0);
}

// --- buildDocumentPayload ---
{
  const p = buildDocumentPayload("body", ["claude-memory"], { title: "t.md" }, "claude/memory/t.md");
  check("doc payload has content/tags/metadata", p.content === "body" && (p.containerTags as string[])[0] === "claude-memory" && (p.metadata as any).title === "t.md");
  check("customId sanitized (no slashes/dots)", p.customId === "claude-memory-t-md");
  check("customId omitted when not given", buildDocumentPayload("b", ["x"]).customId === undefined);
}

// --- formatMemoryInjection ---
{
  const block = formatMemoryInjection([
    { memory: "A fact." },
    { memory: "A fact." }, // dup → deduped
    { memory: "B fact." },
  ]);
  check("injection block has header + deduped bullets", block.includes("[Relevant Memory (supermemory)]") && (block.match(/- /g) || []).length === 2);
  check("empty memories → empty string", formatMemoryInjection([]) === "");
}

// --- async: searchMemories with injected fetch ---
await (async () => {
  let capturedUrl = "";
  const results = await searchMemories("vald", {
    tags: ["claude-memory"],
    cfg: { endpoint: "http://h:1", apiKey: "sm_k" },
    fetchImpl: fakeFetch({ json: { results: [{ memory: "hit one" }] }, capture: (u) => (capturedUrl = u) }),
  });
  check("searchMemories returns parsed hits", results.length === 1 && results[0].memory === "hit one");
  check("searchMemories hit /v4/search", capturedUrl === "http://h:1/v4/search");

  const empty = await searchMemories("q", { fetchImpl: fakeFetch({ status: 500 }), cfg: { endpoint: "http://h:1", apiKey: null } });
  check("searchMemories non-2xx → []", empty.length === 0);

  const thrown = await searchMemories("q", { fetchImpl: fakeFetch({ throwErr: true }), cfg: { endpoint: "http://h:1", apiKey: null } });
  check("searchMemories network throw → [] (never throws)", thrown.length === 0);

  const blank = await searchMemories("   ", { fetchImpl: fakeFetch({ json: { results: [{ memory: "x" }] } }) });
  check("searchMemories blank query → [] without calling fetch", blank.length === 0);

  // auth header sent when apiKey present
  let sawAuth = false;
  await searchMemories("q", {
    cfg: { endpoint: "http://h:1", apiKey: "sm_k" },
    fetchImpl: fakeFetch({ json: { results: [] }, capture: (_u, init) => (sawAuth = init?.headers?.authorization === "Bearer sm_k") }),
  });
  check("searchMemories sends bearer when apiKey present", sawAuth);
})();

// --- async: addMemory ---
await (async () => {
  const id = await addMemory("content", ["claude-memory"], {
    customId: "a/b.md",
    cfg: { endpoint: "http://h:1", apiKey: null },
    fetchImpl: fakeFetch({ json: { id: "doc123", status: "queued" } }),
  });
  check("addMemory returns queued id", id === "doc123");

  const none = await addMemory("", ["x"], { fetchImpl: fakeFetch({ json: { id: "z" } }) });
  check("addMemory empty content → null (no fetch)", none === null);

  const failed = await addMemory("c", ["x"], { fetchImpl: fakeFetch({ status: 400 }), cfg: { endpoint: "http://h:1", apiKey: null } });
  check("addMemory non-2xx → null", failed === null);
})();

// --- async: isAvailable ---
await (async () => {
  check("isAvailable true on 200", (await isAvailable({ fetchImpl: fakeFetch({ status: 200 }), cfg: { endpoint: "http://h:1", apiKey: null } })) === true);
  check("isAvailable false on error", (await isAvailable({ fetchImpl: fakeFetch({ throwErr: true }), cfg: { endpoint: "http://h:1", apiKey: null } })) === false);
})();

console.log(`\nmemory-adapter: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
