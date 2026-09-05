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

// 2. Law 1: pb.go edit blocking
const l1 = checkValdLaws("write", { path: "api/v1/vald/payload.pb.go", content: "package vald" }, "/repo");
check("Law 1 blocks pb.go write", !l1.allowed && l1.lawNumber === 1);

const l1vt = checkValdLaws("edit", { path: "api/v1/vald/payload_vtproto.pb.go" }, "/repo");
check("Law 1 blocks vtproto edit", !l1vt.allowed && l1vt.lawNumber === 1);

// 3. Law 2: direct go build in vald
const l2 = checkValdLaws("bash", { command: "go build ./cmd/vald" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 2 blocks go build in Vald", !l2.allowed && l2.lawNumber === 2);

const l2Allowed = checkValdLaws("bash", { command: "make build" }, "/home/kpango/go/src/github.com/vdaas/vald");
check("Law 2 allows make build in Vald", l2Allowed.allowed);

// 4. Law 3: bare panic
const l3 = checkValdLaws("edit", { path: "pkg/core/service.go", content: "if x == 0 { panic(\"fatal\") }" }, "/repo");
check("Law 3 blocks bare panic in prod go", !l3.allowed && l3.lawNumber === 3);

const l3Test = checkValdLaws("edit", { path: "pkg/core/service_test.go", content: "panic(\"test\")" }, "/repo");
check("Law 3 allows panic in test files", l3Test.allowed);

// 5. Law 4: log.Fatal outside main
const l4 = checkValdLaws("edit", { path: "pkg/core/service.go", content: "log.Fatal(err)" }, "/repo");
check("Law 4 blocks log.Fatal outside main", !l4.allowed && l4.lawNumber === 4);

const l4Main = checkValdLaws("edit", { path: "cmd/main.go", content: "log.Fatal(err)" }, "/repo");
check("Law 4 allows log.Fatal in main.go", l4Main.allowed);

// 6. Law 5: error discarding
const l5 = checkValdLaws("edit", { path: "pkg/core/service.go", content: "_ = err" }, "/repo");
check("Law 5 blocks _ = err", !l5.allowed && l5.lawNumber === 5);

console.log(`\nvald-guard: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
