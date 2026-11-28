import { describe, expect, test } from "bun:test";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import {
  appendEvidenceToDisk,
  createEvidenceRecord,
  evaluateEvidenceGate,
  evidenceLedgerPathForRoot,
  isEvidenceStale,
  loadEvidenceFromDisk,
} from "./evidence-ledger";

describe("evidence-ledger", () => {
  test("detects fresh vs stale artifact fingerprints", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "evidence-ledger-"));
    try {
      const fileA = path.join(tmp, "a.ts");
      const fileB = path.join(tmp, "b.ts");
      fs.writeFileSync(fileA, "export const a = 1;\n");
      fs.writeFileSync(fileB, "export const b = 2;\n");

      const rec = createEvidenceRecord({
        command: "bun test",
        exitCode: 0,
        cwd: tmp,
        targetFiles: [fileA],
      });

      expect(isEvidenceStale(rec, [fileA], tmp).stale).toBe(false);
      expect(evaluateEvidenceGate([rec], [fileA], tmp).ok).toBe(true);

      // Missing newly edited file triggers stale gate
      expect(evaluateEvidenceGate([rec], [fileA, fileB], tmp).ok).toBe(false);

      // Modifying fileA after passing check invalidates fingerprint
      fs.writeFileSync(fileA, "export const a = 999;\n");
      const staleRes = evaluateEvidenceGate([rec], [fileA], tmp);
      expect(staleRes.ok).toBe(false);
      expect(staleRes.reason).toContain("stale");
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });

  test("rejects when only failing verification commands exist", () => {
    const rec = createEvidenceRecord({
      command: "make test",
      exitCode: 2,
      cwd: "/tmp",
      targetFiles: [],
    });
    const gate = evaluateEvidenceGate([rec], [], "/tmp");
    expect(gate.ok).toBe(false);
    expect(gate.reason).toContain("No passing verification command");
  });

  test("persists and reloads bounded ledger JSON", () => {
    const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "evidence-disk-"));
    try {
      const ledgerPath = path.join(tmp, "evidence.json");
      for (let i = 0; i < 5; i++) {
        appendEvidenceToDisk(
          ledgerPath,
          createEvidenceRecord({
            command: `cmd-${i}`,
            exitCode: 0,
            cwd: tmp,
            targetFiles: [],
          }),
          3,
        );
      }
      const loaded = loadEvidenceFromDisk(ledgerPath);
      expect(loaded.records).toHaveLength(3);
      expect(loaded.records[0].command).toBe("cmd-2");
      expect(evidenceLedgerPathForRoot(tmp)).toBe(evidenceLedgerPathForRoot(path.join(tmp, ".")));
    } finally {
      fs.rmSync(tmp, { recursive: true, force: true });
    }
  });
});
