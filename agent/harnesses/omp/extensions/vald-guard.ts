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

import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";

/** ' '(U+0020)以外の空白類、または制御文字・ゼロ幅/方向制御文字を含むか(ast_edit の path 検査用)。 */
function hasNonAsciiSpaceOrControl(s: string): boolean {
  for (const ch of s) {
    if (ch === " ") continue;
    const cp = ch.codePointAt(0) as number;
    if (/\s/.test(ch) || cp < 0x20 || (cp >= 0x7f && cp <= 0x9f) || (cp >= 0x200b && cp <= 0x200f) || (cp >= 0x202a && cp <= 0x202e) || cp === 0x2060 || cp === 0xfeff) {
      return true;
    }
  }
  return false;
}

/**
 * hashline の `[path]` / `[path#XXXX]`(4桁 hex タグ)ラッパーを外す。OMP の write は path をこれで無条件に剥がしてから解決する
 * (src/tools/hashline-header-path.ts の unwrapHashlineHeaderPath と同じ規則)。agent/hooks/omp/security-gate.ts と同一内容。
 */
function unwrapHashlineHeaderPath(p: string): string {
  const t = p.trimEnd();
  if (t.length < 2 || t[0] !== "[" || t[t.length - 1] !== "]") return p;
  const inner = t.slice(1, -1);
  const tag = /#[0-9A-Fa-f]{4}$/.exec(inner);
  const pathPart = tag ? inner.slice(0, tag.index) : inner;
  if (pathPart.length === 0 || (!tag && pathPart.includes("#"))) return p;
  return pathPart;
}

/**
 * OMP の edit ツールは設定(config.yml の edit.mode)により `{input: string}` 形式で、書込先は本文の中にある:
 *  - hashline: `[PATH#TAG]` ヘッダ行(旧形式 `¶PATH`)と、`MV DEST`(移動先)。本文の追加行は `+` で始まる。
 *  - apply_patch: `*** Add|Update|Delete File: PATH` と `*** Move to: PATH`。追加行は `+` で始まる。
 * ここから対象 path 全て(移動先を含む)と追加行テキストを取り出す。`input` が文字列でなければ hasPayload=false。
 * この関数は agent/hooks/omp/security-gate.ts と agent/harnesses/omp/extensions/vald-guard.ts に同一内容で置く。
 */
type EditPayload = { hasPayload: boolean; paths: string[]; text: string; suspicious: boolean };
const payloadCache = new WeakMap<object, EditPayload>();

export function parseEditPayload(inp: Record<string, any> | undefined): EditPayload {
  // 1 つの event に対し inspectWrite が複数回呼ぶので結果を使い回す。
  const cached = inp && typeof inp === "object" ? payloadCache.get(inp) : undefined;
  if (cached) return cached;
  // OMP は `input` が空のとき `_input` を使う(tool-event-input.ts)。どちらも書込先になりうるので両方読んで和集合にする。
  const raws = [inp?.input, inp?._input].filter((v): v is string => typeof v === "string");
  if (raws.length === 0) return { hasPayload: false, paths: [], text: "", suspicious: false };
  const strip = (s: string): string => {
    let p = s.trim().replace(/#[0-9a-fA-F]{4}$/, "");
    if (p.length >= 2 && (p[0] === '"' || p[0] === "'") && p[0] === p[p.length - 1]) p = p.slice(1, -1);
    return p;
  };
  const paths: string[] = [];
  const plus: string[] = [];
  let suspicious = false;
  let sloppy = false; // sloppy モード(`*** Edit File:` / Find / Replace / Insert)は本文が '+' 行ではなく生テキスト
  for (const raw of raws) {
  for (const rawLine of raw.replace(/^﻿/, "").split("\n")) {
    const line = rawLine.replace(/\r$/, "");
    if (line.startsWith("+")) {
      plus.push(line.slice(1));
      continue;
    }
    // apply_patch 系のパーサはヘッダ行を trim して照合するため、字下げされたヘッダも書込先として扱う(おとり + 隠しセクション対策)。
    // 正規表現は接頭辞だけを照合し、残りは slice + trim で取る(行末に空白を大量に置く入力で O(n^2) にならないように)。
    const t = line.trimStart();
    let m: RegExpExecArray | null;
    if (t.startsWith("[") && t.trimEnd().endsWith("]")) {
      const p = strip(t.trimEnd().slice(1, -1));
      if (p) paths.push(p);
    } else if (t.startsWith("¶")) {
      const p = strip(t.replace(/^¶+/, ""));
      if (p) paths.push(p);
    } else if ((m = /^\*\*\*\s*(?:Add|Update|Delete)\s+File:/i.exec(t))) {
      paths.push(t.slice(m[0].length).trim());
    } else if ((m = /^\*\*\*\s*Move\s+to:/i.exec(t))) {
      paths.push(t.slice(m[0].length).trim());
    } else if ((m = /^\*{3}[ \t]+Edit[ \t]+File(?::|[ \t]|$)[ \t]*/i.exec(t))) {
      // sloppy モードの対象ヘッダ(OMP の native パーサ crates/edit/src/modes/sloppy/parse.rs): 大小文字無視・コロン省略可・
      // 末尾の ` all` は path ではない・二重引用符だけ JSON として unquote(解釈できなければ native もヘッダと見なさない)。
      sloppy = true;
      let p = t.slice(m[0].length).trim();
      const am = /\s+all$/i.exec(p);
      if (am) p = p.slice(0, am.index).trimEnd();
      if (p.startsWith('"')) {
        try {
          p = JSON.parse(p);
        } catch {
          // 評価対象にはそのまま残す(余分な候補は害にならない)
        }
      }
      if (typeof p === "string" && p) paths.push(p);
    } else if (/^\*{3}[ \t]+(?:Find|Replace|Insert[ \t]+After|Insert[ \t]+Before)(?::|[ \t]|$)/i.test(t)) {
      sloppy = true;
    } else if (t.startsWith("***") && !/^\*\*\*\s*(?:Begin\s+Patch|End\s+Patch|End\s+of\s+File)\b/i.test(t)) {
      suspicious = true; // 認識できない *** 行は書込先を隠している可能性があるので、呼び出し側が fail-closed にする
    } else if (/^MV(?=$|[\s:])/.test(t)) {
      // hashline の移動: native の keyword_tail は `MV` の後ろに行末・':'・空白を許す(`MV:` / `MV: dest` / `MV dest`)。
      const dest = strip(t.replace(/^MV\s*:?/, ""));
      if (dest) paths.push(dest);
    }
  }
  }
  // sloppy モードの置換・挿入本文は '+' 行ではなく生テキストなので、全文を内容検査に掛ける(Find 側も含む保守的な扱い)。
  const result: EditPayload = { hasPayload: true, paths, text: sloppy ? raws.join("\n") : plus.join("\n"), suspicious };
  if (inp && typeof inp === "object") payloadCache.set(inp, result);
  return result;
}

/**
 * ast_edit の書込対象(fail-closed)。ast-grep 系の書換えは本来ディレクトリ/glob 単位で、単一ファイルの
 * `path` だけを見る gate は path 無し・ディレクトリ・glob 指定で素通りされる。そのため ast_edit は
 * 「実在する通常ファイルだけ」を対象として列挙でき、それ以外は ok:false(呼び出し側が block)にする。
 *  - 対象候補: path / file_path / file / target / TargetFile と paths[](全要素)。1つも無ければ不可。
 *  - glob / globs / include の指定があれば不可(対象集合を特定できない)。
 *  - 各候補は非空文字列で、ツールの path 正規化と食い違う形(先頭 ~ / @ / file:・前後空白・Unicode 空白/制御文字)
 *    でなく、"." / ".." ・glob 文字(*?[]{})・末尾 "/" ・NUL を含まず、
 *    cwd 基準で解決した先が実在する通常ファイル(stat が isFile)であること。
 *  - 通常ファイルなら解決後パスと realpath の両方を返す(symlink 経由の保護パス迂回を防ぐ)。
 *  - 実スキーマ(@oh-my-pi/pi-coding-agent 19.0.1 src/tools/ast-edit.ts で確認済み): `{ ops: [{pat, out}], paths: string[] }`。
 *    paths の要素は file / directory / glob / internal URL で、単数形のキーは無い(単数形の候補は防御的に評価しているだけ)。
 *    つまり実運用の ast_edit(例 `paths: ["src/**\/*.ts"]`)は glob/ディレクトリ指定が普通で、ここでは常に block になる。
 *    許可したい対象は明示的なファイル path で渡すこと。glob を許すには、ツールと同じ展開結果の全ファイルを列挙して
 *    各 gate に通す必要があり、展開規則の食い違いが迂回になるため意図的に実装していない。
 * この関数は agent/hooks/omp/security-gate.ts と agent/harnesses/omp/extensions/vald-guard.ts に
 * 同一内容で置く(両者は別ディレクトリのため相互 import しない)。変更時は両方を同時に更新すること。
 */
export type AstEditTargets = { ok: true; paths: string[] } | { ok: false; reason: string };

export function resolveAstEditTargets(input: Record<string, any> | undefined, cwd: string): AstEditTargets {
  const inp = input ?? {};
  for (const k of ["glob", "globs", "include"]) {
    const v = inp[k];
    if (v !== undefined && v !== null && v !== "" && !(Array.isArray(v) && v.length === 0)) {
      return { ok: false, reason: `ast_edit with '${k}' cannot identify the files it rewrites` };
    }
  }
  const cands: unknown[] = [];
  for (const k of ["path", "file_path", "file", "target", "TargetFile"]) {
    if (inp[k] !== undefined && inp[k] !== null) cands.push(inp[k]);
  }
  if (Array.isArray(inp.paths)) cands.push(...inp.paths);
  else if (inp.paths !== undefined && inp.paths !== null) {
    return { ok: false, reason: "ast_edit 'paths' is not an array" };
  }
  if (cands.length === 0) return { ok: false, reason: "ast_edit has no target path" };
  const out: string[] = [];
  for (const c of cands) {
    if (typeof c !== "string" || c === "") return { ok: false, reason: "ast_edit target path is empty or not a string" };
    // ツールの path 正規化(upstream pi の normalizePath/resolveToCwd: 先頭 '@' 除去・'~' の homedir 展開・
    // file:// の fileURLToPath・Unicode 空白の ' ' 化・前後 trim)とゲートの解決先が食い違う形は、
    // ゲートがデコイを評価して別の保護ファイルを書かれる迂回になるため、正規化せず block する。
    // 対象: 先頭 '~' / '@' / 'file:'(大文字小文字無視)・前後の空白・ASCII 空白以外の空白類/制御文字
    // (NBSP・ゼロ幅・TAB・改行等。パス内部の通常の ' ' だけは許可)。
    // 先頭 ':'(迷子コロン)と前後の '"'(OMP の normalizePathLikeInput が外側の二重引用符を剥がす)も同じ理由で拒否する。
    // `"agent/x.ts"` という名前のデコイを write で作ってからゲートに通し、ツールには本物の agent/x.ts を書かせる迂回を防ぐ。
    if (c.startsWith("~") || c.startsWith("@") || c.startsWith(":") || c.startsWith('"') || c.endsWith('"') || /^file:/i.test(c) || c !== c.trim() || hasNonAsciiSpaceOrControl(c)) {
      return {
        ok: false,
        reason: `ast_edit target '${c}' uses a form (~ / @ / file: / surrounding or Unicode whitespace / control char) where the tool's path normalization and the gate's resolution can differ`,
      };
    }
    const t = c;
    if (t === "." || t === ".." || t.includes("\0") || /[*?\[\]{}]/.test(t) || /[\\/]$/.test(t)) {
      return { ok: false, reason: `ast_edit target '${t}' is not a single regular file (directory/glob/empty)` };
    }
    const abs = path.resolve(cwd, t);
    try {
      if (!fs.statSync(abs).isFile()) {
        return { ok: false, reason: `ast_edit target '${t}' is not a regular file` };
      }
      const real = fs.realpathSync(abs);
      if (!out.includes(abs)) out.push(abs);
      if (!out.includes(real)) out.push(real);
    } catch {
      return { ok: false, reason: `ast_edit target '${t}' does not exist or is unreadable` };
    }
  }
  return { ok: true, paths: out };
}

export interface ValdLawCheckResult {
  allowed: boolean;
  lawNumber?: number;
  violation?: string;
  suggestion?: string;
  /** Non-blocking notice (the caller notifies but does not abort the tool call). */
  advisory?: string;
}

/**
 * ファイルを書き換える OMP ツール名の集合。ゲートはこの集合で判定する(edit/write だけだと
 * ast_edit 経由で Vald Law 1/3/4/5 を素通りできる)。sol-pi-core.ts の EDIT_TOOLS と同じ3種。
 */
export const WRITE_TOOLS: ReadonlySet<string> = new Set(["edit", "write", "ast_edit"]);

/**
 * Replacement text of the OMP `edit` tool's `edits[]` array (and `ast_edit`'s `ops[].out`). Each element may carry the new text
 * under `newText` / `replacement` / `new_string`. The removed text (`oldText`/`old_string`) is
 * deliberately NOT included. Malformed input (non-array, non-object, non-string) is ignored.
 */
export function collectEditTexts(input: Record<string, any>): string[] {
  const out: string[] = [];
  // replace モードの実スキーマは {path, old_string, new_string}(トップレベル)。
  if (typeof input?.new_string === "string") out.push(input.new_string);
  const edits = input?.edits;
  if (Array.isArray(edits)) {
    for (const e of edits) {
      if (!e || typeof e !== "object") continue;
      for (const k of ["newText", "replacement", "new_string"]) {
        if (typeof e[k] === "string") out.push(e[k]);
      }
      // patch モードの実スキーマは edits[]: {op, rename, diff}。create の diff は全文、update の diff は追加行(+)だけが書かれる内容。
      if (typeof e.diff === "string") {
        out.push(e.op === "create" ? e.diff : e.diff.split("\n").filter((l: string) => l.startsWith("+")).map((l: string) => l.slice(1)).join("\n"));
      }
    }
  }
  // ast_edit: ops[].out が置換後テキスト(ops[].pat は置換前パターンなので対象外)。
  const ops = input?.ops;
  if (Array.isArray(ops)) {
    for (const o of ops) {
      if (o && typeof o === "object" && typeof o.out === "string") out.push(o.out);
    }
  }
  return out;
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

  // 1a. ast_edit: 対象を実在する通常ファイルへ解決できなければ fail-closed(Vald repo 内のみ)。
  // 解決できた各ファイルは edit と同じ判定(Law 1/3/4/5。内容は ops[].out)に掛ける。
  if (toolName === "ast_edit") {
    const targets = resolveAstEditTargets(input, cwd);
    if (!targets.ok) {
      return {
        allowed: false,
        lawNumber: 1,
        violation: `Vald Law 1 Violation: ast_edit target cannot be verified (${targets.reason}).`,
        suggestion: "Give ast_edit a single existing regular file path (no directory/glob); generated *.pb.go cannot be ruled out otherwise.",
      };
    }
    let advisory: ValdLawCheckResult | undefined;
    for (const p of targets.paths) {
      const r = checkValdLaws("edit", { ...input, path: p }, cwd);
      if (!r.allowed) return r;
      if (r.advisory && !advisory) advisory = r;
    }
    return advisory ?? { allowed: true };
  }

  // 1a'. patch モード(edits[].rename)の移動先も、書込先として edit と同じ判定に掛ける。
  if (toolName === "edit" && Array.isArray(input.edits)) {
    for (const e of input.edits) {
      if (e && typeof e.rename === "string" && e.rename) {
        // 移動先には、この edit が書く内容(create は diff 全文、update は追加行)も掛ける(.txt → .go への rename で Law 3 を外せないように)。
        const added = typeof e.diff === "string" ? (e.op === "create" ? e.diff : e.diff.split("\n").filter((l: string) => l.startsWith("+")).map((l: string) => l.slice(1)).join("\n")) : "";
        const r = checkValdLaws("edit", { path: e.rename, edits: [{ newText: added }] }, cwd);
        if (!r.allowed) return r;
      }
    }
  }

  // 1b. edit の `{input}` 形式(hashline / apply_patch): 書込先は本文のヘッダ(MV・Move to の移動先を含む)、内容は追加行(+)。
  // 全 path を edit と同じ判定(Law 1/3/4/5)に掛け、書込先を特定できなければ fail-closed(Vald repo 内のみ)。
  if (toolName === "edit") {
    const payload = parseEditPayload(input);
    if (payload.hasPayload) {
      if (payload.suspicious) {
        return {
          allowed: false,
          lawNumber: 1,
          violation: "Vald Law 1 Violation: edit target cannot be verified (unrecognised '***' directive line in the edit input).",
          suggestion: "Use only [PATH#TAG] headers (hashline) or *** Add|Update|Delete File: / *** Move to: headers (apply_patch).",
        };
      }
      const targets = [...new Set([input.path, input.file_path, ...(Array.isArray(input.paths) ? input.paths : []), ...payload.paths].filter((v): v is string => typeof v === "string" && v !== ""))];
      if (targets.length === 0) {
        return {
          allowed: false,
          lawNumber: 1,
          violation: "Vald Law 1 Violation: edit target cannot be verified (no file header in the edit input).",
          suggestion: "Give each edit section a [PATH#TAG] header (hashline) or a *** Update File: header (apply_patch).",
        };
      }
      let advisory: ValdLawCheckResult | undefined;
      for (const p of targets) {
        // input を外した形で再帰するので、この分岐へは戻らない。
        const r = checkValdLaws("edit", { path: p, edits: [{ newText: payload.text }] }, cwd);
        if (!r.allowed) return r;
        if (r.advisory && !advisory) advisory = r;
      }
      return advisory ?? { allowed: true };
    }
  }

  // 1. File edits / writes
  if (WRITE_TOOLS.has(toolName)) {
    const filePath = unwrapHashlineHeaderPath((input.path || input.file || input.TargetFile || "") as string);
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
    // Laws 3/4/5 scan the single-edit/write content AND every edits[] replacement text.
    const editTexts = collectEditTexts(input);
    const scan = (re: RegExp) => re.test(content) || editTexts.some((t) => re.test(t));

    if (filePath.endsWith(".go") && !isTestFile) {
      // Law 3: Bare panic in production code
      if (scan(/\bpanic\s*\(/)) {
        return {
          allowed: false,
          lawNumber: 3,
          violation: `Vald Law 3 Violation: Bare panic() detected in production code '${baseName}'.`,
          suggestion: "Return an explicit error or use robust error handling instead of panicking.",
        };
      }

      // Law 4: log.Fatal outside main
      const isMainFile = baseName === "main.go";
      if (!isMainFile && scan(/\blog\.Fatal\s*\(/)) {
        return {
          allowed: false,
          lawNumber: 4,
          violation: `Vald Law 4 Violation: log.Fatal() detected outside main() in '${baseName}'.`,
          suggestion: "Propagate the error to the caller or log.Error() instead of aborting.",
        };
      }

      // Law 5: Silently discarding error
      if (scan(/_\s*=\s*(?:[a-zA-Z0-9_.]+\.)?err\b/) || scan(/_\s*=\s*err\b/)) {
        return {
          allowed: false,
          lawNumber: 5,
          violation: `Vald Law 5 Violation: Discarding error (_ = err) in '${baseName}'.`,
          suggestion: "Handle or propagate the error explicitly.",
        };
      }

      // Advisory (non-blocking): stdlib errors.New inside edits[] — vald uses internal/errors.
      if (editTexts.some((t) => /\berrors\.New\s*\(/.test(t))) {
        return {
          allowed: true,
          advisory: `Vald: errors.New() detected in an edit to '${baseName}'. Use the constructors in internal/errors instead of the standard library errors.New.`,
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
    if (check.allowed && check.advisory) {
      ctx.ui.notify(`⚠️ ${check.advisory}`, "warning");
    }
    if (!check.allowed) {
      const msg = `🛡️ [VALD LAW ${check.lawNumber} BLOCKED]\n${check.violation}\n👉 ${check.suggestion}`;
      ctx.ui.notify(msg, "error");
      throw new Error(msg);
    }
  });
}
