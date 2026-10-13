import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { extractWrittenPath, lintFileByExtension } from "../post-edit-lint";

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

function have(bin: string, arg = "--version"): boolean {
  try {
    const r = spawnSync(bin, [arg], { encoding: "utf-8" });
    return !r.error;
  } catch {
    return false;
  }
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "post-edit-lint-"));
const w = (name: string, content: string): string => {
  const p = path.join(tmp, name);
  fs.writeFileSync(p, content);
  return p;
};

try {
  // extractWrittenPath
  check("extractWrittenPath: path field", extractWrittenPath({ path: "/a/b.go" }) === "/a/b.go");
  check("extractWrittenPath: file_path field", extractWrittenPath({ file_path: "/a/c.py" }) === "/a/c.py");
  check("extractWrittenPath: prefers path over file_path", extractWrittenPath({ path: "/p", file_path: "/f" }) === "/p");
  check("extractWrittenPath: missing → null", extractWrittenPath({}) === null);
  check("extractWrittenPath: undefined → null", extractWrittenPath(undefined) === null);
  check("extractWrittenPath: non-string → null", extractWrittenPath({ path: 42 as unknown as string }) === null);

  // non-file / unsupported
  check("lint: nonexistent path → not checked", lintFileByExtension(path.join(tmp, "nope.go")).checked === false);
  check("lint: directory → not checked", lintFileByExtension(tmp).checked === false);

  // JSON (native, always available)
  const jOk = lintFileByExtension(w("ok.json", '{"a":1,"b":[2,3]}'));
  check("lint: valid JSON → ok", jOk.checked === true && jOk.ok === true);
  const jBad = lintFileByExtension(w("bad.json", '{"a":1,,}'));
  check("lint: invalid JSON → not ok + message", jBad.checked === true && jBad.ok === false && !!jBad.message);

  // Makefile MUST NOT be linted (make -n $(shell) RCE trap)
  const mk = lintFileByExtension(w("Makefile", "all:\n\t@echo hi\n"));
  check("lint: Makefile is NOT checked (RCE trap avoided)", mk.checked === false && mk.skipped === "unsupported extension");
  const mkExt = lintFileByExtension(w("build.mk", "x := $(shell echo hi)\n"));
  check("lint: *.mk is NOT checked", mkExt.checked === false);

  // unsupported extension
  const txt = lintFileByExtension(w("readme.txt", "hello"));
  check("lint: unsupported .txt → not checked", txt.checked === false && txt.skipped === "unsupported extension");

  // shell (bash -n is ~always available in this env)
  if (have("bash", "-c")) {
    const shOk = lintFileByExtension(w("ok.sh", "#!/usr/bin/env bash\nset -e\necho hi\n"));
    check("lint: valid shell → ok", shOk.checked === true && shOk.ok === true);
    const shBad = lintFileByExtension(w("bad.sh", "if true; then\n echo x\n# missing fi\n"));
    check("lint: invalid shell (missing fi) → not ok", shBad.checked === true && shBad.ok === false);
  } else {
    console.log("skip: shell checks (bash unavailable)");
  }

  // python
  if (have("python3")) {
    const pyOk = lintFileByExtension(w("ok.py", "def f(x):\n    return x + 1\n"));
    check("lint: valid python → ok", pyOk.checked === true && pyOk.ok === true);
    const pyBad = lintFileByExtension(w("bad.py", "def f(:\n    return\n"));
    check("lint: invalid python → not ok", pyBad.checked === true && pyBad.ok === false);

    // yaml (skip gracefully if pyyaml absent)
    const yOk = lintFileByExtension(w("ok.yaml", "a: 1\nb:\n  - x\n  - y\n"));
    check("lint: yaml valid → ok OR skipped(no pyyaml)", yOk.ok === true && (yOk.checked === true || yOk.skipped?.includes("yaml")));
    const yBad = lintFileByExtension(w("bad.yaml", "a: 1\n  b: 2\n :\n- broken: ]["));
    check("lint: yaml invalid → not ok OR skipped(no pyyaml)", yBad.checked === false ? yBad.ok === true : yBad.ok === false);

    // toml (tomllib is stdlib in python 3.11+; skip gracefully otherwise)
    const tOk = lintFileByExtension(w("ok.toml", 'title = "x"\n[tbl]\nk = 1\n'));
    check("lint: toml valid → ok OR skipped(no tomllib)", tOk.ok === true && (tOk.checked === true || tOk.skipped?.includes("toml")));
    const tBad = lintFileByExtension(w("bad.toml", "k = = 1\n"));
    check("lint: toml invalid → not ok OR skipped(no tomllib)", tBad.checked === false ? tBad.ok === true : tBad.ok === false);
  } else {
    console.log("skip: python/yaml/toml checks (python3 unavailable)");
  }

  // go (skip gracefully if gofmt absent)
  if (have("gofmt")) {
    const goOk = lintFileByExtension(w("ok.go", "package main\n\nfunc main() {\n\tprintln(1)\n}\n"));
    check("lint: valid go → ok", goOk.checked === true && goOk.ok === true);
    const goBad = lintFileByExtension(w("bad.go", "package main\nfunc main( {\n"));
    check("lint: invalid go → not ok", goBad.checked === true && goBad.ok === false);
    // gofmt must NOT modify the file in place (advisory, non-invasive)
    const goSrc = "package main\nfunc  main(){println( 1 )}\n"; // deliberately unformatted but valid
    const goPath = w("unformatted.go", goSrc);
    lintFileByExtension(goPath);
    check("lint: gofmt does NOT modify file in place", fs.readFileSync(goPath, "utf-8") === goSrc);
  } else {
    console.log("skip: go checks (gofmt unavailable)");
  }
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}

console.log(`\npost-edit-lint: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
