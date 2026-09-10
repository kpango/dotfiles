/**
 * Unit tests for the MCP bridge: streamable-HTTP transport against the
 * Executor gateway pattern (stateless 2026-07-28 server/discover) and
 * legacy initialize fallback for 2024-11-05 servers.
 */

import * as http from "node:http";
import {
  McpClient,
  extractSsePayload,
  isAllowedMcpUrl,
  isUsableMcpConfig,
  MCP_PROTOCOL_VERSION,
} from "../mcp-bridge";

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

// --- extractSsePayload (prefers id-matching payload) ---
const sseWithMismatch =
  "event: log\ndata: {\"jsonrpc\":\"2.0\",\"id\":99,\"result\":{\"ignored\":true}}\n\n" +
  "data: {\"jsonrpc\":\"2.0\",\"id\":7,\"result\":{\"good\":true}}\n\n";
check(
  "extractSsePayload picks the id-matching payload",
  extractSsePayload(sseWithMismatch, 7) !== null &&
    (JSON.parse(extractSsePayload(sseWithMismatch, 7) as string) as any).result?.good === true
);
check(
  "extractSsePayload falls back to first payload without id match",
  (JSON.parse(extractSsePayload("data: {\"id\":1}\n\n", 999) as string) as any).id === 1
);
check("extractSsePayload returns null for plain JSON", extractSsePayload("{\"a\":1}", 1) === null);

// L1 regression: JSON-RPC ids may be echoed as strings; the id match must be
// value-based so a string-echoed id still correlates and a preceding
// notification is not returned as the response.
check(
  "extractSsePayload matches a string-echoed id (number request)",
  (() => {
    const sse = 'data: {"jsonrpc":"2.0","method":"progress"}\n\ndata: {"jsonrpc":"2.0","id":"5","result":{"answer":42}}\n\n';
    const got = extractSsePayload(sse, 5);
    return got !== null && (JSON.parse(got) as any).result?.answer === 42;
  })()
);
check(
  "extractSsePayload still matches a numeric id",
  (() => {
    const got = extractSsePayload('data: {"jsonrpc":"2.0","id":9,"result":{"v":1}}\n\n', 9);
    return got !== null && (JSON.parse(got) as any).result?.v === 1;
  })()
);
check(
  "extractSsePayload does not treat a notification (no id) as the response",
  (() => {
    const sse = 'data: {"jsonrpc":"2.0","method":"x"}\n\ndata: {"jsonrpc":"2.0","id":7,"result":{"ok":true}}\n\n';
    const got = extractSsePayload(sse, 7);
    return got !== null && (JSON.parse(got) as any).result?.ok === true;
  })()
);
// L5 regression: a multi-line `data:` event must be reassembled (joined with \n)
// into one payload, not mis-split into unparseable fragments.
const multiLineData =
  "event: message\n" +
  "data: {\"jsonrpc\":\"2.0\",\n" +
  "data: \"id\":42,\n" +
  "data: \"result\":{\"ok\":true}}\n\n";
const reassembled = extractSsePayload(multiLineData, 42);
check(
  "extractSsePayload reassembles a multi-line data event",
  reassembled !== null && (JSON.parse(reassembled as string) as any).id === 42
);
check(
  "extractSsePayload reassembled multi-line result parses correctly",
  reassembled !== null && (JSON.parse(reassembled as string) as any).result?.ok === true
);
// id-matching still selects the correct event when a progress event precedes it
// across multiple single-line events.
const progressThenReply =
  "data: {\"jsonrpc\":\"2.0\",\"method\":\"progress\"}\n\n" +
  "data: {\"jsonrpc\":\"2.0\",\"id\":5,\"result\":{}}\n\n";
check(
  "extractSsePayload skips progress event and picks id-matched reply",
  (JSON.parse(extractSsePayload(progressThenReply, 5) as string) as any).id === 5
);

// --- URL allowance (SSRF guard) ---
check("isAllowedMcpUrl allows localhost http", isAllowedMcpUrl("http://localhost:4788/mcp"));
check("isAllowedMcpUrl allows 127.0.0.1", isAllowedMcpUrl("http://127.0.0.1:4788/mcp"));
check("isAllowedMcpUrl allows ::1", isAllowedMcpUrl("http://[::1]:4788/mcp"));
check("isAllowedMcpUrl rejects remote host", !isAllowedMcpUrl("https://example.com/mcp"));
check("isAllowedMcpUrl rejects ftp scheme", !isAllowedMcpUrl("ftp://127.0.0.1/x"));
check("isAllowedMcpUrl rejects malformed url", !isAllowedMcpUrl("not-a-url"));

// --- isUsableMcpConfig ---
check("isUsableMcpConfig accepts command", isUsableMcpConfig({ command: "mcp-server" }));
check("isUsableMcpConfig accepts url", isUsableMcpConfig({ url: "http://127.0.0.1:4788/mcp" }));
check("isUsableMcpConfig rejects empty", !isUsableMcpConfig({}));
check("MCP_PROTOCOL_VERSION is 2026-07-28", MCP_PROTOCOL_VERSION === "2026-07-28");

function startServer(handler: (msg: any, res: http.ServerResponse) => void): Promise<{ server: http.Server; port: number }> {
  return new Promise((resolve) => {
    const server = http.createServer((req, res) => {
      let body = "";
      req.on("data", (c) => (body += c));
      req.on("end", () => {
        res.setHeader("Content-Type", "application/json");
        let msg: any;
        try {
          msg = JSON.parse(body);
        } catch (e: any) {
          res.end(JSON.stringify({ jsonrpc: "2.0", error: { code: -32700, message: e.message } }));
          return;
        }
        handler(msg, res);
      });
    });
    server.listen(0, "127.0.0.1", () => {
      resolve({ server, port: (server.address() as any).port });
    });
  });
}

// --- Stateless 2026-07-28 server (Executor gateway pattern) ---
async function runStateless() {
  const { server, port } = await startServer((msg, res) => {
    if (typeof msg.id === "undefined") {
      // JSON-RPC requests without an id are Notifications and must receive
      // no response; a conforming server would never answer these. Return an
      // error so the test fails loudly if the client omits the id.
      res.end(JSON.stringify({ jsonrpc: "2.0", error: { code: -32600, message: "missing id (notification)" } }));
      return;
    }
    if (msg.method === "server/discover") {
      res.end(JSON.stringify({
        jsonrpc: "2.0", id: msg.id, result: {
          resultType: "complete",
          supportedVersions: ["2026-07-28"],
          capabilities: { tools: { listChanged: true } },
          ttlMs: 3600000,
          cacheScope: "public",
        },
      }));
      return;
    }
    if (msg.method === "tools/list") {
      res.end(JSON.stringify({
        jsonrpc: "2.0", id: msg.id, result: { tools: [
          { name: "echo", description: "Echo", inputSchema: { type: "object" } },
          { name: "add", description: "Add", inputSchema: { type: "object" } },
        ] },
      }));
      return;
    }
    if (msg.method === "tools/call") {
      const args = msg.params.arguments || {};
      const out = args.text ?? String((args.a ?? 0) + (args.b ?? 0));
      res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: { content: [{ type: "text", text: `result:${out}` }] } }));
      return;
    }
    res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "Method not found" } }));
  });

  const client = new McpClient("executor", { url: `http://127.0.0.1:${port}/mcp` }, process.cwd());
  try {
    await client.start(2000);
    check("stateless start() keeps 2026-07-28 protocol", client["protocolVersion"] === "2026-07-28");
    const tools = await client.listTools(2000);
    check("listTools returns catalog tools", tools.length === 2);
    const call = await client.callTool("echo", { text: "hi" });
    check("callTool round-trips", JSON.stringify(call).includes("result:hi"));
    client.stop();
  } finally {
    server.close();
  }
}

// --- Legacy 2024-11-05 fallback ---
async function runLegacy() {
  let discoverCalls = 0;
  const { server, port } = await startServer((msg, res) => {
    if (msg.method === "server/discover") {
      discoverCalls++;
      res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "Method not found" } }));
      return;
    }
    if (msg.method === "initialize") {
      res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "legacy", version: "1.0.0" } } }));
      return;
    }
    if (msg.method === "tools/list") {
      res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, result: { tools: [{ name: "legacy_tool" }] } }));
      return;
    }
    res.end(JSON.stringify({ jsonrpc: "2.0", id: msg.id, error: { code: -32601, message: "Method not found" } }));
  });

  const client = new McpClient("legacy", { url: `http://127.0.0.1:${port}/mcp` }, process.cwd());
  try {
    await client.start(2000);
    check("legacy start() attempts server/discover first", discoverCalls === 1);
    check("legacy start() falls back to initialize", client["protocolVersion"] === "2024-11-05");
    const tools = await client.listTools(2000);
    check("legacy listTools works", tools.length === 1 && tools[0].name === "legacy_tool");
    client.stop();
  } finally {
    server.close();
  }
}

// --- Unreachable endpoint fails fast ---
async function runUnreachable() {
  const client = new McpClient("dead", { url: "http://127.0.0.1:1/mcp" }, process.cwd());
  try {
    await client.start(500);
    check("unreachable endpoint rejects", false, "start() should have thrown");
  } catch {
    check("unreachable endpoint rejects", true);
  } finally {
    client.stop();
  }
}

// --- Disallowed remote url is rejected before any network I/O ---
async function runDisallowedUrl() {
  const client = new McpClient("evil", { url: "https://example.com/mcp" }, process.cwd());
  try {
    await client.start(500);
    check("disallowed url rejects", false, "start() should have thrown");
  } catch (e: any) {
    check(
      "disallowed url rejects",
      String(e.message).includes("disallowed url"),
      `expected disallowed-url error, got: ${e.message}`
    );
  } finally {
    client.stop();
  }
}

// --- Redirect is refused (SSRF guard: loopback -> external bounce) ---
async function runRedirect() {
  const { server, port } = await startServer((msg, res) => {
    res.writeHead(307, {
      Location: `http://127.0.0.1:${port === 0 ? 9 : 9}/mcp`,
    });
    res.end();
  });

  const client = new McpClient("redirector", { url: `http://127.0.0.1:${port}/mcp` }, process.cwd());
  try {
    await client.start(1000);
    check("redirect response is rejected", false, "start() should have thrown on 307");
  } catch (e: any) {
    check(
      "redirect response is rejected",
      String(e.message).includes("redirect"),
      `expected redirect error, got: ${e.message}`
    );
  } finally {
    client.stop();
    server.close();
  }
}

(async () => {
  await runStateless();
  await runLegacy();
  await runUnreachable();
  await runDisallowedUrl();
  await runRedirect();
  console.log(`\nmcp-bridge.test: ${pass} passed, ${fail} failed`);
  process.exit(fail > 0 ? 1 : 0);
})();
