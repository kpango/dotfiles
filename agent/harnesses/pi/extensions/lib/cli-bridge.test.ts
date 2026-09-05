/**
 * pi/extensions/lib/cli-bridge.ts の実機テスト。
 *
 * bridge-claude.ts・bridge-antigravity.ts・bridge-codex.tsの統合(2026-09-03)、および
 * security-audit指摘(SIGKILLフォールバック不発、プロセスグループkillへの修正)の
 * 再発防止テスト。fakeバイナリ(bashスクリプト)でspawn/abort/エラー系を検証する。
 * `bun run pi/extensions/lib/cli-bridge.test.ts` で実行(bun:testフレームワークは使わず、
 * このリポジトリの他テストスクリプトと同じ「PASS/FAILカウンタ + 非ゼロexit」スタイルに揃える)。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { deriveCliBridgeOutput, runCliBridge } from "./cli-bridge";

let pass = 0;
let fail = 0;
function check(desc: string, ok: boolean, detail?: string) {
  if (ok) {
    console.log(`ok: ${desc}`);
    pass++;
  } else {
    console.log(`FAIL: ${desc}${detail ? ` (${detail})` : ""}`);
    fail++;
  }
}

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "cli-bridge-test-"));

function writeFixture(name: string, content: string): string {
  const p = path.join(tmpDir, name);
  fs.writeFileSync(p, content, { mode: 0o755 });
  return p;
}

async function main() {
  // 1. 正常終了・ストリーミング更新
  const okBin = writeFixture("ok.sh", "#!/usr/bin/env bash\necho line1\nsleep 0.1\necho line2\nexit 0\n");
  const updates: string[] = [];
  const r1 = await runCliBridge({
    binary: okBin,
    args: [],
    cwd: tmpDir,
    runningPlaceholder: "(running...)",
    onUpdate: (u) => updates.push(u.displayText),
  });
  check("normal completion: exitCode=0", r1.exitCode === 0, `got ${r1.exitCode}`);
  check("normal completion: stdout captured", r1.stdout === "line1\nline2\n", JSON.stringify(r1.stdout));
  check("normal completion: not aborted", r1.wasAborted === false);
  check("normal completion: streaming updates fired incrementally", updates.length >= 2, `got ${updates.length}`);

  // 2. 非ゼロ終了
  const failBin = writeFixture("fail.sh", "#!/usr/bin/env bash\necho oops >&2\nexit 3\n");
  const r2 = await runCliBridge({ binary: failBin, args: [], cwd: tmpDir, runningPlaceholder: "(running...)" });
  check("non-zero exit: exitCode=3", r2.exitCode === 3, `got ${r2.exitCode}`);
  const derived = deriveCliBridgeOutput(r2.exitCode, r2.stdout, r2.stderr, "fallback error text");
  check("non-zero exit: isError=true", derived.isError === true);

  // 3. missing binary
  const r3 = await runCliBridge({
    binary: path.join(tmpDir, "does-not-exist.sh"),
    args: [],
    cwd: tmpDir,
    runningPlaceholder: "(running...)",
  });
  check("missing binary: exitCode=1", r3.exitCode === 1, `got ${r3.exitCode}`);
  check("missing binary: stderr mentions Process error", r3.stderr.includes("Process error"), r3.stderr);

  // 4. abort — 協調的プロセス(SIGTERMに素直に応答)は3秒以内に終了する
  const cooperativeBin = writeFixture("cooperative.sh", "#!/usr/bin/env bash\ntrap 'exit 0' TERM\nsleep 30\n");
  const ac4 = new AbortController();
  setTimeout(() => ac4.abort(), 300);
  const start4 = Date.now();
  const r4 = await runCliBridge({
    binary: cooperativeBin,
    args: [],
    cwd: tmpDir,
    runningPlaceholder: "(running...)",
    signal: ac4.signal,
  });
  const elapsed4 = Date.now() - start4;
  check("abort (cooperative): wasAborted=true", r4.wasAborted === true);
  check("abort (cooperative): resolves quickly via SIGTERM (<2.5s)", elapsed4 < 2500, `elapsed=${elapsed4}ms`);

  // 5. abort — 非協調的プロセス(SIGTERMを無視)はSIGKILLフォールバック(プロセスグループkill)で
  // 約3.5秒以内に終了する(security-audit指摘の再発防止 — 旧実装は`proc.killed`を終了判定に
  // 使っており常にfalse判定でSIGKILLが不発、さらに単一PID killでは孫プロセス(このテストでは
  // 無いが一般のbashスクリプトが起動する子プロセス)がstdoutパイプを保持し続けてcloseイベントが
  // 自然終了まで遅延する実害があった)。
  const uncooperativeBin = writeFixture("uncooperative.sh", "#!/usr/bin/env bash\ntrap '' TERM\nsleep 30\n");
  const ac5 = new AbortController();
  setTimeout(() => ac5.abort(), 300);
  const start5 = Date.now();
  const r5 = await runCliBridge({
    binary: uncooperativeBin,
    args: [],
    cwd: tmpDir,
    runningPlaceholder: "(running...)",
    signal: ac5.signal,
  });
  const elapsed5 = Date.now() - start5;
  check("abort (uncooperative, SIGTERM ignored): wasAborted=true", r5.wasAborted === true);
  check(
    "abort (uncooperative): SIGKILL fallback fires within ~4s, not left to run 30s",
    elapsed5 < 5000,
    `elapsed=${elapsed5}ms`,
  );

  fs.rmSync(tmpDir, { recursive: true, force: true });

  console.log("----");
  console.log(`pass=${pass} fail=${fail}`);
  process.exit(fail === 0 ? 0 : 1);
}

main();
