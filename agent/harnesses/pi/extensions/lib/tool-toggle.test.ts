import { isToolEnabled, setToolState, setReadOnlyMode } from "../tool-toggle";

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

const testSet = new Set<string>();

// 1. Initially all tools enabled
check("Initially 'bash' is enabled", isToolEnabled(testSet, "bash"));
check("Initially 'write' is enabled", isToolEnabled(testSet, "write"));

// 2. Disable specific tool
setToolState(testSet, "bash", false);
check("'bash' is disabled after toggle off", !isToolEnabled(testSet, "bash"));
check("'write' remains enabled", isToolEnabled(testSet, "write"));

// 3. Re-enable tool
setToolState(testSet, "bash", true);
check("'bash' is re-enabled after toggle on", isToolEnabled(testSet, "bash"));

// 4. Read-only mode
setReadOnlyMode(testSet, true);
check("Read-only disables 'write'", !isToolEnabled(testSet, "write"));
check("Read-only disables 'edit'", !isToolEnabled(testSet, "edit"));
check("Read-only preserves 'read'", isToolEnabled(testSet, "read"));
check("Read-only preserves 'grep'", isToolEnabled(testSet, "grep"));

setReadOnlyMode(testSet, false);
check("Deactivating read-only enables 'write'", isToolEnabled(testSet, "write"));
check("Deactivating read-only enables 'edit'", isToolEnabled(testSet, "edit"));

console.log(`\ntool-toggle: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
