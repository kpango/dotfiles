/**
 * Post-Edit Lint for Pi Coding Agent
 *
 * pi 版 PostToolUse 即時 lint。agy の `agent/harnesses/agy/hooks/post-edit-lint.sh` と同じ
 * broadest-safest-superset 方針(agent/README.md「Post-Write lintフックの対象拡張子superset化」
 * 参照)で、write/edit 直後にその拡張子に応じた **構文チェック** を行い、問題があれば非ブロッキングで
 * 通知する(tool_result はツール実行後に発火するため書込自体はブロックできない — 助言的通知)。
 *
 * 対象拡張子(agy 版と同一の superset): .go / .py / .json / .sh / .bash / .yaml / .yml / .toml。
 *
 * Makefile は **意図的にチェックしない**: GNU Make の `make -n`(dry-run)は `$(shell ...)` / `!=` を
 * パース(変数展開)時に評価するため `-n` は実行を抑制せず、書き込まれた Makefile 次第で確認なしの
 * 任意コマンド実行プリミティブになる(agy/claude の post-write hook が実機 PoC で確認・同パターンを
 * 削除済み。移行 doc §1.5 が再発させないよう明示指定した既知の落とし穴)。拡張子ベース dispatch の
 * default 分岐で「Makefile」(拡張子なし)・「*.mk」(未登録拡張子)は素通りする。
 *
 * agy 版との差異(移行時の設計判断): agy は .go を `gofmt -s -w` で **その場整形** するが、pi 版は
 * tool_result 助言フックの非侵襲性を優先し **構文チェックのみ(ファイル無改変)** とする(gofmt -e で
 * 構文エラーのみ検出)。対象拡張子 superset は agy と一致させ、拡張子リストの正典は agy 版とする
 * (将来の追加は両方を同期させること)。
 *
 * 縮退方針: 各チェッカ(gofmt/python3/bash)が未導入なら **スキップ**(偽の失敗を出さない、agy の
 * `which gofmt` ガードと同じ)。lint は助言であり安全ゲートではないため、いかなる場合もブロックしない。
 */

import { spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export interface LintResult {
  ext: string;
  checked: boolean; // 実際に構文チェックを実行したか(未対応拡張子/ツール欠落なら false)
  ok: boolean; // checked=true のときのみ意味を持つ(構文妥当か)
  message?: string; // ok=false のときの診断メッセージ(1 行に正規化)
  skipped?: string; // checked=false の理由(未対応拡張子/ツール欠落等)
}

function firstLine(s: string): string {
  const t = (s || "").trim();
  const nl = t.indexOf("\n");
  return (nl >= 0 ? t.slice(0, nl) : t).trim();
}

// 外部チェッカを spawnSync で実行。ツール未導入(ENOENT)は checked=false でスキップ、exit 0=ok、
// 非 0=構文エラー(message は stderr→stdout の先頭行)。ファイルは一切改変しない。
function runCheck(bin: string, args: string[], ext: string): LintResult {
  try {
    const res = spawnSync(bin, args, { encoding: "utf-8" });
    if (res.error) {
      // ENOENT 等: チェッカ未導入 → スキップ(偽陽性を出さない)
      return { ext, checked: false, ok: true, skipped: `${bin} unavailable` };
    }
    if (res.status === 0) return { ext, checked: true, ok: true };
    const msg = firstLine(res.stderr || "") || firstLine(res.stdout || "") || `${bin} exited ${res.status}`;
    return { ext, checked: true, ok: false, message: msg };
  } catch {
    return { ext, checked: false, ok: true, skipped: `${bin} spawn failed` };
  }
}

function checkJson(filePath: string, ext: string): LintResult {
  try {
    JSON.parse(fs.readFileSync(filePath, "utf-8"));
    return { ext, checked: true, ok: true };
  } catch (e) {
    return { ext, checked: true, ok: false, message: firstLine(String((e as Error)?.message ?? e)) };
  }
}

// python3 -c でモジュール(yaml / tomllib)を使って構造検証。モジュール未導入(ImportError)は
// スキップ(exit 3)、パース失敗は exit 1(構文エラー)。ファイルパスは argv で渡し文字列補間しない
// (インジェクション回避)。
function runPyStructured(filePath: string, ext: string, kind: "yaml" | "toml"): LintResult {
  const script =
    kind === "yaml"
      ? "import sys\ntry:\n import yaml\nexcept ImportError:\n sys.exit(3)\ntry:\n yaml.safe_load(open(sys.argv[1], 'r', encoding='utf-8'))\nexcept Exception as e:\n sys.stderr.write(str(e)); sys.exit(1)\n"
      : "import sys\ntry:\n import tomllib\nexcept ImportError:\n sys.exit(3)\ntry:\n tomllib.load(open(sys.argv[1], 'rb'))\nexcept Exception as e:\n sys.stderr.write(str(e)); sys.exit(1)\n";
  try {
    const res = spawnSync("python3", ["-c", script, filePath], { encoding: "utf-8" });
    if (res.error) return { ext, checked: false, ok: true, skipped: "python3 unavailable" };
    if (res.status === 0) return { ext, checked: true, ok: true };
    if (res.status === 3) return { ext, checked: false, ok: true, skipped: `python ${kind} module unavailable` };
    return { ext, checked: true, ok: false, message: firstLine(res.stderr || res.stdout || `${kind} parse error`) };
  } catch {
    return { ext, checked: false, ok: true, skipped: "python3 spawn failed" };
  }
}

// 書き込まれたファイルを拡張子で dispatch して構文チェックする(純粋 core、テスト可能)。
export function lintFileByExtension(filePath: string): LintResult {
  let isFile = false;
  try {
    isFile = fs.existsSync(filePath) && fs.statSync(filePath).isFile();
  } catch {
    isFile = false;
  }
  if (!isFile) return { ext: "", checked: false, ok: true, skipped: "not a file" };

  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case ".go":
      // gofmt -e: 構文エラーを報告(-w は付けない=ファイル無改変)。整形済み出力は stdout へ捨てられる。
      return runCheck("gofmt", ["-e", filePath], ext);
    case ".py":
      return runCheck("python3", ["-m", "py_compile", filePath], ext);
    case ".sh":
    case ".bash":
      return runCheck("bash", ["-n", filePath], ext);
    case ".json":
      return checkJson(filePath, ext);
    case ".yaml":
    case ".yml":
      return runPyStructured(filePath, ext, "yaml");
    case ".toml":
      return runPyStructured(filePath, ext, "toml");
    default:
      // Makefile(拡張子なし)・*.mk・その他は非対象(上記 Makefile 除外理由参照)。
      return { ext, checked: false, ok: true, skipped: "unsupported extension" };
  }
}

// tool_result の write/edit イベントから書込対象パスを取り出す(input は path または file_path)。
export function extractWrittenPath(input: Record<string, unknown> | undefined): string | null {
  if (!input) return null;
  const p = input.path ?? input.file_path;
  return typeof p === "string" && p ? p : null;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", async (event, ctx) => {
    if (event.toolName !== "write" && event.toolName !== "edit") return;
    // 書込自体が失敗していれば lint 対象は無い
    if ((event as { isError?: boolean }).isError) return;

    const rawPath = extractWrittenPath(event.input as Record<string, unknown> | undefined);
    if (!rawPath) return;
    const abs = path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.cwd, rawPath);

    let res: LintResult;
    try {
      res = lintFileByExtension(abs);
    } catch {
      return; // lint は助言 — 予期せぬ失敗でも通知しない(ブロックもしない)
    }
    if (res.checked && !res.ok && res.message) {
      if (ctx.hasUI) {
        ctx.ui.notify(`post-edit-lint: ${path.basename(abs)} (${res.ext}): ${res.message}`, "warning");
      }
    }
  });
}
