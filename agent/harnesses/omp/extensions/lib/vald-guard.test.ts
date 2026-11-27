import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import valdGuard, { checkValdLaws, isValdRepo, WRITE_TOOLS } from "../vald-guard";

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

// 1. isValdRepo detection
check("isValdRepo: positive", isValdRepo("/home/kpango/go/src/github.com/vdaas/vald"));
check("isValdRepo: negative", !isValdRepo("/home/kpango/go/src/github.com/kpango/dotfiles"));
// L1 regression: `/vald` must match as a path COMPONENT, not a bare substring.
check("isValdRepo: /valdemort is NOT a Vald repo (substring boundary)", !isValdRepo("/home/x/valdemort/src"));
check("isValdRepo: trailing /vald matches", isValdRepo("/opt/clones/vald"));
check("isValdRepo: /vald/ component matches", isValdRepo("/opt/vald/rust"));

// 2. Law 1: pb.go edit blocking
const l1 = checkValdLaws("write", { path: "api/v1/vald/payload.pb.go", content: "package vald" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 1 blocks pb.go write", !l1.allowed && l1.lawNumber === 1);

const l1vt = checkValdLaws("edit", { path: "api/v1/vald/payload_vtproto.pb.go" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 1 blocks vtproto edit", !l1vt.allowed && l1vt.lawNumber === 1);

// 3. Law 2: direct go build in vald
const l2 = checkValdLaws("bash", { command: "go build ./cmd/vald" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 2 blocks go build in Vald", !l2.allowed && l2.lawNumber === 2);

const l2Allowed = checkValdLaws("bash", { command: "make build" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 2 allows make build in Vald", l2Allowed.allowed);

// 4. Law 3: bare panic
const l3 = checkValdLaws("edit", { path: "pkg/core/service.go", content: "if x == 0 { panic(\"fatal\") }" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 3 blocks bare panic in prod go", !l3.allowed && l3.lawNumber === 3);

const l3Test = checkValdLaws("edit", { path: "pkg/core/service_test.go", content: "panic(\"test\")" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 3 allows panic in test files", l3Test.allowed);

// 5. Law 4: log.Fatal outside main
const l4 = checkValdLaws("edit", { path: "pkg/core/service.go", content: "log.Fatal(err)" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 4 blocks log.Fatal outside main", !l4.allowed && l4.lawNumber === 4);

const l4Main = checkValdLaws("edit", { path: "cmd/main.go", content: "log.Fatal(err)" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 4 allows log.Fatal in main.go", l4Main.allowed);

// 6. Law 5: error discarding
const l5 = checkValdLaws("edit", { path: "pkg/core/service.go", content: "_ = err" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 5 blocks _ = err", !l5.allowed && l5.lawNumber === 5);

// 7. L1 regression: Laws 1/3/4/5 must NOT fire OUTSIDE the Vald repo (they are
// repo-scoped like Law 2). A non-Vald Go project must be able to use panic(),
// log.Fatal, `_ = err`, and edit generated .pb.go files freely.
const nonVald = "/home/kpango/go/src/github.com/kpango/other-project";
check("Law 1 does NOT block .pb.go edit outside Vald", checkValdLaws("edit", { path: "api.pb.go", content: "x" }, nonVald).allowed);
check("Law 3 does NOT block panic() outside Vald", checkValdLaws("write", { path: "server.go", content: "panic(\"x\")" }, nonVald).allowed);
check("Law 4 does NOT block log.Fatal outside Vald", checkValdLaws("edit", { path: "db.go", content: "log.Fatal(err)" }, nonVald).allowed);
check("Law 5 does NOT block _ = err outside Vald", checkValdLaws("edit", { path: "h.go", content: "_ = err" }, nonVald).allowed);
check("Law 2 does NOT block go build outside Vald", checkValdLaws("bash", { command: "go build ./..." }, nonVald).allowed);

// 8. OMP `edit` tool: edits[] array (newText / replacement / new_string) must be scanned (Laws 3/4/5)
const VALD = "/home/kpango/go/src/github.com/vdaas/vald";
const svc = "pkg/core/service.go";
for (const key of ["newText", "replacement", "new_string"]) {
  const e = (txt: string) => ({ path: svc, edits: [{ oldText: "x", [key]: txt }] });
  const r3 = checkValdLaws("edit", e("if x == 0 { panic(\"boom\") }"), VALD);
  check(`edits[].${key}: Law 3 blocks panic`, !r3.allowed && r3.lawNumber === 3);
  const r4 = checkValdLaws("edit", e("log.Fatal(err)"), VALD);
  check(`edits[].${key}: Law 4 blocks log.Fatal`, !r4.allowed && r4.lawNumber === 4);
  const r5 = checkValdLaws("edit", e("_ = err"), VALD);
  check(`edits[].${key}: Law 5 blocks _ = err`, !r5.allowed && r5.lawNumber === 5);
  check(`edits[].${key}: clean text allowed`, checkValdLaws("edit", e("return nil"), VALD).allowed);
}
// offending text only in the 2nd element of edits[]
const r3b = checkValdLaws("edit", { path: svc, edits: [{ newText: "return nil" }, { newText: "panic(1)" }] }, VALD);
check("edits[]: violation in a later element is caught", !r3b.allowed && r3b.lawNumber === 3);
// oldText/old_string (text being REMOVED) must not trigger
check("edits[]: oldText containing panic( is not scanned", checkValdLaws("edit", { path: svc, edits: [{ oldText: "panic(1)", newText: "return err" }] }, VALD).allowed);
// exemptions are preserved for edits[]
check("edits[]: test file exempt from Law 3", checkValdLaws("edit", { path: "pkg/a_test.go", edits: [{ newText: "panic(1)" }] }, VALD).allowed);
check("edits[]: main.go exempt from Law 4", checkValdLaws("edit", { path: "cmd/main.go", edits: [{ newText: "log.Fatal(err)" }] }, VALD).allowed);
check("edits[]: non-.go file not scanned", checkValdLaws("edit", { path: "README.md", edits: [{ newText: "panic(1)" }] }, VALD).allowed);
check("edits[]: not scanned outside Vald", checkValdLaws("edit", { path: svc, edits: [{ newText: "panic(1)" }] }, nonVald).allowed);
check("edits[]: malformed (non-array / non-object / non-string) is ignored without throwing",
  checkValdLaws("edit", { path: svc, edits: "panic(1)" as any }, VALD).allowed &&
  checkValdLaws("edit", { path: svc, edits: { newText: "panic(1)" } as any }, VALD).allowed &&
  checkValdLaws("edit", { path: svc, edits: [null, 5, { newText: 7 }] as any }, VALD).allowed);
check("edits[]: Law 1 still applies via path", (() => { const r = checkValdLaws("edit", { path: "a.pb.go", edits: [{ newText: "x" }] }, VALD); return !r.allowed && r.lawNumber === 1; })());

// 9. errors.New( inside edits[]: advisory pointing at internal/errors (notify, not block)
const adv = checkValdLaws("edit", { path: svc, edits: [{ newText: "return errors.New(\"x\")" }] }, VALD);
check("edits[]: errors.New( stays allowed (advisory only)", adv.allowed);
check("edits[]: errors.New( yields internal/errors advisory", typeof adv.advisory === "string" && adv.advisory.includes("internal/errors"), String(adv.advisory));
check("edits[]: no advisory for clean edit", checkValdLaws("edit", { path: svc, edits: [{ newText: "return nil" }] }, VALD).advisory === undefined);
check("edits[]: no advisory for errors.New in test file", checkValdLaws("edit", { path: "pkg/a_test.go", edits: [{ newText: "errors.New(\"x\")" }] }, VALD).advisory === undefined);
check("edits[]: errors.NewFoo( is not advisory-matched", checkValdLaws("edit", { path: svc, edits: [{ newText: "errors.NewFoo(x)" }] }, VALD).advisory === undefined);
// a hard violation still wins over the advisory
const both = checkValdLaws("edit", { path: svc, edits: [{ newText: "errors.New(\"x\"); panic(1)" }] }, VALD);
check("edits[]: blocking law wins over advisory", !both.allowed && both.lawNumber === 3);

// 10. Handler wiring: advisory => notify("warning") without throwing; violation => notify("error") + throw
{
  let h: any;
  valdGuard({ on: (_e: string, fn: any) => (h = fn) } as any);
  const notes: Array<[string, string]> = [];
  const ctx = { cwd: VALD, ui: { notify: (m: string, l: string) => notes.push([m, l]) } };
  let threw = false;
  try { await h({ toolName: "edit", input: { path: svc, edits: [{ newText: "errors.New(\"x\")" }] } }, ctx); } catch { threw = true; }
  check("handler: errors.New advisory notifies (warning) and does not throw", !threw && notes.length === 1 && notes[0][1] === "warning" && notes[0][0].includes("internal/errors"), JSON.stringify(notes));
  threw = false;
  try { await h({ toolName: "edit", input: { path: svc, edits: [{ newText: "panic(1)" }] } }, ctx); } catch { threw = true; }
  check("handler: edits[] panic throws and notifies (error)", threw && notes.length === 2 && notes[1][1] === "error", JSON.stringify(notes));
}

// 11. ast_edit (T17): edit/write と同じ書込ゲートに掛かる。ast_edit は実在する通常ファイルだけを許可し、
// 対象を特定できない形(path 無し・ディレクトリ・glob・存在しない・"."・末尾 "/")は fail-closed で block する。
{
  const T = fs.mkdtempSync(path.join(os.tmpdir(), "t17-vg-"));
  const VT = path.join(T, "vdaas", "vald"); // isValdRepo は `vdaas/vald` パスセグメントで判定する
  const mk = (rel: string, body = "package x\n") => {
    const f = path.join(VT, rel);
    fs.mkdirSync(path.dirname(f), { recursive: true });
    fs.writeFileSync(f, body);
    return f;
  };
  const pbf = mk("apis/grpc/v1/vald/zz_t17.pb.go");
  const gof = mk("pkg/gateway/zz_t17.go");
  const ast = (input: Record<string, any>) => checkValdLaws("ast_edit", input, VT);
  try {
    const a1 = ast({ path: pbf, ops: [{ pat: "a", out: "b" }] });
    check("ast_edit: Law 1 blocks generated pb.go file like edit", !a1.allowed && a1.lawNumber === 1, JSON.stringify(a1));
    const a3 = ast({ path: gof, ops: [{ pat: "return err", out: "panic(err)" }] });
    check("ast_edit: Law 3 blocks panic( in ops[].out like edits[]", !a3.allowed && a3.lawNumber === 3, JSON.stringify(a3));
    const a4 = ast({ path: gof, ops: [{ pat: "x", out: "log.Fatal(x)" }] });
    check("ast_edit: Law 4 blocks log.Fatal( in ops[].out", !a4.allowed && a4.lawNumber === 4, JSON.stringify(a4));
    const a5 = ast({ path: gof, ops: [{ pat: "x", out: "_ = err" }] });
    check("ast_edit: Law 5 blocks discarded error in ops[].out", !a5.allowed && a5.lawNumber === 5, JSON.stringify(a5));
    check("ast_edit: clean replacement on a regular file is allowed", ast({ path: gof, ops: [{ pat: "x", out: "return nil" }] }).allowed);
    check("ast_edit: panic only in pat (removed text) is allowed", ast({ path: gof, ops: [{ pat: "panic($A)", out: "return $A" }] }).allowed);
    check("ast_edit: outside Vald repo is not enforced", checkValdLaws("ast_edit", { path: pbf, ops: [{ pat: "a", out: "panic(1)" }] }, os.tmpdir()).allowed);
    check("ast_edit: malformed ops (non-array/non-object/non-string out) is ignored, no throw", ast({ path: gof, ops: [null, 3, { out: 5 }] }).allowed && ast({ path: gof, ops: "x" }).allowed);
    check("ast_edit: file_path / file / paths[] shapes also evaluated", !ast({ file_path: pbf, ops: [] }).allowed && !ast({ file: pbf, ops: [] }).allowed && !ast({ paths: [gof, pbf], ops: [] }).allowed);
    check("ast_edit: paths[] of only regular clean files is allowed", ast({ paths: [gof], ops: [{ pat: "x", out: "return nil" }] }).allowed);

    // fail-closed 形(いずれも Vald repo 内の ast_edit は block)
    const fc = (name: string, input: Record<string, any>) => {
      const r = ast(input);
      check(`ast_edit fail-closed: ${name}`, !r.allowed, JSON.stringify(r));
    };
    fc("no path at all", { ops: [{ pat: "a", out: "b" }] });
    fc("glob key without path", { glob: "**/*.go", ops: [{ pat: "a", out: "b" }] });
    fc("glob key with a regular file path", { path: gof, glob: "**/*.go", ops: [] });
    fc("directory (Vald gateway)", { path: path.join(VT, "pkg/gateway"), lang: "go", ops: [{ pat: "a", out: "b" }] });
    fc("directory containing generated .pb.go", { path: path.join(VT, "apis/grpc/v1/vald"), ops: [] });
    fc("directory with trailing slash", { path: path.join(VT, "pkg/gateway") + "/", ops: [] });
    fc("relative '.' (cwd is the repo)", { path: ".", ops: [] });
    fc("empty path", { path: "", ops: [] });
    fc("glob chars in path", { path: path.join(VT, "pkg/**/*.go"), ops: [] });
    fc("brace glob in path", { path: path.join(VT, "pkg/{a,b}.go"), ops: [] });
    fc("nonexistent file", { path: path.join(VT, "pkg/gateway/nonexistent_t17.go"), ops: [] });
    fc("paths[] with one directory", { paths: [gof, path.join(VT, "pkg")], ops: [] });
    fc("paths[] empty array and no path", { paths: [], ops: [] });
    fc("non-string path", { path: 5, ops: [] });
    fc("non-array paths", { paths: "x", ops: [] });
    fc("regular file path + non-array paths", { path: gof, paths: "x", ops: [] });

    // ---- ツール側 path 正規化(~ / @ / file: / Unicode 空白)とゲートの解決先が食い違う形は block ----
    {
      const NBSP = String.fromCharCode(0xa0);
      const dk = (rel: string) => mk(rel, "package x\n");
      const forms: Array<[string, string, string | null]> = [
        ["tilde path (decoy present)", "~/zz_t17.go", "~/zz_t17.go"],
        ["tilde path (no decoy)", "~/zz_t17.go", null],
        ["@-prefixed pb.go (decoy present)", "@apis/grpc/v1/vald/zz_t17.pb.go", "@apis/grpc/v1/vald/zz_t17.pb.go"],
        ["@-prefixed pb.go (no decoy)", "@apis/grpc/v1/vald/zz_t17.pb.go", null],
        ["@-prefixed absolute path", "@" + pbf, null],
        ["file:// pb.go absolute path (decoy present)", "file://" + pbf, "file:" + pbf],
        ["file:// pb.go absolute path (no decoy)", "file://" + pbf, null],
        ["FILE:// upper-case scheme", "FILE://" + pbf, null],
        ["leading space on a real file", " " + gof, null],
        ["trailing space on a real file", gof + " ", null],
        ["NBSP in file name (decoy present)", path.join(VT, "pkg", "a" + NBSP + "b.go"), "pkg/a" + NBSP + "b.go"],
        ["NBSP trailing (real file + NBSP)", gof + NBSP, null],
        ["control char (TAB) in file name", path.join(VT, "pkg", "a" + String.fromCharCode(9) + "b.go"), "pkg/a" + String.fromCharCode(9) + "b.go"],
        ["@-prefixed symlink-to-pb.go (regular decoy present)", "@lnk.go", "@lnk.go"],
        ["file:// symlink-to-pb.go (regular decoy present)", "file://" + path.join(VT, "lnk.go"), "file:" + path.join(VT, "lnk.go")],
        ["control char U+0001 in file name", path.join(VT, "pkg", "a" + String.fromCharCode(1) + "b.go"), "pkg/a" + String.fromCharCode(1) + "b.go"],
        ["DEL in file name", path.join(VT, "pkg", "a" + String.fromCharCode(0x7f) + "b.go"), "pkg/a" + String.fromCharCode(0x7f) + "b.go"],
        ["C1 control U+009B in file name", path.join(VT, "pkg", "a" + String.fromCharCode(0x9b) + "b.go"), "pkg/a" + String.fromCharCode(0x9b) + "b.go"],
        ["ZWSP U+200B in file name", path.join(VT, "pkg", "a" + String.fromCharCode(0x200b) + "b.go"), "pkg/a" + String.fromCharCode(0x200b) + "b.go"],
        ["LRM U+200E in file name", path.join(VT, "pkg", "a" + String.fromCharCode(0x200e) + "b.go"), "pkg/a" + String.fromCharCode(0x200e) + "b.go"],
        ["RLO U+202E in file name", path.join(VT, "pkg", "a" + String.fromCharCode(0x202e) + "b.go"), "pkg/a" + String.fromCharCode(0x202e) + "b.go"],
      ];
      fs.symlinkSync(pbf, path.join(VT, "lnk.go")); // @/file: を剥がした先の本物は生成 .pb.go への symlink
      for (const [name, p, decoyRel] of forms) {
        if (decoyRel) dk(decoyRel);
        fc(name, { path: p, ops: [] });
        fc(name + " [via paths[]]", { paths: [gof, p], ops: [] });
      }
      dk("plain.go");
      dk("my file.go");
      check("ast_edit: relative existing regular file is allowed (control)", checkValdLaws("ast_edit", { path: "plain.go", ops: [{ pat: "x", out: "return nil" }] }, VT).allowed);
      check("ast_edit: inner ASCII space in an existing file name is allowed (control)", checkValdLaws("ast_edit", { path: "my file.go", ops: [{ pat: "x", out: "return nil" }] }, VT).allowed);
    }

    // symlink は realpath 解決後でも評価される(Vald 外の名前でも .pb.go 実体なら block)
    const lnk = path.join(T, "innocent.txt");
    fs.symlinkSync(pbf, lnk);
    const rs = ast({ path: lnk, ops: [] });
    check("ast_edit: symlink to a .pb.go is evaluated on its realpath", !rs.allowed && rs.lawNumber === 1, JSON.stringify(rs));

    // edit / write は不変(ディレクトリ・無 path でも従来どおり判定しない)
    check("edit unchanged: directory path is not fail-closed", checkValdLaws("edit", { path: path.join(VT, "pkg/gateway") }, VT).allowed);
    check("write unchanged: no path is not fail-closed", checkValdLaws("write", { content: "x" }, VT).allowed);
  } finally {
    fs.rmSync(T, { recursive: true, force: true });
  }
  check("WRITE_TOOLS contains exactly edit/write/ast_edit", WRITE_TOOLS.size === 3 && ["edit", "write", "ast_edit"].every((t) => WRITE_TOOLS.has(t)));
  const T2 = fs.mkdtempSync(path.join(os.tmpdir(), "t17-vg2-"));
  try {
    const VT2 = path.join(T2, "vdaas", "vald");
    fs.mkdirSync(VT2, { recursive: true });
    const f2 = path.join(VT2, "a.go");
    fs.writeFileSync(f2, "package x\n");
    let h2: any;
    valdGuard({ on: (_e: string, fn: any) => (h2 = fn) } as any);
    const ctx2 = { cwd: VT2, ui: { notify: () => {} } };
    let threw = false;
    try { await h2({ toolName: "ast_edit", input: { path: f2, ops: [{ pat: "x", out: "panic(1)" }] } }, ctx2); } catch { threw = true; }
    check("handler: ast_edit panic throws (blocked)", threw);
    threw = false;
    try { await h2({ toolName: "ast_edit", input: { path: VT2, ops: [] } }, ctx2); } catch { threw = true; }
    check("handler: ast_edit on a directory throws (fail-closed)", threw);
  } finally {
    fs.rmSync(T2, { recursive: true, force: true });
  }
}

// edit の実形状: config.yml の edit.mode=hashline では入力は {input: string}(書込先は本文のヘッダ、内容は + 行)。
{
  const VALD = "/home/kpango/go/src/github.com/vdaas/vald";
  const OTHER = "/home/kpango/go/src/github.com/kpango/dotfiles";
  const hl = (...sections: string[]) => ({ input: `*** Begin Patch\n${sections.join("\n")}\n*** End Patch\n` });
  const put = (p: string, body = "+x") => `[${p}#ABCD]\nPUT 1.=1:\n${body}`;
  const ap = (p: string, body = "+x") => ({ input: `*** Begin Patch\n*** Update File: ${p}\n@@\n-a\n${body}\n*** End Patch\n` });
  check("edit {input} hashline: generated .pb.go header is blocked (Law 1)", !checkValdLaws("edit", hl(put("api/v1/vald/payload.pb.go")), VALD).allowed);
  check("edit {input} hashline: panic in a + line of a prod .go is blocked (Law 3)", checkValdLaws("edit", hl(put("pkg/core/service.go", "+func f() { panic(1) }")), VALD).lawNumber === 3);
  check("edit {input} hashline: panic in a _test.go is allowed", checkValdLaws("edit", hl(put("pkg/core/service_test.go", "+func f() { panic(1) }")), VALD).allowed);
  check("edit {input} hashline: second header is a .pb.go (several sections) is blocked", !checkValdLaws("edit", hl(put("pkg/a.go", "+ok"), put("api/x.pb.go")), VALD).allowed);
  check("edit {input} hashline: MV to a .pb.go destination is blocked", !checkValdLaws("edit", hl("[pkg/a.go#ABCD]\nMV api/x.pb.go"), VALD).allowed);
  check("edit {input} apply_patch: *** Update File: .pb.go is blocked", !checkValdLaws("edit", ap("api/x.pb.go"), VALD).allowed);
  check("edit {input} apply_patch: panic in a + line is blocked", checkValdLaws("edit", ap("pkg/core/service.go", "+func f() { panic(1) }"), VALD).lawNumber === 3);
  check("edit {input}: no identifiable target is blocked fail-closed in the Vald repo", !checkValdLaws("edit", { input: "PUT 1.=1:\n+x\n" }, VALD).allowed);
  check("edit {input}: a clean Go edit is allowed (control)", checkValdLaws("edit", hl(put("pkg/core/service.go", "+func f() error { return nil }")), VALD).allowed);
  check("edit {input}: outside the Vald repo nothing is enforced (control)", checkValdLaws("edit", hl(put("api/x.pb.go")), OTHER).allowed);
  check("write path wrapped as [x.pb.go#TAG] is blocked (Law 1)", !checkValdLaws("write", { path: "[api/v1/vald/payload.pb.go#ABCD]", content: "package vald" }, VALD).allowed);
  check("write path wrapped as [x.pb.go] is blocked (Law 1)", !checkValdLaws("write", { path: "[api/v1/vald/payload.pb.go]", content: "package vald" }, VALD).allowed);
  // replace / patch モードの実スキーマ
  check("edit replace-mode: panic in top-level new_string is blocked (Law 3)", checkValdLaws("edit", { path: "pkg/core/service.go", old_string: "a", new_string: "func f() { panic(1) }" }, VALD).lawNumber === 3);
  check("edit patch-mode: panic on a + line of edits[].diff is blocked (Law 3)", checkValdLaws("edit", { path: "pkg/core/service.go", edits: [{ op: "update", diff: "@@\n-a\n+func f() { panic(1) }\n" }] }, VALD).lawNumber === 3);
  check("edit patch-mode: panic only on a - line is allowed", checkValdLaws("edit", { path: "pkg/core/service.go", edits: [{ op: "update", diff: "@@\n-func f() { panic(1) }\n+func f() error { return nil }\n" }] }, VALD).allowed);
  check("edit patch-mode: create diff is the whole content (panic blocked)", checkValdLaws("edit", { path: "pkg/core/service.go", edits: [{ op: "create", diff: "func f() { panic(1) }\n" }] }, VALD).lawNumber === 3);
  check("edit patch-mode: rename to a .pb.go destination is blocked (Law 1)", !checkValdLaws("edit", { path: "pkg/core/service.go", edits: [{ op: "update", rename: "api/x.pb.go", diff: "@@\n-a\n+b\n" }] }, VALD).allowed);
  check("edit patch-mode: rename to a clean destination is allowed (control)", checkValdLaws("edit", { path: "pkg/core/service.go", edits: [{ op: "update", rename: "pkg/core/other.go", diff: "@@\n-a\n+b\n" }] }, VALD).allowed);
  // 独立再レビューの指摘
  check("edit patch-mode: a .txt renamed to a .go carries its panic text into the Law 3 check", checkValdLaws("edit", { path: "pkg/notes.txt", edits: [{ op: "update", rename: "pkg/core/x.go", diff: "@@\n-a\n+func f() { panic(1) }\n" }] }, VALD).lawNumber === 3);
  check("edit {input}: an indented header hidden after a decoy section is blocked (Law 1)", !checkValdLaws("edit", hl(put("pkg/a.go", "+ok"), "  [api/x.pb.go#ABCD]\n  PUT 1.=1:\n+y"), VALD).allowed);
  check("edit {input}: an indented MV after a decoy header is blocked (Law 1)", !checkValdLaws("edit", hl("[pkg/a.go#ABCD]\n  MV api/x.pb.go"), VALD).allowed);
  // おとり(正規ヘッダの clean ファイル)を併記して、パース分岐そのものが無いと block されない形にする
  const okHdr = "*** Update File: pkg/a.go\n@@\n-a\n+func f() error { return nil }";
  check("edit {input} apply_patch: a lower-case / extra-space header after a decoy is blocked (Law 1)", !checkValdLaws("edit", { input: `*** Begin Patch\n${okHdr}\n*** add  file: api/x.pb.go\n+y\n*** End Patch\n` }, VALD).allowed);
  check("edit {input}: an unrecognised *** directive after a decoy is blocked fail-closed", !checkValdLaws("edit", { input: `*** Begin Patch\n${okHdr}\n*** Frobnicate File: pkg/b.go\n+x\n*** End Patch\n` }, VALD).allowed);
  check("edit: a Law 1 target only in _input is blocked", !checkValdLaws("edit", { input: "", _input: put("api/x.pb.go") }, VALD).allowed);
  check("edit {input}: *** Begin/End Patch and *** End of File alone are not suspicious (control)", checkValdLaws("edit", { input: "*** Begin Patch\n*** Update File: pkg/a.go\n@@\n-a\n+func f() error { return nil }\n*** End of File\n*** End Patch\n" }, VALD).allowed);
  check("ast_edit: a double-quoted path is not evaluated as a plain file (fail-closed in the Vald repo)", !checkValdLaws("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: ['"api/x.pb.go"'] }, VALD).allowed);
  check("ast_edit: a path with a leading ':' is fail-closed in the Vald repo", !checkValdLaws("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: [":api/x.pb.go"] }, VALD).allowed);
}

console.log(`\nvald-guard: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
