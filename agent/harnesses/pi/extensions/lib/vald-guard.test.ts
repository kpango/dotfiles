import { checkValdLaws, isValdRepo } from "../vald-guard";

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

console.log(`\nvald-guard: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
