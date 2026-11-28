/**
 * OMP セッション履歴の保持ポリシー。
 *
 * `~/.pi/agent/sessions/<project>/<timestamp>_<id>.jsonl` は巨大な tool 出力を
 * そのまま含むため(実測 1 セッション 417MB)、無制限に溜まる。OMP v19 には
 * 保持設定が無いので、明示的に指定されたときだけ古いセッションを削除する。
 * 既定は dry-run で、`apply` を渡したときだけ実削除する。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

/** OMP のプロジェクト別セッションディレクトリ名(`~/go/src/x` -> `-go-src-x`、`/tmp` -> `-tmp`)。 */
export function sessionProjectDirName(cwd: string, home: string = os.homedir()): string {
  const absolute = path.resolve(cwd);
  const rel = path.relative(home, absolute);
  const base = rel && !rel.startsWith("..") ? rel : absolute;
  return `-${base.split(path.sep).filter(Boolean).join("-")}`;
}

export interface SessionPruneOptions {
  /** これより古いセッションを対象にする。 */
  olderThanMs: number;
  now?: number;
  /** 対象を 1 プロジェクトディレクトリに限定する。 */
  projectDir?: string;
  /** true のときだけ実際に削除する。既定は dry-run。 */
  apply?: boolean;
}

export interface SessionPruneTarget {
  session: string;
  bytes: number;
  paths: string[];
}

export interface SessionPruneResult {
  targets: SessionPruneTarget[];
  freedBytes: number;
  applied: boolean;
}

/** セッション 1 件分の `.jsonl`、サイドカー `/<id>/`、ロック `<id>.lock.os` を列挙する。 */
function sessionPaths(projectDir: string, file: string): string[] {
  const name = file.slice(0, -".jsonl".length);
  const candidates = [
    path.join(projectDir, file),
    path.join(projectDir, name),
    path.join(projectDir, `.${file}.lock.os`),
  ];
  return candidates.filter((p) => fs.existsSync(p));
}

function sizeOf(target: string): number {
  try {
    const stat = fs.lstatSync(target);
    if (!stat.isDirectory()) return stat.size;
    let total = 0;
    for (const entry of fs.readdirSync(target)) {
      total += sizeOf(path.join(target, entry));
    }
    return total;
  } catch {
    return 0;
  }
}

/**
 * 古いセッションを列挙し、`apply` 指定時のみ削除する。
 * 現在進行中のセッションは mtime が新しいため対象にならない。
 */
export function pruneSessions(root: string, options: SessionPruneOptions): SessionPruneResult {
  const now = options.now ?? Date.now();
  const cutoff = now - options.olderThanMs;
  const apply = options.apply === true;
  const projects = options.projectDir
    ? [path.join(root, options.projectDir)]
    : fs.existsSync(root)
      ? fs
          .readdirSync(root, { withFileTypes: true })
          .filter((e) => e.isDirectory() && !e.name.startsWith("."))
          .map((e) => path.join(root, e.name))
      : [];

  const targets: SessionPruneTarget[] = [];
  let freedBytes = 0;
  for (const project of projects) {
    let files: string[];
    try {
      files = fs.readdirSync(project).filter((f) => f.endsWith(".jsonl"));
    } catch {
      continue;
    }
    for (const file of files) {
      const sessionFile = path.join(project, file);
      let mtimeMs: number;
      try {
        mtimeMs = fs.statSync(sessionFile).mtimeMs;
      } catch {
        continue;
      }
      if (mtimeMs >= cutoff) continue;
      const paths = sessionPaths(project, file);
      const bytes = paths.reduce((sum, p) => sum + sizeOf(p), 0);
      targets.push({ session: file, bytes, paths });
      freedBytes += bytes;
    }
  }

  if (apply) {
    for (const target of targets) {
      for (const p of target.paths) {
        try {
          fs.rmSync(p, { recursive: true, force: true });
        } catch {
          // 削除できなかったものは次回に回す
        }
      }
    }
  }
  return { targets, freedBytes, applied: apply };
}

/** 既定の保持日数。OMP v19 に保持設定が無いため、この拡張が起動時に適用する。 */
export const DEFAULT_SESSION_RETENTION_DAYS = 30;

/**
 * `PI_SESSION_RETENTION_DAYS` を解釈する。未設定は既定 30 日、`0`/`off` は無効、
 * 不正値は既定へフォールバックする(空文字も既定)。
 */
export function resolveRetentionDays(raw: string | undefined): number {
  if (raw === undefined || raw.trim() === "") return DEFAULT_SESSION_RETENTION_DAYS;
  const normalized = raw.trim().toLowerCase();
  if (normalized === "off" || normalized === "0") return 0;
  const days = Number(normalized);
  if (!Number.isFinite(days) || days < 1) return DEFAULT_SESSION_RETENTION_DAYS;
  return Math.floor(days);
}
