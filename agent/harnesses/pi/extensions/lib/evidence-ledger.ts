/**
 * Pstack-inspired Evidence Ledger (Command Exit Codes + Artifact SHA-256 Fingerprints)
 *
 * Tracks executed verification commands and file fingerprints so completion gates
 * can detect stale ("unverified after edit") claims instead of trusting prose.
 */

import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

export function evidenceLedgerPathForRoot(root: string): string {
  const key = createHash("sha256").update(path.resolve(root)).digest("hex").slice(0, 16);
  return path.join(os.tmpdir(), "pi-evidence", `${key}.json`);
}

export interface VerificationEvidence {
  command: string;
  exitCode: number;
  timestamp: string;
  cwd: string;
  files: Record<string, string>;
  outputSnippet?: string;
}

export interface EvidenceLedgerState {
  version: 1;
  records: VerificationEvidence[];
}

export function hashFileSha256(absPath: string): string {
  try {
    if (!fs.existsSync(absPath)) return "missing";
    const st = fs.statSync(absPath);
    if (!st.isFile()) return `nonfile:${st.size}`;
    return createHash("sha256").update(fs.readFileSync(absPath)).digest("hex");
  } catch {
    return "unreadable";
  }
}

export function snapshotFileDigests(filePaths: Iterable<string>, cwd: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const p of filePaths) {
    const abs = path.isAbsolute(p) ? p : path.resolve(cwd, p);
    out[abs] = hashFileSha256(abs);
  }
  return out;
}

export function createEvidenceRecord(params: {
  command: string;
  exitCode: number;
  cwd: string;
  targetFiles: Iterable<string>;
  outputSnippet?: string;
  timestamp?: string;
}): VerificationEvidence {
  return {
    command: params.command,
    exitCode: params.exitCode,
    timestamp: params.timestamp ?? new Date().toISOString(),
    cwd: params.cwd,
    files: snapshotFileDigests(params.targetFiles, params.cwd),
    outputSnippet: params.outputSnippet?.slice(0, 600),
  };
}

export function isEvidenceStale(
  record: VerificationEvidence,
  currentFiles: Iterable<string>,
  cwd: string = record.cwd,
): { stale: boolean; changedFiles: string[]; missingFiles: string[] } {
  const changedFiles: string[] = [];
  const missingFiles: string[] = [];

  for (const raw of currentFiles) {
    const abs = path.isAbsolute(raw) ? raw : path.resolve(cwd, raw);
    const recordedHash = record.files[abs];
    const currentHash = hashFileSha256(abs);
    if (recordedHash === undefined) {
      missingFiles.push(abs);
    } else if (recordedHash !== currentHash) {
      changedFiles.push(abs);
    }
  }

  return {
    stale: changedFiles.length > 0 || missingFiles.length > 0,
    changedFiles,
    missingFiles,
  };
}

export function evaluateEvidenceGate(
  records: VerificationEvidence[],
  targetFiles: string[],
  cwd: string,
): { ok: boolean; reason: string; latest?: VerificationEvidence } {
  const latestPass = [...records].reverse().find((r) => r.exitCode === 0);
  if (!latestPass) {
    return {
      ok: false,
      reason: "No passing verification command (exitCode=0) recorded in Evidence Ledger.",
    };
  }
  const freshness = isEvidenceStale(latestPass, targetFiles, cwd);
  if (freshness.stale) {
    const details = [
      freshness.changedFiles.length ? `modified after check: ${freshness.changedFiles.join(", ")}` : "",
      freshness.missingFiles.length ? `not covered by check: ${freshness.missingFiles.join(", ")}` : "",
    ]
      .filter(Boolean)
      .join("; ");
    return {
      ok: false,
      reason: `Latest passing evidence (${latestPass.command}) is stale (${details}).`,
      latest: latestPass,
    };
  }
  return {
    ok: true,
    reason: `Verified fresh by '${latestPass.command}' at ${latestPass.timestamp}.`,
    latest: latestPass,
  };
}

export function appendEvidenceToDisk(ledgerPath: string, record: VerificationEvidence, maxEntries = 50): void {
  fs.mkdirSync(path.dirname(ledgerPath), { recursive: true });
  let state: EvidenceLedgerState = { version: 1, records: [] };
  if (fs.existsSync(ledgerPath)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(ledgerPath, "utf-8")) as EvidenceLedgerState;
      if (parsed && Array.isArray(parsed.records)) {
        state = parsed;
      }
    } catch {
      // Overwrite corrupted ledger cleanly.
    }
  }
  state.records.push(record);
  if (state.records.length > maxEntries) {
    state.records = state.records.slice(-maxEntries);
  }
  fs.writeFileSync(ledgerPath, JSON.stringify(state, null, 2) + "\n", "utf-8");
}

export function loadEvidenceFromDisk(ledgerPath: string): EvidenceLedgerState {
  if (!fs.existsSync(ledgerPath)) return { version: 1, records: [] };
  try {
    const parsed = JSON.parse(fs.readFileSync(ledgerPath, "utf-8")) as EvidenceLedgerState;
    if (parsed && Array.isArray(parsed.records)) return parsed;
  } catch {
    // Ignore malformed ledger.
  }
  return { version: 1, records: [] };
}
