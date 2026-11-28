/**
 * Security Gate Extension for Pi
 *
 * Enforces safety boundaries across shell command execution and file writes,
 * protecting credentials, sensitive files, destructive disk ops, production namespaces,
 * and repository-specific invariants (Vald Law).
 *
 * 破壊的コマンド・機微パスのルールデータは agent/security-rules.json を、Vald Law判定データは
 * agent/vald-law-rules.json を読む(いずれもclaude/agy/omp共通)。
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { callDecide, repoRoot } from "./lib/shared";

// shell_command_rules・sensitive_write_path_rules・Vald Law 1/2/3/4/5 の判定アルゴリズム
// (all_of/any_of/not_any_of の評価・force_push/git_reset_hardの特別扱い・パス候補照合・
// Vald Lawのスコープ判定/コンテンツ検査)は agent/scripts/hooks/rule_engine.py + decide.py へ
// 統合済み(2026-09-03、claude/agy/ompで独立に再実装されていたロジックを1箇所化)。本ファイルは
// OMP Extension API(ctx.ui.confirm等)への結線のみを持つ薄いシム。
// decide.py 自身が毎回最新のルールファイルを読み込むため、モジュールロード時の RULES キャッシュや
// ゲートは持たない(起動時読み込み失敗による fail-open を構造的に防止する)。
export interface DecideResult {
  decision: "allow" | "ask" | "block" | "deny";
  reason?: string;
  matched_rule_id?: string;
  resolved_path?: string;
  all_matches?: Array<{ id: string; tier: string; description: string }>;
  violations?: string[];
}

function evaluateShellCommand(root: string, cwd: string, command: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "security_shell",
      command,
      cwd,
      rules_file: path.join(root, "agent", "security-rules.json"),
      resolve_command_target: true,
    },
    { decision: "allow" },
  );
}

function evaluateWritePath(root: string, cwd: string, home: string, rawPath: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "security_write",
      file_path: rawPath,
      cwd,
      home,
      rules_file: path.join(root, "agent", "security-rules.json"),
    },
    { decision: "allow" },
  );
}

// ファイルを書き換える OMP ツール名。security_write / write_scope(Tier B) / Vald Law の全ゲートが
// この集合で判定する(edit/write だけだと ast_edit 経由で全ゲートを素通りできる)。
// agent/harnesses/pi/extensions/vald-guard.ts の WRITE_TOOLS・lib/sol-pi-core.ts の EDIT_TOOLS と同じ3種。
export const WRITE_TOOLS: ReadonlySet<string> = new Set(["write", "edit", "ast_edit"]);

// OMP の Unicode 空白(NBSP・U+2000-200A・U+202F・U+205F・U+3000)。ツール側はこれを ' ' に置換して path を解決する。
const isUnicodeSpace = (cp: number): boolean =>
  cp === 0xa0 || (cp >= 0x2000 && cp <= 0x200a) || cp === 0x202f || cp === 0x205f || cp === 0x3000;

/**
 * hashline の `[path]` / `[path#XXXX]`(4桁 hex タグ)ラッパーを外す。OMP の write は path をこれで無条件に剥がしてから解決する
 * (src/tools/hashline-header-path.ts の unwrapHashlineHeaderPath と同じ規則: 厳密なヘッダ形だけ。タグ無しで '#' を含む path は元のまま)。
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
 * ここから対象 path 全て(移動先を含む)と追加行テキストを取り出す(@earendil-works/pi-coding-agent 19.0.1 の
 * src/extensibility/tool-event-input.ts の extractHashlinePaths と edit-hashline-compact.md / APPLY_PATCH_EXAMPLES に準拠)。
 * `input` が文字列でなければ hasPayload=false(replace/patch モードの `path`+`edits[]` は呼び出し側が従来どおり扱う)。
 * OMP は単一ヘッダのとき `path`、複数のとき `paths` も補うが、`MV` と apply_patch は補わないため本文を自分で読む。
 * この関数は agent/hooks/pi/security-gate.ts と agent/harnesses/pi/extensions/vald-guard.ts に同一内容で置く。
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
 * edit / write が実際に書く path を、OMP の expandPath(@earendil-works/pi-coding-agent 19.0.1 src/tools/path-utils.ts)と
 * 同じ手順で求める: 先頭の迷子 ':' の除去 → 先頭 '@'(後ろが '/'・'~'・'~/' のときだけ)の除去 → Unicode 空白の ' ' 化 →
 * file:// の path 化(host が空/localhost のときだけ) → 先頭 '~' の home 展開。
 * 生の文字列だけを評価すると `@/etc/x` や `file:///etc/x` が cwd 配下の別名に見え、保護 path を素通りできる。
 * Windows 固有の分岐(ドライブレター・UNC・\\?\・WSL のドライブ変換)はここでは写さない(Linux/macOS の dotfiles 用)。
 * internal URL のうち ssh:// vault:// cfg:// conflict:// は書込先が見えないため呼び出し側で fail-closed にする
 * (local:// と、ast_edit の適用に使う xd://resolve は通す)。
 */
export function normalizeToolPath(raw: string, home: string): string {
  let p = unwrapHashlineHeaderPath(raw);
  p = /^:(?=[/\\~]|\.\.?[/\\]|[A-Za-z]:)/.test(p) ? p.slice(1) : p;
  if (p.startsWith("@")) {
    const rest = p.slice(1);
    if (rest.startsWith("/") || rest === "~" || rest.startsWith("~/")) p = rest;
  }
  p = Array.from(p, (ch) => (isUnicodeSpace(ch.codePointAt(0) as number) ? " " : ch)).join("");
  if (/^file:\/\//i.test(p)) {
    try {
      const u = new URL(p);
      if (u.hostname === "" || u.hostname === "localhost") p = decodeURIComponent(u.pathname);
    } catch {
      // 解釈できない file: はツールも生のまま扱う。
    }
  }
  if (p === "~") return home;
  if (p.startsWith("~/")) return path.join(home, p.slice(2));
  return p;
}

// Tier B 書込保護ゲート: fail-closed (callDecide失敗時も block を返す)
function evaluateWriteScope(root: string, cwd: string, home: string, rawPath: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "write_scope",
      file_path: rawPath,
      cwd,
      home,
      rules_file: path.join(root, "agent", "write-scope-rules.json"),
    },
    { decision: "block", reason: "write-scope decide.py invocation failed; failing closed (Tier B)" },
  );
}

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
 * ast_edit の書込対象(fail-closed)。ast-grep 系の書換えは本来ディレクトリ/glob 単位で、単一ファイルの
 * `path` だけを見る gate は path 無し・ディレクトリ・glob 指定で素通りされる。そのため ast_edit は
 * 「実在する通常ファイルだけ」を対象として列挙でき、それ以外は ok:false(呼び出し側が block)にする。
 *  - 対象候補: path / file_path / file / target / TargetFile と paths[](全要素)。1つも無ければ不可。
 *  - glob / globs / include の指定があれば不可(対象集合を特定できない)。
 *  - 各候補は非空文字列で、ツールの path 正規化と食い違う形(先頭 ~ / @ / file:・前後空白・Unicode 空白/制御文字)
 *    でなく、"." / ".." ・glob 文字(*?[]{})・末尾 "/" ・NUL を含まず、
 *    cwd 基準で解決した先が実在する通常ファイル(stat が isFile)であること。
 *  - 通常ファイルなら解決後パスと realpath の両方を返す(symlink 経由の保護パス迂回を防ぐ)。
 *  - 実スキーマ(@earendil-works/pi-coding-agent 19.0.1 src/tools/ast-edit.ts で確認済み): `{ ops: [{pat, out}], paths: string[] }`。
 *    paths の要素は file / directory / glob / internal URL で、単数形のキーは無い(単数形の候補は防御的に評価しているだけ)。
 *    つまり実運用の ast_edit(例 `paths: ["src/**\/*.ts"]`)は glob/ディレクトリ指定が普通で、ここでは常に block になる。
 *    許可したい対象は明示的なファイル path で渡すこと。glob を許すには、ツールと同じ展開結果の全ファイルを列挙して
 *    各 gate に通す必要があり、展開規則の食い違いが迂回になるため意図的に実装していない。
 * この関数は agent/hooks/pi/security-gate.ts と agent/harnesses/pi/extensions/vald-guard.ts に
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

/**
 * ast_edit はプレビュー(ここで各 gate を通す)と適用(`write xd://resolve`)が別の呼び出しで、適用時にツールは対象を
 * ファイルシステムから解決し直す。間に対象を symlink へ差し替えられると、プレビューで許可した path が適用時には別の
 * (保護された)ファイルを指す。そこで、許可したプレビューの各対象の realpath をその時点で記録しておき、
 * xd://resolve への write のときに再解決して、変わっていたら(消えた・宙ぶらりんの symlink になった場合も)block する。
 * OMP はプレビューを重ねて個別に保留でき(queueResolveHandler: stacked/sequential previews each get their own entry)、
 * どれが適用されるかはここから分からない。そのため保留中のプレビュー全てを保持して毎回全てを確認し、適用が通っても捨てない
 * (捨てると、別のプレビューの対象を後から差し替える経路が空く)。捨てるのは `write xd://reject` のときだけ(上限 32 件、古い順)。
 * 古い対象を正当に symlink にした等で誤って止まったときは、`write xd://reject` で記録を捨てる。
 */
const pendingAstEdits: Array<Array<[string, string]>> = [];

const realpathOrNull = (p: string): string | null => {
  try {
    return fs.realpathSync(p);
  } catch {
    return null;
  }
};

function rememberAstEditPreview(paths: string[]): void {
  const pairs: Array<[string, string]> = [];
  for (const p of new Set(paths)) {
    const real = realpathOrNull(p);
    if (real !== null) pairs.push([p, real]);
  }
  pendingAstEdits.push(pairs);
  if (pendingAstEdits.length > 32) pendingAstEdits.shift();
}

/** 適用(xd://resolve)の直前に呼ぶ。保留中のどのプレビューでも、対象の解決先が変わっていれば理由を返す。 */
function checkAstEditStillSame(): string | undefined {
  for (const pairs of pendingAstEdits) {
    for (const [p, real] of pairs) {
      const now = realpathOrNull(p);
      if (now === real) continue;
      // 対象が普通に消えただけ(lstat も失敗)なら書き込む先が無いので通す。symlink 化・宙ぶらりん・別物への差し替えは block。
      let gone = false;
      try {
        fs.lstatSync(p);
      } catch {
        gone = true;
      }
      if (gone) continue;
      return `ast_edit target '${p}' resolved to '${real}' at preview time but resolves to '${now ?? "(unresolvable)"}' now (write xd://reject to drop the staged previews)`;
    }
  }
  return undefined;
}

const isResolveDevice = (c: string): boolean => /^xd:\/\/resolve(?:[/?#].*)?$/i.test(unwrapHashlineHeaderPath(c).replace(/^[:@]/, ""));
const isRejectDevice = (c: string): boolean => /^xd:\/\/reject(?:[/?#].*)?$/i.test(unwrapHashlineHeaderPath(c).replace(/^[:@]/, ""));

function extractWrittenContent(event: { toolName: string; input: Record<string, unknown> }): string {
  if (event.toolName === "write") {
    return (event.input.content as string) || "";
  }
  if (event.toolName === "edit") {
    // edit の実スキーマ(@earendil-works/pi-coding-agent 19.0.1 src/edit/schemas.ts): replace は {path, old_string, new_string}、
    // patch は {path, edits:[{op, rename, diff}]}(create の diff は全文・update の diff は追加行 '+' だけが書かれる内容)、
    // hashline / apply_patch は {input}(追加行が '+' 始まりの本文)。旧来の edits[].newText も読む。
    const inp = event.input as Record<string, any>;
    const parts: string[] = [];
    if (typeof inp.new_string === "string") parts.push(inp.new_string);
    for (const e of Array.isArray(inp.edits) ? inp.edits : []) {
      if (!e || typeof e !== "object") continue;
      for (const k of ["newText", "new_string", "replacement"]) if (typeof e[k] === "string") parts.push(e[k]);
      if (typeof e.diff === "string") {
        parts.push(e.op === "create" ? e.diff : e.diff.split("\n").filter((l: string) => l.startsWith("+")).map((l: string) => l.slice(1)).join("\n"));
      }
    }
    parts.push(parseEditPayload(inp).text);
    return parts.join("\n");
  }
  if (event.toolName === "ast_edit") {
    // ast_edit: ops[].out が置換後テキスト(ops[].pat は置換前パターン)。
    const ops = Array.isArray(event.input.ops) ? (event.input.ops as Array<{ out?: unknown }>) : [];
    return ops.map((o) => (o && typeof o.out === "string" ? o.out : "")).join("\n");
  }
  return "";
}

function evaluateValdLaw2(root: string, valdRulesFile: string, cwd: string, command: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "vald_law2",
      command,
      cwd,
      vald_rules_file: valdRulesFile,
      scope_mode: "cwd_and_resolved_path",
    },
    { decision: "allow" },
  );
}

function evaluateValdLaw1(root: string, valdRulesFile: string, filePath: string): DecideResult {
  return callDecide<DecideResult>(
    root,
    { family: "vald_law1", file_path: filePath, vald_rules_file: valdRulesFile },
    { decision: "allow" },
  );
}

function evaluateValdLaw345(
  root: string,
  valdRulesFile: string,
  cwd: string,
  filePath: string,
  content: string,
): DecideResult {
  return callDecide<DecideResult>(
    root,
    {
      family: "vald_law345",
      file_path: filePath,
      content,
      vald_rules_file: valdRulesFile,
      scope_mode: "cwd_and_resolved_path",
      cwd,
    },
    { decision: "allow" },
  );
}

async function confirmOrBlock(
  ctx: { hasUI?: boolean; ui?: { confirm?: (title: string, message: string) => Promise<boolean> } },
  title: string,
  confirmMessage: string,
  userDeniedReason: string,
  noUiBlockReason: string,
): Promise<{ block: true; reason: string } | undefined> {
  if (ctx?.hasUI && ctx.ui?.confirm) {
    const ok = await ctx.ui.confirm(title, confirmMessage);
    if (!ok) {
      return { block: true, reason: userDeniedReason };
    }
    return undefined;
  }
  return { block: true, reason: noUiBlockReason };
}

export async function handleShellCommandResult(
  result: DecideResult,
  command: string,
  confirmFn: (title: string, message: string) => Promise<boolean>,
  hasUI: boolean,
): Promise<{ block: true; reason: string } | undefined> {
  if (result.decision === "block" || result.decision === "deny") {
    return { block: true, reason: `Security Gate blocked command: ${result.reason ?? ""}` };
  }

  const matches = result.all_matches ?? [];
  if (matches.length > 0) {
    for (const m of matches) {
      if (hasUI) {
        const title = m.tier === "ask" ? "Confirm Destructive Operation" : "Dangerous Command Warning";
        const ok = await confirmFn(
          title,
          `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${m.description}\n\nAllow execution?`,
        );
        if (!ok) {
          return { block: true, reason: `Blocked by user: ${m.description}` };
        }
        // 承認された場合はこのruleについては通過するが、複合コマンドが他のruleにも
        // 一致しうるため走査を継続する。
      } else {
        return { block: true, reason: `Security Gate blocked command: ${m.description}` };
      }
    }
    return undefined;
  }

  if (result.decision === "ask") {
    const reason = result.reason || "Operation requires confirmation";
    if (hasUI) {
      const ok = await confirmFn(
        "Confirm Destructive Operation",
        `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${reason}\n\nAllow execution?`,
      );
      if (!ok) {
        return { block: true, reason: `Blocked by user: ${reason}` };
      }
    } else {
      return { block: true, reason: `Security Gate blocked command: ${reason}` };
    }
  }

  return undefined;
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    const home = os.homedir();
    const root = repoRoot(import.meta.url);

    // 1. Inspect Bash Commands
    if (event.toolName === "bash") {
      const command = (event.input.command as string) || "";

      if (root && command) {
        const result = evaluateShellCommand(root, ctx.cwd, command);
        const blocked = await handleShellCommandResult(
          result,
          command,
          (title, message) => ctx.ui.confirm(title, message),
          ctx.hasUI,
        );
        if (blocked) {
          return blocked;
        }
      }

      // Vald Law 2 Check (in vald repository)
      if (root && command) {
        const valdRulesFile = path.join(root, "agent", "vald-law-rules.json");
        if (fs.existsSync(valdRulesFile)) {
          const law2 = evaluateValdLaw2(root, valdRulesFile, ctx.cwd, command);
          if (law2.decision === "block" || law2.decision === "deny") {
            return { block: true, reason: law2.reason ?? "Vald Law 2 violation" };
          }
          if (law2.decision === "ask") {
            const reason = law2.reason || "Vald Law 2 requires confirmation";
            const res = await confirmOrBlock(
              ctx,
              "Vald Law 2 Violation",
              `The agent is trying to execute:\n\n$ ${command}\n\nReason: ${reason}\n\nAllow execution?`,
              `Blocked by user: ${reason}`,
              reason,
            );
            if (res) return res;
          }
        }
      }
    }

    // 2. Inspect File Write & Edit (write / edit / ast_edit)
    if (WRITE_TOOLS.has(event.toolName)) {
      // 1 つの対象パスに対する全 write gate(security_write / Tier B / Vald Law)。
      const inspectWrite = async (rawPath: string) => {
      const resolvedPath = path.isAbsolute(rawPath) ? rawPath : path.resolve(ctx.cwd, rawPath);

      if (root) {
        const writeResult = evaluateWritePath(root, ctx.cwd, home, rawPath);
        if (writeResult.decision === "deny") {
          return {
            block: true,
            reason: writeResult.reason ?? `Security Gate denied modification to sensitive path: ${resolvedPath}`,
          };
        }
        if (writeResult.decision === "block" || writeResult.decision === "ask") {
          const label = writeResult.reason ?? "";
          const res = await confirmOrBlock(
            ctx,
            "Protected File Modification",
            `The agent is trying to write to sensitive file (${label}):\n\n${resolvedPath}\n\nAllow write?`,
            `Blocked by user: Modification to protected path (${resolvedPath}) denied.`,
            `Security Gate blocked modification to sensitive path: ${resolvedPath}`,
          );
          if (res) return res;
        }
      }

      // Tier B 書込保護ゲート(write-scope)
      if (root) {
        const scopeResult = evaluateWriteScope(root, ctx.cwd, home, rawPath);
        if (scopeResult.decision === "deny") {
          return {
            block: true,
            reason: scopeResult.reason ?? `Security Gate denied write to Tier B protected path: ${resolvedPath}`,
          };
        }
        if (scopeResult.decision === "block" || scopeResult.decision === "ask") {
          const reason = scopeResult.reason ?? "Tier B protected path (write-scope)";
          const res = await confirmOrBlock(
            ctx,
            "Tier B Protected Path (write-scope gate)",
            `The agent is trying to write to a Tier B protected path (${reason}):\n\n${resolvedPath}\n\nAllow write?`,
            `Blocked by user: Tier B protected path (${resolvedPath}) denied.`,
            `Security Gate blocked write to Tier B protected path: ${resolvedPath}`,
          );
          if (res) return res;
        }
      }

      if (root) {
        const valdRulesFile = path.join(root, "agent", "vald-law-rules.json");
        if (fs.existsSync(valdRulesFile)) {
          // Vald Law 1 Check: *.pb.go, *_vtproto.pb.go, *_grpc.pb.go, *.pb.gw.go are generated
          const law1 = evaluateValdLaw1(root, valdRulesFile, resolvedPath);
          if (law1.decision === "block" || law1.decision === "deny") {
            return { block: true, reason: law1.reason ?? "Vald Law 1 violation" };
          }
          if (law1.decision === "ask") {
            const reason = law1.reason || "Vald Law 1 requires confirmation";
            const res = await confirmOrBlock(
              ctx,
              "Vald Law 1 Violation",
              `${reason}\n\n${resolvedPath}\n\nAllow write?`,
              `Blocked by user: ${reason}`,
              reason,
            );
            if (res) return res;
          }

          // Vald Laws 3/4/5
          const content = extractWrittenContent(event);
          if (content) {
            const law345 = evaluateValdLaw345(root, valdRulesFile, ctx.cwd, resolvedPath, content);
            if (law345.decision === "block" || law345.decision === "deny") {
              return { block: true, reason: law345.reason ?? "Vald Law 3/4/5 violation" };
            }
            if (law345.decision === "ask") {
              const violations = law345.violations ?? [];
              const reason =
                violations.length > 0
                  ? `Vald Law violation(s) in ${path.basename(resolvedPath)}:\n${violations.slice(0, 5).map((v) => `- ${v}`).join("\n")}`
                  : (law345.reason || `Vald Law 3/4/5 violation in ${path.basename(resolvedPath)}`);
              const res = await confirmOrBlock(
                ctx,
                "Vald Law 3/4/5 Violation",
                `${reason}\n\nAllow write?`,
                `Blocked by user: ${reason}`,
                reason,
              );
              if (res) return res;
            }
          }
        }
      }
      };

      let rawPaths: string[];
      if (event.toolName === "ast_edit") {
        // ast_edit は実在する通常ファイルに解決できる場合のみ評価し、それ以外は fail-closed で block する。
        const targets = resolveAstEditTargets(event.input as Record<string, unknown>, ctx.cwd);
        if (!targets.ok) {
          return { block: true, reason: `Security Gate blocked ast_edit (fail-closed): ${targets.reason}` };
        }
        rawPaths = targets.paths;
      } else {
        const inp = event.input as Record<string, any>;
        const str = (v: unknown): v is string => typeof v === "string" && v !== "";
        // ツール(write は path のみ)とゲートが別のキーを見ないよう file_path と path の両方を評価し、OMP が補う paths[] と
        // edit の本文(hashline の [PATH#TAG]・MV 移動先 / apply_patch の *** File:・*** Move to:)の path も全て評価する。
        const payload = event.toolName === "edit" ? parseEditPayload(inp) : { hasPayload: false, paths: [] as string[], text: "", suspicious: false };
        // patch モードの edits[].rename(移動先)も書込先。
        const renames = Array.isArray(inp.edits) ? inp.edits.map((e: any) => e?.rename) : [];
        const cands = [...new Set([inp.file_path, inp.path, ...(Array.isArray(inp.paths) ? inp.paths : []), ...payload.paths, ...renames].filter(str))];
        if (payload.suspicious) {
          // 認識できない `***` 行は、native パーサが別のヘッダとして読む書込先を隠しているかもしれない。
          return { block: true, reason: "Security Gate blocked edit (fail-closed): the edit input has an unrecognised '***' directive line" };
        }
        if (cands.length === 0) {
          // edit の本文から書込先を特定できないものは fail-closed(従来は path が無いだけで素通りだった)。
          if (payload.hasPayload) return { block: true, reason: "Security Gate blocked edit (fail-closed): cannot identify the files the edit input writes" };
          return;
        }
        // OMP の write/edit は internal URL も書込先にできる(ssh:// は遠隔、vault:// cfg:// conflict:// proc:// agent:// out:// 等は実際の
        // 書込先・効果がゲートから見えない。proc:// は実行中プロセスの stdin への書込で bash ゲートの迂回になる)。そのため許可するのは
        // local://(セッション内の scratch)・xd://(ast_edit の適用)・file:// だけにして、それ以外の `scheme://` は fail-closed。
        const internal = cands.find((c) => {
          const m = /^([A-Za-z][A-Za-z0-9+.-]+):\/\//.exec(unwrapHashlineHeaderPath(c).replace(/^[:@]/, ""));
          return (m !== null && !["local", "xd", "file"].includes(m[1].toLowerCase())) || c.includes("conflict://");
        });
        if (internal !== undefined) {
          return { block: true, reason: `Security Gate blocked ${event.toolName} (fail-closed): '${internal}' is an internal URL whose real write target or effect the gate cannot verify (only local:// xd:// file:// are allowed)` };
        }
        // OMP の expandPath は Windows 系の形も解釈する(ドライブ表記は WSL で /mnt/<drive>/ へ変換、`\x` と `~\x` の区切り、UNC)。
        // この gate は Linux/macOS 向けで、その解釈を写さない。dotfiles の Linux/macOS では正当な用途が無いので fail-closed。
        const winlike = cands.find((c) => /^(?:[A-Za-z]:[\\/]|~?\\)/.test(unwrapHashlineHeaderPath(c).replace(/^[:@]/, "")));
        if (winlike !== undefined) {
          return { block: true, reason: `Security Gate blocked ${event.toolName} (fail-closed): '${winlike}' is a Windows-style path (drive letter / UNC / backslash) whose resolution the gate does not model` };
        }
        // 適用(write xd://resolve)の直前に、プレビューで許可した ast_edit の対象が同じ実体を指しているか再確認する。
        // 破棄(write xd://reject)なら記録を全て捨てる。適用が通っても捨てない(どのプレビューが適用されるか分からないため)。
        if (event.toolName === "write" && cands.some(isResolveDevice)) {
          const why = checkAstEditStillSame();
          if (why !== undefined) return { block: true, reason: `Security Gate blocked applying the staged ast_edit (fail-closed): ${why}` };
        } else if (event.toolName === "write" && cands.some(isRejectDevice)) {
          pendingAstEdits.length = 0;
        }
        // ツールは自前の path 正規化(hashline ラッパー / @ / file:// / 迷子 ':' / ~ / Unicode 空白)で書込先を決めるため、
        // 生の形と正規化後の両方を評価する(デコイ相対 path で実際の保護先を隠せないように)。
        rawPaths = [];
        for (const c of cands) {
          rawPaths.push(c);
          const n = normalizeToolPath(c, home);
          if (n !== c) rawPaths.push(n);
        }
      }
      for (const rp of rawPaths) {
        const res = await inspectWrite(rp);
        if (res) return res;
      }
      // 許可した ast_edit のプレビュー対象を記録する(適用時に解決先が変わっていないか xd://resolve で再確認する)。
      if (event.toolName === "ast_edit") rememberAstEditPreview(rawPaths);
    }
  });
}
