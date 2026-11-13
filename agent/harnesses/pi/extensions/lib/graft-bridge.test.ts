import { isRawSearchToolName, truncateForGraftQuery } from "../graft-bridge";

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

// isRawSearchToolName: matches Pi's own built-in tool-name literals — confirmed by reading
// @earendil-works/pi-coding-agent's types.d.ts (ReadToolCallEvent.toolName = "read",
// GrepToolCallEvent.toolName = "grep", FindToolCallEvent.toolName = "find",
// LsToolCallEvent.toolName = "ls"; Pi has no "glob" tool name, unlike Claude Code).
check("read is a raw search tool", isRawSearchToolName("read"));
check("grep is a raw search tool", isRawSearchToolName("grep"));
check("find is a raw search tool", isRawSearchToolName("find"));
check("ls is a raw search tool", isRawSearchToolName("ls"));
check("bash is not a raw search tool", !isRawSearchToolName("bash"));
check("edit is not a raw search tool", !isRawSearchToolName("edit"));
check("write is not a raw search tool", !isRawSearchToolName("write"));
check("a custom tool name is not a raw search tool", !isRawSearchToolName("graphify_query"));

// truncateForGraftQuery: keeps short prompts intact, caps very long ones so a huge user prompt
// never becomes an oversized argv element to `executor call`.
check("short text passes through unchanged", truncateForGraftQuery("hello world") === "hello world");
{
  const long = "x".repeat(1000);
  const truncated = truncateForGraftQuery(long, 50);
  check("long text is truncated to the max length", truncated.length === 50, `got length ${truncated.length}`);
  check("truncated text is a prefix of the original", long.startsWith(truncated.replace(/…$/, "")));
}
check("empty text stays empty", truncateForGraftQuery("") === "");

console.log(`\ngraft-bridge: ${pass} passed, ${fail} failed`);
if (fail > 0) process.exit(1);
