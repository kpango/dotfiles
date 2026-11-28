import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  DapMessageParser,
  encodeDapMessage,
  formatStackFrames,
  formatVariables,
  loadDapConfig,
  matchDapAdapter,
  parseDlvListenEndpoint,
} from "./dap-core";

describe("dap-core", () => {
  test("loadDapConfig loads repository dap.json", () => {
    const repoDap = path.resolve(import.meta.dir, "..", "..", "dap.json");
    const cfg = loadDapConfig([repoDap]);
    expect(cfg.adapters.dlv).toBeDefined();
    expect(cfg.adapters.dlv.connectMode).toBe("socket");
    expect(cfg.adapters["lldb-dap"]).toBeDefined();
    expect(cfg.adapters["lldb-dap"].connectMode).toBe("stdio");
  });

  test("matchDapAdapter selects dlv for .go and lldb-dap for .rs", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "dap-core-"));
    try {
      fs.writeFileSync(path.join(tmp, "go.mod"), "module example.com/app\n");
      fs.writeFileSync(path.join(tmp, "main.go"), "package main\n");
      const cfg = loadDapConfig([path.resolve(import.meta.dir, "..", "..", "dap.json")]);
      const goMatch = matchDapAdapter(cfg, path.join(tmp, "main.go"), undefined, tmp);
      expect(goMatch?.adapterName).toBe("dlv");
      expect(goMatch?.rootDir).toBe(tmp);

      const rsMatch = matchDapAdapter(cfg, path.join(tmp, "main.rs"), undefined, tmp);
      expect(rsMatch?.adapterName).toBe("lldb-dap");

      const explicitMatch = matchDapAdapter(cfg, undefined, "dlv", tmp);
      expect(explicitMatch?.adapterName).toBe("dlv");
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });

  test("encodeDapMessage + DapMessageParser handles split and multi-frame packets", () => {
    const msg1 = { seq: 1, type: "response", request_seq: 1, success: true, command: "initialize" };
    const msg2 = { seq: 2, type: "event", event: "stopped", body: { reason: "breakpoint", threadId: 7 } };
    const combined = Buffer.concat([encodeDapMessage(msg1), encodeDapMessage(msg2)]);

    const parser = new DapMessageParser();
    expect(parser.push(combined.subarray(0, 12))).toHaveLength(0);
    const out = parser.push(combined.subarray(12));
    expect(out).toHaveLength(2);
    expect(out[0].command).toBe("initialize");
    expect((out[1].body as any).threadId).toBe(7);
  });

  test("parseDlvListenEndpoint parses dlv output", () => {
    expect(parseDlvListenEndpoint("DAP server listening at: 127.0.0.1:41235\n")).toEqual({
      host: "127.0.0.1",
      port: 41235,
    });
    expect(parseDlvListenEndpoint("starting server...")).toBeNull();
  });

  test("formatStackFrames and formatVariables format readable diagnostics", () => {
    const stack = formatStackFrames([
      { id: 1, name: "main.run", line: 42, column: 3, source: { path: "/app/main.go" } },
    ]);
    expect(stack).toContain("#1 main.run at /app/main.go:42:3");
    const vars = formatVariables([{ name: "count", value: "3", type: "int", variablesReference: 0 }]);
    expect(vars).toBe("count: int = 3");
  });
});
