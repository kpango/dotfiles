/**
 * Vald Law Enforcement Guard Extension for Pi Coding Agent
 *
 * Enforces the 5 Vald Laws deterministically before any tool execution:
 * 1. Never edit generated *.pb.go / *_vtproto.pb.go directly — edit .proto and run make proto/all.
 * 2. Never run go build / cargo build / kubectl apply / helm install directly in vdaas/vald — use make targets.
 * 3. Never introduce a bare panic() in a production code path.
 * 4. Never call log.Fatal() outside main().
 * 5. Never silently discard an error (_ = err) — handle or propagate it.
 */

import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export interface ValdLawCheckResult {
  allowed: boolean;
  lawNumber?: number;
  violation?: string;
  suggestion?: string;
}

export function isValdRepo(cwd: string): boolean {
  const norm = cwd.replace(/\\/g, "/").toLowerCase();
  // Match `vdaas/vald` (canonical) or `vald` as a full path COMPONENT, not a bare
  // substring — otherwise unrelated dirs like `/home/x/valdemort` false-positive
  // as the Vald repo and wrongly trip the (repo-scoped) Vald Laws.
  return norm.includes("vdaas/vald") || /(^|\/)vald(\/|$)/.test(norm);
}

export function checkValdLaws(
  toolName: string,
  input: Record<string, any>,
  cwd: string
): ValdLawCheckResult {
  const inVald = isValdRepo(cwd);

  // Vald Laws are repository-scoped (see project AGENTS.md "Vald Law (when
  // working in vdaas/vald)"). Only enforce inside the Vald repo; otherwise
  // legitimate `panic()`, `log.Fatal`, `_ = err`, and generated-file edits in
  // any other Go project would be wrongly blocked. (Law 2 was already gated on
  // inVald; Laws 1/3/4/5 previously fired everywhere — this closes that gap.)
  if (!inVald) {
    return { allowed: true };
  }

  // 1. File edits / writes
  if (toolName === "edit" || toolName === "write") {
    const filePath = (input.path || input.file || input.TargetFile || "") as string;
    const baseName = path.basename(filePath);

    // Law 1: Never edit generated protobuf code
    if (baseName.endsWith(".pb.go") || baseName.endsWith("_vtproto.pb.go")) {
      return {
        allowed: false,
        lawNumber: 1,
        violation: `Vald Law 1 Violation: Cannot directly edit generated file '${baseName}'.`,
        suggestion: "Edit the underlying .proto file and run `make proto/all` instead.",
      };
    }

    const content = (input.content || input.CodeContent || input.ReplacementContent || "") as string;
    const isTestFile = baseName.endsWith("_test.go");

    if (filePath.endsWith(".go") && !isTestFile) {
      // Law 3: Bare panic in production code
      if (/\bpanic\s*\(/.test(content)) {
        return {
          allowed: false,
          lawNumber: 3,
          violation: `Vald Law 3 Violation: Bare panic() detected in production code '${baseName}'.`,
          suggestion: "Return an explicit error or use robust error handling instead of panicking.",
        };
      }

      // Law 4: log.Fatal outside main
      const isMainFile = baseName === "main.go";
      if (!isMainFile && /\blog\.Fatal\s*\(/.test(content)) {
        return {
          allowed: false,
          lawNumber: 4,
          violation: `Vald Law 4 Violation: log.Fatal() detected outside main() in '${baseName}'.`,
          suggestion: "Propagate the error to the caller or log.Error() instead of aborting.",
        };
      }

      // Law 5: Silently discarding error
      if (/_\s*=\s*(?:[a-zA-Z0-9_.]+\.)?err\b/.test(content) || /_\s*=\s*err\b/.test(content)) {
        return {
          allowed: false,
          lawNumber: 5,
          violation: `Vald Law 5 Violation: Discarding error (_ = err) in '${baseName}'.`,
          suggestion: "Handle or propagate the error explicitly.",
        };
      }
    }
  }

  // 2. Command execution (already scoped to inVald by the early-return above).
  if (toolName === "bash") {
    const command = ((input.command || input.CommandLine || "") as string).trim();

    // Law 2: Build / K8s commands directly in Vald
    {
      const forbiddenPrefixes = ["go build", "cargo build", "kubectl apply", "helm install", "helm upgrade"];
      for (const prefix of forbiddenPrefixes) {
        // match word boundary
        const regex = new RegExp(`(^|[;&|\\s])${prefix}\\b`);
        if (regex.test(command)) {
          return {
            allowed: false,
            lawNumber: 2,
            violation: `Vald Law 2 Violation: Direct execution of '${prefix}' is prohibited in Vald repository.`,
            suggestion: "Use appropriate `make <target>` (e.g. `make build`, `make k8s/...`).",
          };
        }
      }
    }
  }

  return { allowed: true };
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    const check = checkValdLaws(event.toolName, event.input || {}, ctx.cwd);
    if (!check.allowed) {
      const msg = `🛡️ [VALD LAW ${check.lawNumber} BLOCKED]\n${check.violation}\n👉 ${check.suggestion}`;
      ctx.ui.notify(msg, "error");
      throw new Error(msg);
    }
  });
}
