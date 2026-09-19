/**
 * lib/graft-executor-bridge.ts の実機テスト(graft-bridge.test.ts と同じ手作り
 * check()/pass/fail 集計規約)。
 *
 * `executor` バイナリを直接叩くのではなく、テスト専用のスタブ実行ファイル(bash script)を
 * `opts.binary` として差し込み、callGraftTool() が実際に spawn する経路
 * (runCliBridge → node:child_process.spawn、shell: true を渡さない argv 形式)を実機で検証する。
 * ADR-0001 決定2(executor call をシェルアウトで呼ぶ)の実装が「argvとして安全に渡す」ことを
 * 保証しているかどうかは、この経路を実際に spawn してみない限り確認できない。
 */
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { callGraftTool } from "./graft-executor-bridge";

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

function writeStub(dir: string, name: string, script: string): string {
  const p = path.join(dir, name);
  fs.writeFileSync(p, `#!/usr/bin/env bash\n${script}\n`);
  fs.chmodSync(p, 0o755);
  return p;
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "graft-executor-bridge-test-"));

async function main() {
  // 1. Successful call parsing: a stub "executor" prints the real observed
  //    `executor call` response shape (verified 2026-09-13 against the live
  //    graft-dotfiles.user.graftDotfiles connection — see ADR-0001) and
  //    callGraftTool must extract data.content[0].text.
  {
    const stub = writeStub(
      tmp,
      "stub-ok.sh",
      `echo '{"ok":true,"data":{"content":[{"type":"text","text":"hello from graft"}],"isError":false}}'`,
    );
    const result = await callGraftTool("graft_find_code", { query: "x" }, { binary: stub, cwd: tmp });
    check("successful call returns extracted text", result === "hello from graft", `got: ${JSON.stringify(result)}`);
  }

  // 2. executor binary missing (ENOENT) -> null, never throws.
  {
    let threw = false;
    let result: string | null = null;
    try {
      result = await callGraftTool("graft_find_code", { query: "x" }, { binary: "definitely-not-a-real-binary-xyz123", cwd: tmp });
    } catch {
      threw = true;
    }
    check("missing executor binary returns null", result === null);
    check("missing executor binary does not throw", !threw);
  }

  // 3. executor call structurally succeeds but reports ok:false (e.g. tool not
  //    found / connection down) -> null.
  {
    const stub = writeStub(
      tmp,
      "stub-notok.sh",
      `echo '{"ok":false,"error":{"code":"tool_not_found","message":"nope"}}'`,
    );
    const result = await callGraftTool("graft_find_code", { query: "x" }, { binary: stub, cwd: tmp });
    check("ok:false response returns null", result === null);
  }

  // 4. Malformed / non-JSON stdout -> null, never throws.
  {
    const stub = writeStub(tmp, "stub-badjson.sh", `echo 'not json at all'`);
    let threw = false;
    let result: string | null = null;
    try {
      result = await callGraftTool("graft_find_code", { query: "x" }, { binary: stub, cwd: tmp });
    } catch {
      threw = true;
    }
    check("malformed stdout returns null", result === null);
    check("malformed stdout does not throw", !threw);
  }

  // 5. ok:true but data.isError:true (the underlying tool call itself failed)
  //    -> null, per this bridge's own design choice (documented in
  //    graft-executor-bridge.ts) to never surface an error string as if it
  //    were legitimate graft context/orientation text.
  {
    const stub = writeStub(
      tmp,
      "stub-toolerror.sh",
      `echo '{"ok":true,"data":{"content":[{"type":"text","text":"boom"}],"isError":true}}'`,
    );
    const result = await callGraftTool("graft_find_code", { query: "x" }, { binary: stub, cwd: tmp });
    check("data.isError:true returns null", result === null);
  }

  // 6. Timeout -> null, never throws. Stub sleeps past a tiny timeoutMs.
  {
    const stub = writeStub(tmp, "stub-slow.sh", `sleep 5\necho '{"ok":true,"data":{"content":[{"type":"text","text":"late"}],"isError":false}}'`);
    let threw = false;
    let result: string | null = null;
    const start = Date.now();
    try {
      result = await callGraftTool("graft_find_code", { query: "x" }, { binary: stub, cwd: tmp, timeoutMs: 200 });
    } catch {
      threw = true;
    }
    const elapsedMs = Date.now() - start;
    check("timeout returns null", result === null);
    check("timeout does not throw", !threw);
    check("timeout resolves well under the 5s sleep", elapsedMs < 4500, `elapsed=${elapsedMs}ms`);
  }

  // 7. L1 injection regression (mirrors graft-bridge.test.ts's L1 case): a
  //    query containing shell metacharacters must reach the spawned process as
  //    ONE literal argv element and never be shell-interpreted anywhere along
  //    this bridge's own call path. The stub captures its raw argv (via
  //    printf '%s\0') to a file instead of touching a marker, so this proves
  //    argv fidelity directly rather than merely proving "nothing happened"
  //    (which a broken stub could satisfy vacuously).
  {
    const marker = path.join(tmp, "pwned");
    const captureFile = path.join(tmp, "argv-capture.bin");
    const stub = writeStub(
      tmp,
      "stub-capture-argv.sh",
      `for a in "$@"; do printf '%s\\0' "$a"; done > "${captureFile}"\n` +
        `echo '{"ok":true,"data":{"content":[{"type":"text","text":"stub-ok"}],"isError":false}}'`,
    );
    const payloads = [`x$(touch ${marker})`, "y`touch " + marker + "`", `z; touch ${marker}`];
    let threw = false;
    for (const payload of payloads) {
      try {
        await callGraftTool("graft_find_code", { query: payload }, { binary: stub, cwd: tmp });
      } catch {
        threw = true;
      }
      const captured = fs.readFileSync(captureFile, "utf-8");
      const argv = captured.split("\0").filter((s) => s.length > 0);
      // args[] is ["call", "graft-dotfiles.user.graftDotfiles.graft_find_code", '{"query":"<payload>"}']
      const jsonArg = argv[argv.length - 1];
      const roundTripped = JSON.parse(jsonArg);
      check(
        `L1: payload survives as literal argv (${payload.slice(0, 12)}...)`,
        roundTripped.query === payload,
        `argv had: ${JSON.stringify(argv)}`,
      );
    }
    check("L1: shell-metacharacter query does not execute commands", !fs.existsSync(marker));
    check("L1: shell-metacharacter query does not throw", !threw);
  }

  fs.rmSync(tmp, { recursive: true, force: true });

  console.log(`\ngraft-executor-bridge: ${pass} passed, ${fail} failed`);
  if (fail > 0) process.exit(1);
}

await main();
