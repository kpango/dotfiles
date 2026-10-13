import { isSafeCommand } from "../plan-mode";

let pass = 0;
let fail = 0;
function check(desc: string, ok: boolean) {
  if (ok) {
    console.log(`ok: ${desc}`);
    pass++;
  } else {
    console.log(`FAIL: ${desc}`);
    fail++;
  }
}

// Genuinely safe read-only commands are allowed.
check("git status is safe", isSafeCommand("git status"));
check("git diff HEAD is safe", isSafeCommand("git diff HEAD~1"));
check("grep pattern is safe", isSafeCommand("grep -rn foo ."));
check("go vet is safe", isSafeCommand("go vet ./..."));
check("empty command is safe", isSafeCommand("   "));
check("safe chained (git status && git diff) is safe", isSafeCommand("git status && git diff"));
check("rtk-wrapped safe command is safe", isSafeCommand("rtk git log --oneline"));
check("rtk with pipe is safe (rtk exception)", isSafeCommand("rtk 'git log | head'"));

// L2 regression: shell-level bypasses must be rejected.
check("command substitution $() is blocked", !isSafeCommand("git status $(rm -rf x)"));
check("backtick substitution is blocked", !isSafeCommand("git status `rm -rf x`"));
check("output redirection is blocked", !isSafeCommand("cat foo > bar"));
check("input redirection is blocked", !isSafeCommand("cat < /etc/passwd"));
check("embedded newline is blocked", !isSafeCommand("git status\nrm -rf x"));
check("carriage return is blocked", !isSafeCommand("git status\rrm -rf x"));

// `env` as an arbitrary command runner is no longer allowlisted.
check("env <cmd> is blocked (removed from allowlist)", !isSafeCommand("env rm -rf x"));

// find mutation/exec flags are blocked; plain find traversal is allowed.
check("find -delete is blocked", !isSafeCommand("find . -name '*.tmp' -delete"));
check("find -exec is blocked", !isSafeCommand("find . -type f -exec rm {} +"));
check("plain find traversal is safe", isSafeCommand("find . -name '*.go'"));

// Word-boundary: loose prefix matches must not slip through.
check("'category' does NOT match 'cat' prefix", !isSafeCommand("category-delete --all"));
check("'lsof' does NOT match 'ls' prefix", !isSafeCommand("lsof -i"));
check("chained bypass (git status; env rm) blocked", !isSafeCommand("git status; env rm -rf x"));

// L1 regression: `git branch` is read-only for listing but its mutating flags
// delete/rename/copy/force-move branches and must not be allowed in plan mode.
check("git branch (list) is safe", isSafeCommand("git branch"));
check("git branch -a is safe", isSafeCommand("git branch -a"));
check("git branch -v is safe", isSafeCommand("git branch -v"));
check("git branch --contains <sha> is safe", isSafeCommand("git branch --contains abc123"));
check("git branch -D is NOT safe (deletes)", !isSafeCommand("git branch -D foo"));
check("git branch -d is NOT safe (deletes)", !isSafeCommand("git branch -d foo"));
check("git branch -m is NOT safe (renames)", !isSafeCommand("git branch -m old new"));
check("git branch -f is NOT safe (force-moves)", !isSafeCommand("git branch -f main x"));
check("git branch --delete is NOT safe", !isSafeCommand("git branch --delete foo"));
check("git branch --force is NOT safe", !isSafeCommand("git branch --force main x"));

console.log(`\nplan-mode: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
