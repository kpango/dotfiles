// security-gate.ts の書込ゲートが write / edit / ast_edit を同じに扱うことの検証(T17)。
// 実 decide.py を経由する(callDecide)。hasUI=false なので ask/block はいずれも block に落ちる。
// ast_edit は「対象を特定できる実在の通常ファイル」のみ各 gate で評価し、それ以外(path 無し・
// ディレクトリ・glob・存在しない・"."・末尾 "/")は fail-closed で block する。
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import securityGate, { WRITE_TOOLS } from "../security-gate";

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

const root = path.resolve(__dirname, "../../../..");
let handler: any;
securityGate({ on: (_e: string, fn: any) => (handler = fn) } as any);

const T = fs.mkdtempSync(path.join(os.tmpdir(), "t17-sg-"));
const VALD = path.join(T, "vdaas", "vald"); // isValdRepo 相当のパスセグメント
const mk = (abs: string, body = "package x\n") => {
  fs.mkdirSync(path.dirname(abs), { recursive: true });
  fs.writeFileSync(abs, body);
  return abs;
};
const protectedFile = path.join(root, "agent/write-scope-rules.json"); // Tier B(実在)
const sshKey = mk(path.join(T, ".ssh", "id_rsa"), "x");
const pbFile = mk(path.join(VALD, "apis/grpc/v1/vald/zz_t17.pb.go"));
const goFile = mk(path.join(VALD, "pkg/gateway/zz_t17.go"));
const okFile = mk(path.join(T, "ok.txt"), "hello");

const run = async (toolName: string, input: Record<string, unknown>, cwd = root) =>
  handler({ toolName, input }, { cwd, hasUI: false, ui: { confirm: async () => true } });
const blocked = (r: any) => !!r && r.block === true;

// 入力形状: edit は edits[].newText、ast_edit は ops[].out、write は content。path は共通。
const shape = (tool: string, p: string, text = "x") =>
  tool === "write"
    ? { path: p, content: text }
    : tool === "edit"
      ? { path: p, edits: [{ oldText: "a", newText: text }] }
      : { path: p, ops: [{ pat: "a", out: text }] };

try {
  check("WRITE_TOOLS contains exactly write/edit/ast_edit", WRITE_TOOLS.size === 3 && ["write", "edit", "ast_edit"].every((t) => WRITE_TOOLS.has(t)));

  for (const tool of ["write", "edit", "ast_edit"]) {
    check(`${tool}: Tier B protected file is blocked`, blocked(await run(tool, shape(tool, protectedFile))));
    check(`${tool}: sensitive path (.ssh/id_rsa) is blocked`, blocked(await run(tool, shape(tool, sshKey))));
    check(`${tool}: Vald Law 1 (generated .pb.go) is blocked`, blocked(await run(tool, shape(tool, pbFile), VALD)));
    check(`${tool}: Vald Law 3 (panic in prod .go) is blocked`, blocked(await run(tool, shape(tool, goFile, "func f() { panic(1) }"), VALD)));
    check(`${tool}: ordinary regular file with clean content is allowed (control)`, (await run(tool, shape(tool, okFile, "hello"))) === undefined);
  }

  check("ast_edit: panic only in pat (removed text) is allowed", (await run("ast_edit", { path: goFile, ops: [{ pat: "panic($A)", out: "return $A" }] }, VALD)) === undefined);
  check("ast_edit: file_path field also evaluated", blocked(await run("ast_edit", { file_path: protectedFile, ops: [] })));
  check("ast_edit: paths[] of regular files evaluates every element (one protected -> block)", blocked(await run("ast_edit", { paths: [okFile, protectedFile], ops: [] })));
  check("ast_edit: paths[] of only clean regular files is allowed", (await run("ast_edit", { paths: [okFile], ops: [{ pat: "a", out: "b" }] })) === undefined);
  check("read tool is not gated", (await run("read", { path: protectedFile })) === undefined);

  // ---- edit / write: ツール側の path 正規化(@ / file:// / 迷子 ':' / ~ / Unicode 空白)を介した迂回 ----
  // OMP expandPath は生の文字列とは別の場所へ解決するため、生の形だけを評価すると保護 path を素通りできる。
  for (const tool of ["write", "edit"]) {
    const nbsp = String.fromCharCode(0xa0);
    const forms: [string, string][] = [
      ["@ prefix", `@${protectedFile}`],
      ["file:// URL", `file://${protectedFile}`],
      ["stray ':' prefix", `:${protectedFile}`],
      ["@~ shorthand to sensitive path", "@~/.ssh/id_rsa"],
      ["~ expansion to sensitive path", "~/.ssh/id_rsa"],
      ["percent-encoded file:// URL", `file://${protectedFile.replace("write-scope", "write%2Dscope")}`],
      ["NBSP in the path resolves to a space-named file the gate must still see", `${path.dirname(protectedFile)}/${path.basename(protectedFile).replace("-", nbsp)}`],
    ];
    for (const [label, p] of forms) {
      // NBSP 形は別名のファイルを指す(保護対象ではない)ので block 対象から除く: 正規化が壊れず評価できることだけ確認する。
      if (label.startsWith("NBSP")) {
        check(`${tool}: ${label} does not crash the gate`, (await run(tool, shape(tool, p))) !== null);
        continue;
      }
      check(`${tool}: ${label} cannot hide a protected target`, blocked(await run(tool, shape(tool, p))), p);
    }
    check(`${tool}: @ / file:// forms of a clean file stay allowed (control)`, (await run(tool, shape(tool, `@${okFile}`, "hello"))) === undefined && (await run(tool, shape(tool, `file://${okFile}`, "hello"))) === undefined);
    check(`${tool}: a literal '@name' relative path is not rewritten`, (await run(tool, shape(tool, "@literal-name.txt", "hello"), T)) === undefined);
  }

  // ---- 識別力のあるテスト: 保護対象を fixed_absolute_path_patterns(末尾一致ではない)の ${HOME}/…/.claude/settings.json にする ----
  // 末尾一致(*/agent/…)の保護 path は `<cwd>/@/abs/agent/x` のようなデコイ形でも block されるため、正規化の有無を区別できない。
  // cwd は T(保護 path の外)なので、デコイ形は fixed 絶対パターンに当たらず、正規化後だけが当たる。
  const SETTINGS = path.join(os.homedir(), "go/src/github.com/kpango/dotfiles/.claude/settings.json");
  const HOMEREL = "~/go/src/github.com/kpango/dotfiles/.claude/settings.json";
  const input = (tool: string, p: string) => shape(tool, p);
  for (const tool of ["write", "edit"]) {
    check(`${tool}: [real tool shape control] absolute fixed-pattern path is blocked`, blocked(await run(tool, input(tool, SETTINGS), T)));
    const decoys: [string, string][] = [
      ["@ prefix", `@${SETTINGS}`],
      ["file:// URL", `file://${SETTINGS}`],
      ["stray ':' prefix", `:${SETTINGS}`],
      ["~ expansion", HOMEREL],
      ["@~ shorthand", `@${HOMEREL}`],
      ["percent-encoded file:// URL", `file://${SETTINGS.replace("settings", "setting%73")}`],
      ["hashline [path#TAG] wrapper", `[${SETTINGS}#ABCD]`],
      ["hashline [path] wrapper", `[${SETTINGS}]`],
    ];
    for (const [label, p] of decoys) {
      check(`${tool}: ${label} cannot hide a fixed-pattern protected target`, blocked(await run(tool, input(tool, p), T)), p);
    }
    check(`${tool}: file_path and path are both evaluated (file_path is a decoy)`, blocked(await run(tool, { file_path: okFile, path: SETTINGS, content: "x", edits: [] }, T)));
    check(`${tool}: file_path and path are both evaluated (path is a decoy)`, blocked(await run(tool, { file_path: SETTINGS, path: okFile, content: "x", edits: [] }, T)));
  }

  // ---- edit の実形状: config.yml の edit.mode=hashline では入力は {input: string}(書込先は本文の [PATH#TAG] / MV / apply_patch ヘッダ) ----
  const hl = (...sections: string[]) => ({ input: `*** Begin Patch\n${sections.join("\n")}\n*** End Patch\n` });
  const put = (p: string, body = "+x") => `[${p}#ABCD]\nPUT 1.=1:\n${body}`;
  check("edit {input} hashline: single protected header is blocked (no path key at all)", blocked(await run("edit", hl(put(SETTINGS)), T)));
  check("edit {input} hashline: REM (delete file) of a protected header is blocked", blocked(await run("edit", hl(`[${SETTINGS}#ABCD]\nREM`), T)));
  check("edit {input} hashline: second of several headers protected is blocked (OMP only supplies paths[])", blocked(await run("edit", hl(put(okFile), put(SETTINGS)), T)));
  check("edit {input} hashline: MV destination protected is blocked", blocked(await run("edit", hl(`[${okFile}#ABCD]\nMV ${SETTINGS}`), T)));
  check("edit {input} hashline: header wrapped in quotes is blocked", blocked(await run("edit", hl(put(`"${SETTINGS}"`)), T)));
  check("edit {input} hashline: legacy ¶ header is blocked", blocked(await run("edit", { input: `¶${SETTINGS}#ABCD\nPUT 1.=1:\n+x\n` }, T)));
  check("edit {input} hashline: CRLF line endings are parsed", blocked(await run("edit", { input: `*** Begin Patch\r\n[${SETTINGS}#ABCD]\r\nPUT 1.=1:\r\n+x\r\n*** End Patch\r\n` }, T)));
  check("edit {input} apply_patch: *** Update File: protected is blocked", blocked(await run("edit", { input: `*** Begin Patch\n*** Update File: ${SETTINGS}\n@@\n-a\n+b\n*** End Patch\n` }, T)));
  check("edit {input} apply_patch: *** Add File: protected is blocked", blocked(await run("edit", { input: `*** Begin Patch\n*** Add File: ${SETTINGS}\n+x\n*** End Patch\n` }, T)));
  check("edit {input} apply_patch: *** Delete File: protected is blocked", blocked(await run("edit", { input: `*** Begin Patch\n*** Delete File: ${SETTINGS}\n*** End Patch\n` }, T)));
  check("edit {input} apply_patch: *** Move to: protected is blocked", blocked(await run("edit", { input: `*** Begin Patch\n*** Update File: ${okFile}\n*** Move to: ${SETTINGS}\n@@\n-a\n+b\n*** End Patch\n` }, T)));
  check("edit {input}: no identifiable target is blocked fail-closed", blocked(await run("edit", { input: "PUT 1.=1:\n+x\n" }, T)));
  check("edit {input}: OMP-supplied path+paths of a protected file is blocked", blocked(await run("edit", { ...hl(put(SETTINGS)), path: SETTINGS, paths: [SETTINGS] }, T)));
  check("edit {input}: control — clean regular file via hashline header is allowed", (await run("edit", hl(put(okFile, "+hello")), T)) === undefined);
  check("edit {input}: control — clean regular file via apply_patch is allowed", (await run("edit", { input: `*** Begin Patch\n*** Update File: ${okFile}\n@@\n-a\n+hello\n*** End Patch\n` }, T)) === undefined);
  // Vald Law の内容検査は本文の追加行(+)に掛かる
  check("edit {input} hashline: Vald Law 3 (panic in prod .go) via + lines is blocked", blocked(await run("edit", hl(put(goFile, "+func f() { panic(1) }")), VALD)));
  check("edit {input} hashline: generated .pb.go header is blocked (Vald Law 1)", blocked(await run("edit", hl(put(pbFile)), VALD)));
  check("edit {input} hashline: clean Go edit in the Vald repo is allowed (control)", (await run("edit", hl(put(goFile, "+func f() error { return nil }")), VALD)) === undefined);

  // ---- replace / patch モードの実スキーマ(src/edit/schemas.ts): {path, old_string, new_string} / {path, edits:[{op, rename, diff}]} ----
  check("edit replace-mode: panic in new_string of a prod .go is blocked (Vald Law 3)", blocked(await run("edit", { path: goFile, old_string: "a", new_string: "func f() { panic(1) }" }, VALD)));
  check("edit replace-mode: clean new_string is allowed (control)", (await run("edit", { path: goFile, old_string: "a", new_string: "func f() error { return nil }" }, VALD)) === undefined);
  check("edit patch-mode: panic on a + line of a diff is blocked", blocked(await run("edit", { path: goFile, edits: [{ op: "update", diff: "@@\n-a\n+func f() { panic(1) }\n" }] }, VALD)));
  check("edit patch-mode: panic only on a removed (-) line is allowed", (await run("edit", { path: goFile, edits: [{ op: "update", diff: "@@\n-func f() { panic(1) }\n+func f() error { return nil }\n" }] }, VALD)) === undefined);
  check("edit patch-mode: create with panic as the whole diff is blocked", blocked(await run("edit", { path: goFile, edits: [{ op: "create", diff: "func f() { panic(1) }\n" }] }, VALD)));
  check("edit patch-mode: rename destination protected is blocked", blocked(await run("edit", { path: okFile, edits: [{ op: "update", rename: SETTINGS, diff: "@@\n-a\n+b\n" }] }, T)));
  check("edit patch-mode: rename of a clean file to a clean name is allowed (control)", (await run("edit", { path: okFile, edits: [{ op: "update", rename: path.join(T, "renamed.txt"), diff: "@@\n-a\n+hello\n" }] }, T)) === undefined);

  // ---- ast_edit: ツールは外側の二重引用符と先頭 ':' を正規化で剥がす(デコイ名のファイルでゲートを通して本物を書く迂回) ----
  const decoy = mk(path.join(T, '"agent', 'hooks', 'omp', 'security-gate.ts"'), "x");
  check("ast_edit: a path wrapped in double quotes is blocked fail-closed", blocked(await run("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: [`"${path.join(T, "agent/hooks/pi/security-gate.ts")}"`] }, T)));
  check("ast_edit: a relative quoted path naming an existing decoy file is blocked", blocked(await run("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: ['"agent/hooks/pi/security-gate.ts"'] }, T)) && fs.existsSync(decoy));
  check("ast_edit: a path with a leading ':' is blocked fail-closed", blocked(await run("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: [`:${okFile}`] }, T)));

  // ---- internal URL(ssh / vault / cfg / conflict)は実際の書込先が見えないので fail-closed。local:// と xd:// は対象外 ----
  for (const tool of ["write", "edit"]) {
    for (const u of ["ssh://host/etc/passwd", "vault://x/y", "cfg://theme/save", "conflict://1", `${okFile}:conflict://1`, "@cfg://theme/save"]) {
      check(`${tool}: internal URL ${u} is blocked fail-closed`, blocked(await run(tool, shape(tool, u), T)), u);
    }
  }
  check("write: local:// scratch path is still allowed (control)", (await run("write", { path: "local://scratch.md", content: "x" }, T)) === undefined);
  check("write: xd://resolve (applying an ast_edit preview) is still allowed (control)", (await run("write", { path: "xd://resolve", content: "x" }, T)) === undefined);

  // ---- Windows 系のパス(OMP の expandPath は解釈するが、この gate は Linux/macOS 向けで写さない)は fail-closed ----
  for (const tool of ["write", "edit"]) {
    for (const p of ["C:\\Users\\x\\.ssh\\id_rsa", "C:/Users/x/file", "\\\\server\\share\\f", "\\rooted", "~\\.ssh\\id_rsa", "@\\rooted", ":C:\\x", "[C:\\x#ABCD]"]) {
      check(`${tool}: Windows-style path ${JSON.stringify(p)} is blocked fail-closed`, blocked(await run(tool, shape(tool, p), T)), p);
    }
  }
  check("write: a normal relative path containing a colon or backslash later on is not misclassified (control)", (await run("write", { path: "notes/a:b.txt", content: "x" }, T)) === undefined);

  // ---- ast_edit のプレビューと適用(write xd://resolve)の間に対象が差し替えられた場合 ----
  {
    const preview = async (file: string) => run("ast_edit", { ops: [{ pat: "a", out: "b" }], paths: [file] }, T);
    const resolveWrite = async () => run("write", { path: "xd://resolve", content: "apply" }, T);
    const rejectWrite = async () => run("write", { path: "xd://reject", content: "discard" }, T);
    const swapDir = path.join(T, "swap");
    const fresh = (name: string) => mk(path.join(swapDir, name), "a");
    const toSymlink = (file: string, target: string) => {
      fs.rmSync(file);
      fs.symlinkSync(target, file);
    };
    // 保留中のプレビューは適用が通っても残る(どれが適用されるか分からないため)ので、ケースごとに xd://reject で記録を空にする。
    await rejectWrite();
    const f1 = fresh("same.ts");
    check("ast_edit preview of a regular file is allowed", (await preview(f1)) === undefined);
    check("ast_edit apply with the target unchanged is allowed", (await resolveWrite()) === undefined);

    await rejectWrite();
    const f2 = fresh("to-protected.ts");
    await preview(f2);
    toSymlink(f2, SETTINGS);
    check("ast_edit apply after the target became a symlink to a protected file is blocked", blocked(await resolveWrite()));

    await rejectWrite();
    const f3 = fresh("to-other.ts");
    await preview(f3);
    toSymlink(f3, okFile);
    check("ast_edit apply after the target became a symlink to ANY other file is blocked (resolution changed)", blocked(await resolveWrite()));

    await rejectWrite();
    const f4 = fresh("dangling.ts");
    await preview(f4);
    toSymlink(f4, path.join(T, "does-not-exist-yet", "x"));
    check("ast_edit apply after the target became a dangling symlink is blocked", blocked(await resolveWrite()));

    await rejectWrite();
    const f5 = fresh("gone.ts");
    await preview(f5);
    fs.rmSync(f5);
    check("ast_edit apply after the target was simply deleted is allowed (nothing to write through)", (await resolveWrite()) === undefined);

    await rejectWrite();
    const f6 = fresh("rejected.ts");
    await preview(f6);
    toSymlink(f6, SETTINGS);
    check("xd://reject discards the staged previews: a later resolve is not blocked by them", (await rejectWrite()) === undefined && (await resolveWrite()) === undefined);

    // OMP は重ねたプレビューを個別に保留する: 古い方の対象を差し替えて、新しい方のプレビューを挟んでも止まる
    await rejectWrite();
    const f7 = fresh("stacked-old.ts");
    const f8 = fresh("stacked-new.ts");
    await preview(f7);
    await preview(f8);
    toSymlink(f7, SETTINGS);
    check("stacked previews: swapping the OLDER staged target is blocked at apply", blocked(await resolveWrite()));
    check("stacked previews: the block persists until xd://reject (a successful apply does not forget them)", blocked(await resolveWrite()));
    await rejectWrite();
    check("stacked previews: after xd://reject apply is allowed again", (await resolveWrite()) === undefined);

    await rejectWrite();
    check("write xd://resolve variants (case, wrapper, @) are checked the same way", await (async () => {
      const f9 = fresh("variant.ts");
      await preview(f9);
      toSymlink(f9, SETTINGS);
      const forms = ["XD://Resolve", "@xd://resolve", "[xd://resolve]", ":xd://resolve", "xd://resolve/reason"];
      return (await Promise.all(forms.map((p) => run("write", { path: p, content: "apply" }, T)))).every((r) => blocked(r));
    })());
    await rejectWrite();
  }
  // ---- 実パーサ(OMP native: crates/edit)との突き合わせ ----
  // hashline の MV: native の keyword_tail は MV の後ろに行末・':'・空白を許し、DEST は引用符を unquote する
  for (const [label, line] of [["MV: dest", `MV: ${SETTINGS}`], ["MV:dest", `MV:${SETTINGS}`], ["MV dest", `MV ${SETTINGS}`], ['MV "dest"', `MV "${SETTINGS}"`], ["MV 'dest'", `MV '${SETTINGS}'`]] as [string, string][]) {
    check(`edit {input} hashline: ${label} (protected destination) is blocked`, blocked(await run("edit", hl(`[${okFile}#ABCD]\n${line}`), T)), line);
  }
  // sloppy モード: `*** Edit File: path [all]`(大小文字無視・コロン省略可・" は JSON unquote)、本文は '+' 行ではなく生テキスト
  const sloppyOk = `*** Edit File: ${okFile}\n*** Find\nold\n*** Replace\nnew`;
  check("edit {input} sloppy: a protected *** Edit File: header is blocked", blocked(await run("edit", { input: `*** Edit File: ${SETTINGS}\n*** Find\na\n*** Replace\nb\n` }, T)));
  check("edit {input} sloppy: a quoted header with the trailing ' all' flag is blocked", blocked(await run("edit", { input: `*** Edit File: ${JSON.stringify(SETTINGS)} all\n*** Find\na\n*** Replace\nb\n` }, T)));
  check("edit {input} sloppy: a second header after a decoy (lower case, no colon) is blocked", blocked(await run("edit", { input: `${sloppyOk}\n*** edit file ${SETTINGS}\n*** Find\na\n*** Replace\nb\n` }, T)));
  check("edit {input} sloppy: a clean file edit is allowed (control)", (await run("edit", { input: sloppyOk }, T)) === undefined);
  check("edit {input} sloppy: the replacement text (not a + row) is scanned by the Vald Laws", blocked(await run("edit", { input: `*** Edit File: ${goFile}\n*** Find\nreturn nil\n*** Replace\nfunc f() { panic(1) }\n` }, VALD)));
  check("edit {input} sloppy: a clean replacement in the Vald repo is allowed (control)", (await run("edit", { input: `*** Edit File: ${goFile}\n*** Find\nreturn nil\n*** Replace\nreturn err\n` }, VALD)) === undefined);

  // allowlist: local:// xd:// file:// だけ通す。proc:// は実行中プロセスの stdin への書込(bash ゲートの迂回)、agent:// out:// も効果が見えない
  for (const u of ["proc://1", "agent://x", "out://x", "PROC://1", "[proc://1#ABCD]", ":proc://1", "@proc://1"]) {
    check(`write: internal URL ${u} is blocked (allowlist is local/xd/file only)`, blocked(await run("write", { path: u, content: "ls\n" }, T)), u);
  }

  // ---- 独立再レビューの指摘: 字下げ・大文字小文字・_input・未知の *** 行・ReDoS ----
  const decoyOk = `[${okFile}#ABCD]\nPUT 1.=1:\n+x`;
  check("edit {input}: an indented hashline header hidden after a decoy section is blocked", blocked(await run("edit", hl(decoyOk, `  [${SETTINGS}#ABCD]\n  PUT 1.=1:\n+x`), T)));
  check("edit {input}: an indented MV after a decoy header is blocked", blocked(await run("edit", hl(`[${okFile}#ABCD]\n  MV ${SETTINGS}`), T)));
  check("edit {input} apply_patch: an indented *** Add File: after a decoy is blocked", blocked(await run("edit", { input: `*** Begin Patch\n*** Add File: ${okFile}\n+x\n *** Add File: ${SETTINGS}\n+y\n*** End Patch\n` }, T)));
  // おとり(正規ヘッダの clean ファイル)を併記して、パース分岐そのものが無いと block されない形にする(対象 0 件の fail-closed に頼らない)。
  const okHdr = `*** Update File: ${okFile}\n@@\n-a\n+hello`;
  check("edit {input} apply_patch: a lower-case / extra-space header after a decoy is blocked", blocked(await run("edit", { input: `*** Begin Patch\n${okHdr}\n*** add  file: ${SETTINGS}\n+y\n*** End Patch\n` }, T)) && blocked(await run("edit", { input: `*** Begin Patch\n${okHdr}\n***  Move to: ${SETTINGS}\n*** End Patch\n` }, T)));
  check("edit {input}: an unrecognised *** directive after a decoy is blocked fail-closed", blocked(await run("edit", { input: `*** Begin Patch\n${okHdr}\n*** Frobnicate File: ${SETTINGS}\n+x\n*** End Patch\n` }, T)));
  check("edit {input}: *** Begin/End Patch and *** End of File alone are not suspicious (control)", (await run("edit", { input: `*** Begin Patch\n*** Update File: ${okFile}\n@@\n-a\n+hello\n*** End of File\n*** End Patch\n` }, T)) === undefined);
  check("edit: a protected target only in _input (input is empty) is blocked", blocked(await run("edit", { input: "", _input: put(SETTINGS), path: okFile }, T)));
  check("edit: a protected MV only in _input while input names a decoy is blocked", blocked(await run("edit", { input: put(okFile), _input: `[${okFile}#ABCD]\nMV ${SETTINGS}` }, T)));
  {
    // 行末・語間に大量の空白を置く入力で正規表現が O(n^2) にならない(同期処理なので timeout では止められない)
    const pad = " ".repeat(60000);
    const t0 = Date.now();
    await run("edit", { input: `*** Begin Patch\n*** Add File:${pad}a\n+x\n*** End Patch\n` }, T);
    await run("edit", { input: `[${okFile}#ABCD]\nMV a${pad}b\n` }, T);
    await run("edit", { input: `*** Begin Patch\n*** Update File: ${okFile}${pad}\n+x\n*** End Patch\n` }, T);
    const ms = Date.now() - t0;
    check("edit {input}: padding-heavy lines are parsed in linear time", ms < 5000, `${ms}ms`);
  }

  // ---- fail-closed: ast_edit が対象ファイルを特定できない形は全て block ----
  const fc = async (name: string, input: Record<string, unknown>, cwd = root) =>
    check(`ast_edit fail-closed: ${name}`, blocked(await run("ast_edit", input, cwd)));
  const ops = [{ pat: "a", out: "b" }];
  await fc("no path at all", { ops });
  await fc("glob key naming a protected file, no path", { glob: "agent/write-scope-rules.json", ops });
  await fc("glob key with an ordinary regular file path", { path: okFile, glob: "**/*.json", ops });
  await fc("relative directory 'agent/rules'", { path: "agent/rules", ops });
  await fc("relative directory 'agent/rules/' (trailing slash)", { path: "agent/rules/", ops });
  await fc("'.' (repo root)", { path: ".", ops });
  await fc("relative directory 'agent/scripts/hooks'", { path: "agent/scripts/hooks", ops });
  await fc("glob in path 'agent/*.json'", { path: "agent/*.json", ops });
  await fc("empty path", { path: "", ops });
  await fc("nonexistent regular-looking file", { path: path.join(T, "nope.txt"), ops });
  await fc("Vald repo directory (gateway)", { path: path.join(VALD, "pkg/gateway"), lang: "go", ops }, VALD);
  await fc("Vald directory containing generated .pb.go", { path: path.join(VALD, "apis/grpc/v1/vald"), ops }, VALD);
  await fc("paths[] with a directory element", { paths: [okFile, T], ops });
  await fc("paths[] empty and no path", { paths: [], ops });
  await fc("non-string path", { path: 5, ops });
  await fc("non-array paths", { paths: "x", ops });
  await fc("regular file path + non-array paths", { path: okFile, paths: "x", ops });

  // ---- ツールの path 正規化(~ / @ / file: / Unicode 空白)とゲートの解決先が食い違う形は block ----
  // cwd 配下にデコイを置く(ゲートがデコイを見て ALLOW、ツールは別の保護ファイルを書く攻撃の再現)。
  const D = fs.mkdtempSync(path.join(os.tmpdir(), "t17-sg-decoy-"));
  try {
    const NBSP = String.fromCharCode(0xa0);
    const ZWSP = String.fromCharCode(0x200b);
    const decoy = (rel: string) => mk(path.join(D, rel), "x");
    const homeSettings = "~/.claude/settings.json";
    const fileUrl = "file://" + protectedFile;
    const shapes: Array<[string, string, string | null]> = [
      // [name, path 文字列, デコイを作る相対パス(null = デコイ無し)]
      ["tilde home settings (decoy present)", homeSettings, "~/.claude/settings.json"],
      ["tilde home settings (no decoy)", homeSettings, null],
      ["bare tilde", "~", null],
      ["tilde user form", "~root/x", "~root/x"],
      ["@-prefixed hook file (decoy present)", "@agent/hooks/pi/security-gate.ts", "@agent/hooks/pi/security-gate.ts"],
      ["@-prefixed hook file (no decoy)", "@agent/hooks/pi/security-gate.ts", null],
      ["@-prefixed rules json (decoy present)", "@agent/write-scope-rules.json", "@agent/write-scope-rules.json"],
      ["@-prefixed absolute path", "@" + protectedFile, null],
      ["file:// Tier B absolute path (decoy present)", fileUrl, "file:" + protectedFile],
      ["file:// Tier B absolute path (no decoy)", fileUrl, null],
      ["FILE:// upper-case scheme", "FILE://" + protectedFile, null],
      ["file:/ single-slash form", "file:" + protectedFile, "file:" + protectedFile],
      ["leading space on a real file", " " + okFile, null],
      ["trailing space on a real file", okFile + " ", null],
      ["trailing newline on a real file", okFile + String.fromCharCode(10), null],
      ["NBSP in path (decoy present)", path.join(D, "a" + NBSP + "b.txt"), "a" + NBSP + "b.txt"],
      ["NBSP trailing (real file + NBSP)", okFile + NBSP, null],
      ["zero-width space in path", path.join(D, "a" + ZWSP + "b.txt"), "a" + ZWSP + "b.txt"],
      ["control char (TAB) in path", path.join(D, "a" + String.fromCharCode(9) + "b.txt"), "a" + String.fromCharCode(9) + "b.txt"],
      // 末尾構造が保護パターンに一致しないデコイ(symlink 経由で本物が保護ファイル): ゲートがデコイを評価すると素通りする
      ["@-prefixed symlink-to-protected (regular decoy present)", "@lnk-prot.json", "@lnk-prot.json"],
      ["file:// symlink-to-protected (regular decoy present)", "file://" + path.join(D, "lnk-prot.json"), "file:" + path.join(D, "lnk-prot.json")],
      ["FILE:// symlink-to-protected (regular decoy present)", "FILE://" + path.join(D, "lnk-prot.json"), "FILE:" + path.join(D, "lnk-prot.json")],
      // C0/DEL/C1/方向制御/ゼロ幅(\s に入らないもの)
      ["control char U+0001 in path", path.join(D, "a" + String.fromCharCode(1) + "b.txt"), "a" + String.fromCharCode(1) + "b.txt"],
      ["control char ESC in path", path.join(D, "a" + String.fromCharCode(0x1b) + "b.txt"), "a" + String.fromCharCode(0x1b) + "b.txt"],
      ["DEL in path", path.join(D, "a" + String.fromCharCode(0x7f) + "b.txt"), "a" + String.fromCharCode(0x7f) + "b.txt"],
      ["C1 control U+009B in path", path.join(D, "a" + String.fromCharCode(0x9b) + "b.txt"), "a" + String.fromCharCode(0x9b) + "b.txt"],
      ["LRM U+200E in path", path.join(D, "a" + String.fromCharCode(0x200e) + "b.txt"), "a" + String.fromCharCode(0x200e) + "b.txt"],
      ["RLO U+202E in path", path.join(D, "a" + String.fromCharCode(0x202e) + "b.txt"), "a" + String.fromCharCode(0x202e) + "b.txt"],
      ["word joiner U+2060 in path", path.join(D, "a" + String.fromCharCode(0x2060) + "b.txt"), "a" + String.fromCharCode(0x2060) + "b.txt"],
      ["BOM U+FEFF in path", path.join(D, "a" + String.fromCharCode(0xfeff) + "b.txt"), "a" + String.fromCharCode(0xfeff) + "b.txt"],
    ];
    fs.symlinkSync(protectedFile, path.join(D, "lnk-prot.json")); // 本物(@/file: を剥がした先)は Tier B 保護ファイルへの symlink
    for (const [name, p, decoyRel] of shapes) {
      if (decoyRel) decoy(decoyRel);
      await fc(name, { path: p, ops }, D);
      await fc(name + " [via paths[]]", { paths: [okFile, p], ops }, D);
    }
    // 対照: 通常の絶対/相対パス・内部に ASCII 空白を含む実在ファイルは従来どおり許可
    decoy("plain.txt");
    decoy("my file.txt");
    check("ast_edit: relative existing regular file is allowed (control)", (await run("ast_edit", { path: "plain.txt", ops }, D)) === undefined);
    check("ast_edit: absolute existing regular file is allowed (control)", (await run("ast_edit", { path: path.join(D, "plain.txt"), ops }, D)) === undefined);
    check("ast_edit: ./relative existing regular file is allowed (control)", (await run("ast_edit", { path: "./plain.txt", ops }, D)) === undefined);
    check("ast_edit: inner ASCII space in an existing file name is allowed (control)", (await run("ast_edit", { path: "my file.txt", ops }, D)) === undefined);
  } finally {
    fs.rmSync(D, { recursive: true, force: true });
  }

  // symlink は realpath でも評価する: 無害な名前のリンク先が Tier B 保護ファイルなら block
  const lnk = path.join(T, "innocent-link.json");
  fs.symlinkSync(protectedFile, lnk);
  check("ast_edit: symlink to a protected file is blocked via realpath", blocked(await run("ast_edit", { path: lnk, ops })));

  // edit / write の挙動は不変: ディレクトリや無 path でも従来どおり(fail-closed の対象外)
  check("edit unchanged: directory path is not fail-closed", (await run("edit", { path: T, edits: [{ newText: "x" }] })) === undefined);
  check("write unchanged: no path returns undefined", (await run("write", { content: "x" })) === undefined);
} finally {
  fs.rmSync(T, { recursive: true, force: true });
}

console.log(`\nsecurity-gate: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
