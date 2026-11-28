/**
 * lib/bounded-payload.ts のテスト。`bun test` の単一ファイル実行で動く PASS/FAIL カウンタ形式。
 */

import { boundJsonPayload, jsonByteLength } from "./bounded-payload";

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
function eq<T>(name: string, actual: T, expected: T) {
  check(name, actual === expected, `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
}

const opts = { maxBytes: 64, previewChars: 8 };

const small = { a: 1 };
eq("byte length of small object", jsonByteLength(small), Buffer.byteLength(JSON.stringify(small), "utf8"));
eq("serialization failure is undefined", jsonByteLength({ get x() { throw new Error("boom"); } }), undefined);

const kept = boundJsonPayload(small, opts);
eq("under the cap passes through", kept.truncated, false);
eq("under the cap keeps the value", kept.value, small);
eq("under the cap reports bytes", kept.bytes, jsonByteLength(small) as number);

const big = { a: "x".repeat(200) };
const capped = boundJsonPayload(big, opts);
eq("over the cap is truncated", capped.truncated, true);
const cappedValue = capped.value as { truncated: boolean; bytes: number; preview: string };
eq("preview flag is set", cappedValue.truncated, true);
eq("preview length is bounded", cappedValue.preview.length, opts.previewChars);
eq("preview matches the serialized head", cappedValue.preview, JSON.stringify(big).slice(0, opts.previewChars));
eq("reported bytes exceed the cap", cappedValue.bytes > opts.maxBytes, true);

eq("undefined stays undefined", boundJsonPayload(undefined, opts).truncated, false);

const circular: any = {};
circular.self = circular;
const uncapped = boundJsonPayload(circular, opts);
eq("unserializable values are left alone", uncapped.truncated, false);
check("unserializable values keep identity", uncapped.value === circular);
eq("unserializable bytes are zero", uncapped.bytes, 0);

console.log(`\nbounded-payload: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
