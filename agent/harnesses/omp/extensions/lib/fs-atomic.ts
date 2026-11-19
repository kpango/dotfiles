import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Write a file atomically: write to a sibling temp file, then rename it over the
 * target. A crash or concurrent read mid-write can never observe a torn/partial
 * file — readers see either the previous complete content or the new complete
 * content. The temp file is created in the same directory so the rename stays on
 * one filesystem (rename across filesystems is not atomic). On failure the temp
 * file is best-effort removed and the original error is re-thrown.
 */
export function writeFileAtomic(filePath: string, content: string): void {
  const dir = path.dirname(filePath);
  const tmp = path.join(dir, `.${path.basename(filePath)}.${process.pid}.${Date.now()}.tmp`);
  try {
    fs.writeFileSync(tmp, content, "utf-8");
    fs.renameSync(tmp, filePath);
  } catch (err) {
    try {
      fs.unlinkSync(tmp);
    } catch {
      // temp file may not exist; ignore
    }
    throw err;
  }
}
