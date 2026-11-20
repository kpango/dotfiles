/**
 * SoL-Pi (arXiv:2609.20519) runtime enforcement core.
 *
 * - Action Fusion: run an extension-specific validator right after an edit.
 * - ObservationPack: archive large tool outputs, replay compact handles later.
 * - Evidence-Preserving Reducer: shrink build/test logs, verifying every quote
 *   against the raw log (fail-closed to a deterministic raw excerpt).
 * - Online compaction: Pricing Cliff *recommendation* only (never auto-applies).
 *
 * Thresholds come from sol-pi.json; hard-coded values are defaults only.
 * Validators run asynchronously (never block the event loop) with an allowlisted
 * environment (no API keys / tokens), a hard timeout that kills the process group,
 * and are scoped to the edited file/package. Build-executing validators are never run for
 * build-definition files (build.rs, Cargo.toml, go.mod, Makefile ...), and cargo-class
 * validators run ONLY through `unshare -rn -- pa-sandbox -- cmd` (no network; skipped when either is missing). `go vet` is not
 * sandboxed; it runs with GOPROXY=off / GOTOOLCHAIN=local and GOFLAGS stripped of -toolexec/-exec/-vettool (goValidatorEnv),
 * which closes the download and tool-injection paths. cgo stays on (cgo packages cannot be vetted otherwise), so this is not isolation.
 * Pricing Cliff thresholds: single source = agent/models/catalog.json compaction_threshold.
 *
 * Ordering invariant for everything that leaves this module as text:
 *   verify against the RAW line -> mask the WHOLE line -> only then cut to a byte cap.
 * (Cutting first could leave the head of a secret that no pattern recognises.)
 */
import { spawn } from "node:child_process";
import { createHash, randomBytes } from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { loadModelCatalog, lookupCompactionThreshold, type ModelCatalogData } from "./model-catalog";

export interface SolPiConfig {
  cacheWriteReadRatio: number;
  actionFusionConfig: {
    enabled: boolean;
    timeoutMs: number;
    defaultValidators: Record<string, string>;
  };
  /** Kill switch for Pricing Cliff advisories/detectors only (toast, badge, failover advice, pricing_cliff detector). */
  pricingCliffAdvisoryConfig: {
    enabled: boolean;
  };
  observationPackConfig: {
    enabled: boolean;
    minBytesThreshold: number;
    fullReplayTurns: number;
    headLines: number;
    tailLines: number;
    archiveDir: string;
    maxArchiveFiles: number;
    maxArchiveBytes: number;
  };
  evidencePreservingReducerConfig: {
    enabled: boolean;
    minBytesThreshold: number;
    maxInputBytes: number;
    failClosedOnQuoteMismatch: boolean;
    verifyExitCode: boolean;
    redactSecrets: boolean;
  };
  onlineContextCompactConfig: {
    enabled: boolean;
    tokenPressureThreshold: number;
    respectPricingCliffs: boolean;
    warnRatio: number;
  };
}

/** Legacy shipped value of observationPackConfig.archiveDir; resolved to a safe per-user dir. */
export const LEGACY_ARCHIVE_DIR = "/tmp/omp-obs-pack";

export const DEFAULT_CONFIG: SolPiConfig = {
  cacheWriteReadRatio: 12.5,
  actionFusionConfig: {
    enabled: true,
    timeoutMs: 15000,
    defaultValidators: {
      ".go": "go vet ./...",
      ".rs": "cargo check --quiet",
      ".nix": "nix-instantiate --parse",
      ".sh": "bash -n",
      ".json": "python3 -I -m json.tool",
      ".py": "python3 -I -m py_compile",
    },
  },
  pricingCliffAdvisoryConfig: {
    enabled: true,
  },
  observationPackConfig: {
    enabled: true,
    minBytesThreshold: 10240,
    fullReplayTurns: 2,
    headLines: 20,
    tailLines: 15,
    archiveDir: LEGACY_ARCHIVE_DIR,
    maxArchiveFiles: 200,
    maxArchiveBytes: 64 * 1024 * 1024,
  },
  evidencePreservingReducerConfig: {
    enabled: true,
    minBytesThreshold: 4096,
    maxInputBytes: 65536,
    failClosedOnQuoteMismatch: true,
    verifyExitCode: true,
    redactSecrets: true,
  },
  onlineContextCompactConfig: {
    enabled: true,
    tokenPressureThreshold: 180000,
    respectPricingCliffs: true,
    warnRatio: 0.85,
  },
};

// ---------------------------------------------------------------------------
// Config loading
// ---------------------------------------------------------------------------
const warned = new Set<string>();
/** Default warning sink: emits each distinct message once per process. */
export function warnOnce(msg: string): void {
  if (warned.has(msg)) return;
  warned.add(msg);
  console.warn(`[sol-pi] ${msg}`);
}

function defaultConfigPath(): string {
  return path.resolve(import.meta.dir, "..", "..", "sol-pi.json");
}

const FORBIDDEN_KEYS = new Set(["__proto__", "constructor", "prototype"]);

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** Deep-merge `over` onto `base`: only keys known to `base`, same type, never dangerous keys. */
function merge<T>(base: T, over: unknown): T {
  if (!isObj(base) || !isObj(over)) return base;
  const out: Record<string, unknown> = { ...base };
  for (const [k, v] of Object.entries(over)) {
    if (FORBIDDEN_KEYS.has(k)) continue;
    const b = (base as Record<string, unknown>)[k];
    if (b === undefined) continue;
    if (isObj(b)) out[k] = merge(b, v);
    else if (typeof b === typeof v && Array.isArray(b) === Array.isArray(v)) out[k] = v;
  }
  return out as T;
}

const FLAG_MAP: [string, keyof SolPiConfig][] = [
  ["actionFusion", "actionFusionConfig"],
  ["observationPack", "observationPackConfig"],
  ["evidencePreservingReducer", "evidencePreservingReducerConfig"],
  ["onlineContextCompact", "onlineContextCompactConfig"],
  ["pricingCliffAdvisory", "pricingCliffAdvisoryConfig"],
];

export function loadSolPiConfig(file?: string, onWarn: (msg: string) => void = warnOnce): SolPiConfig {
  const target = file ?? defaultConfigPath();
  const cfg: SolPiConfig = JSON.parse(JSON.stringify(DEFAULT_CONFIG));
  let raw: unknown;
  try {
    raw = JSON.parse(fs.readFileSync(target, "utf-8"));
  } catch (e) {
    const err = e as NodeJS.ErrnoException;
    if (err.code !== "ENOENT") onWarn(`cannot load ${target}: ${err.message}; using defaults`);
    return cfg;
  }
  const merged = merge(cfg, raw);
  if (isObj(raw)) {
    // Validators are an open map: allow adding extensions.
    const af = raw.actionFusionConfig;
    const dv = isObj(af) ? af.defaultValidators : undefined;
    if (isObj(dv)) {
      for (const [k, v] of Object.entries(dv)) {
        if (!FORBIDDEN_KEYS.has(k) && k.startsWith(".") && typeof v === "string") merged.actionFusionConfig.defaultValidators[k] = v;
      }
    }
    // Top-level boolean flags are authoritative kill-switches.
    for (const [flag, section] of FLAG_MAP) {
      if (raw[flag] === false) (merged[section] as { enabled: boolean }).enabled = false;
    }
  }
  return merged;
}

// ---------------------------------------------------------------------------
// Secret redaction (best-effort, linear time)
//
// This is a heuristic denylist, NOT a guarantee: unknown token formats, secrets
// split across lines, or secrets that do not look like credentials can survive.
// Design rules that keep it safe to run over untrusted, adversarial output:
//   * no `\b` before token prefixes (a secret glued to a word, e.g. "TestSksk-...", must match);
//   * every quantifier is bounded, and keyword rules start at a literal keyword, so
//     matching is linear (no nested/ambiguous repetition);
//   * work is per line; a line longer than MAX_REDACT_LINE is cut (with a marker) BEFORE
//     matching, so the part that cannot be inspected never leaves this module;
//   * the whole input is capped at MAX_REDACT_INPUT chars (head + tail kept, the middle is
//     replaced by a marker), so cost does not grow with output size. Consequence: archives
//     built from redacted text can be LOSSY for huge outputs;
//   * a cheap prefilter skips the pattern list for lines that contain no trigger word;
//   * multi-line PEM/PGP private key blocks are handled by a small state machine
//     (at most MAX_PEM_LINES lines are dropped, then masking resumes);
//   * a value that is quoted but unterminated/too long, or that opens a nested structure,
//     is masked to the end of the line. Bare values run to the next whitespace (so
//     `password=abc,def` is fully masked); this over-masks things like `token=x&next=1`.
// JSON-escaped keys/values (`{\"password\":\"x\"}`, up to 4 backslashes) are handled too.
// ---------------------------------------------------------------------------
const MAX_REDACT_LINE = 4096;
const MAX_REDACT_INPUT = 512 * 1024;
const REDACT_KEEP = 256 * 1024;
const MAX_PEM_LINES = 200;
const KEY_WORDS = "(?:token|api[_-]?key|secret|passw(?:or)?d|pwd|credential|private[_-]?key|access[_-]?key|(?:pass|key|auth|bearer)(?![A-Za-z]))";
// optional (possibly JSON-escaped) quote adjacent to a key
const KQ = String.raw`(?:\\{0,4}["'])?`;
// quoted value: escaped-quote string | "..." | '...' | unterminated/too-long quote to end of line
const QUOTED = String.raw`(?:\\{1,4}"[^"\\\n]{0,512}\\{1,4}"|"(?:[^"\\\n]|\\.){0,512}"|'(?:[^'\\\n]|\\.){0,512}'|\\{0,4}["'][^\n]*)`;
const VALUE = String.raw`(?:${QUOTED}|[{\[][^\n]*|\S+)`;
const SECRET_PATTERNS: [RegExp, string][] = [
  [/((?:Set-)?Cookie(?:\\{0,4}["'])?\s{0,8}:\s{0,8})[^\n]+/gi, "$1***"],
  [/(Authorization(?:\\{0,4}["'])?\s{0,8}[:=]\s{0,8})[^\n]+/gi, "$1***"],
  [new RegExp(String.raw`(${KEY_WORDS}[A-Za-z0-9_-]{0,40}${KQ}\s{0,8}[:=](?:=|>)?\s{0,8}(?:\(\s{0,8}|!![a-z]{1,10}\s{1,8})?)${VALUE}`, "gi"), "$1***"],
  [/((?:^|\s)(?:-u|--user|--password|--passwd|--pass|--token|--secret|--api-key|-b|--cookie)(?:\s+|=))(?!-)\S+/gi, "$1***"],
  [/((?:^|\s)-u)[^\s:]{1,64}:\S+/g, "$1***"],
  [/(\b(?:mysql|mysqldump|mysqladmin|mariadb)\b[^\n]{0,200}?\s-p)\S+/gi, "$1***"],
  [/((?:X-Amz-(?:Signature|Security-Token|Credential)|Signature)=)[^&\s"']+/gi, "$1***"],
  [/([a-z][a-z0-9+.-]{1,20}:\/\/)[^\s\/?#]{0,200}@/gi, "$1***@"],
  [/Bearer\s{1,8}[A-Za-z0-9._~+\/=-]{8,}/gi, "Bearer ***"],
  [/github_pat_[A-Za-z0-9_]{20,}/g, "github_pat_***"],
  [/glpat-[A-Za-z0-9_-]{20,}/g, "glpat-***"],
  [/glsa_[A-Za-z0-9_]{20,}/g, "glsa_***"],
  [/npm_[A-Za-z0-9]{30,}/g, "npm_***"],
  [/AIza[0-9A-Za-z_-]{35}/g, "AIza***"],
  [/eyJ[A-Za-z0-9_-]{5,2000}\.[A-Za-z0-9_-]{1,2000}\.[A-Za-z0-9_-]{1,2000}/g, "***JWT***"],
  [/(?:AKIA|ASIA)[0-9A-Z]{16}/g, "AWSKEY***"],
  [/[sr]k_(?:live|test)_[A-Za-z0-9]{10,}/g, "sk_***"],
  [/sk-[A-Za-z0-9_-]{16,}/g, "sk-***"],
  [/SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}/g, "SG.***"],
  [/ya29\.[A-Za-z0-9_-]{20,}/g, "ya29.***"],
  [/hf_[A-Za-z0-9]{30,}/g, "hf_***"],
  [/gh[pousr]_[A-Za-z0-9]{20,}/g, "gh*_***"],
  [/xox[abprs]-[A-Za-z0-9-]{10,}/g, "xox*-***"],
];
// Superset of every trigger above (case-insensitive): a line without any of these cannot match.
const MAYBE_SECRET = /cookie|authorization|token|key|secret|pass|pwd|credential|auth|bearer|:\/\/|-u|--|-b|mysql|mariadb|amz|signature|github_pat|glpat|glsa_|npm_|aiza|eyj|akia|asia|[sr]k_|sk-|sg\.|ya29|hf_|gh[pousr]_|xox/i;
const PEM_BEGIN = /-----BEGIN [A-Z ]{0,40}PRIVATE KEY(?: BLOCK)?-----/;
const PEM_END = /-----END [A-Z ]{0,40}PRIVATE KEY(?: BLOCK)?-----/;
const PEM_MARK = "[REDACTED PRIVATE KEY]";
const TOKEN_CHAR = /[A-Za-z0-9_\-.\/+=]/;

function redactLine(line: string): string {
  let l = line;
  let tail = "";
  if (l.length > MAX_REDACT_LINE) {
    let end = MAX_REDACT_LINE;
    // never leave the head of a possibly-cut token: drop the trailing run of token characters
    let back = 0;
    while (back < 256 && TOKEN_CHAR.test(l[end - 1 - back] ?? " ")) back++;
    end -= back >= 256 ? 256 : back;
    tail = `…[${l.length - end} chars truncated before redaction]`;
    l = l.slice(0, end);
  }
  if (!MAYBE_SECRET.test(l)) return l + tail;
  for (const [re, rep] of SECRET_PATTERNS) l = l.replace(re, rep);
  return l + tail;
}

const BASE64_LINE = /^[A-Za-z0-9+\/=_-]{16,}$/;
const PGP_CRC_LINE = /^=[A-Za-z0-9+\/]{4}$/;

/**
 * The input cap keeps the last REDACT_KEEP chars. If that cut landed INSIDE a private key block,
 * the BEGIN line is gone and the PEM state machine would never start, leaving the key body.
 *  - END line before any BEGIN line -> the tail started inside a key: drop everything up to it.
 *  - neither marker anywhere       -> an unterminated key: drop a leading run (>= 1 line) of
 *    base64-looking lines (a heuristic; it may also drop a genuine long token/base64 line that
 *    happens to be the first line of the kept tail).
 */
function dropLeadingKeyInterior(tail: string): string {
  const lines = tail.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (l.includes("-----END") && PEM_END.test(l)) return `${PEM_MARK}\n${lines.slice(i + 1).join("\n")}`;
    if (l.includes("-----BEGIN") && PEM_BEGIN.test(l)) return tail; // a block that starts normally comes first
  }
  let n = 0;
  let i = 0;
  while (i < lines.length && (BASE64_LINE.test(lines[i]) || PGP_CRC_LINE.test(lines[i]) || lines[i] === "")) {
    if (lines[i] !== "") n++;
    i++;
  }
  return n >= 1 ? `${PEM_MARK}\n${lines.slice(i).join("\n")}` : tail;
}

export function redactSecrets(input: string): string {
  let text = input;
  if (text.length > MAX_REDACT_INPUT) {
    let head = text.slice(0, REDACT_KEEP);
    const hn = head.lastIndexOf("\n");
    if (hn > 0) head = head.slice(0, hn);
    let tail = text.slice(-REDACT_KEEP);
    const tn = tail.indexOf("\n");
    if (tn >= 0) tail = tail.slice(tn + 1);
    tail = dropLeadingKeyInterior(tail);
    text =`${head}\n…[${text.length - head.length - tail.length} chars omitted before redaction]\n${tail}`;
  }
  const out: string[] = [];
  let inPem = false;
  let pemLines = 0;
  for (const line of text.split("\n")) {
    if (inPem) {
      pemLines++;
      const e = PEM_END.exec(line);
      if (!e) {
        if (pemLines > MAX_PEM_LINES) {
          inPem = false;
          out.push(`…[private key block longer than ${MAX_PEM_LINES} lines: masking resumed]`);
        }
        continue; // inside a key block: emit nothing
      }
      inPem = false;
      out.push(redactLine(line.slice(e.index + e[0].length)));
      continue;
    }
    if (line.includes("-----BEGIN")) {
      const b = PEM_BEGIN.exec(line);
      if (b) {
        const rest = line.slice(b.index + b[0].length);
        const e = PEM_END.exec(rest);
        if (e) out.push(redactLine(line.slice(0, b.index)) + PEM_MARK + redactLine(rest.slice(e.index + e[0].length)));
        else {
          out.push(redactLine(line.slice(0, b.index)) + PEM_MARK);
          inPem = true;
          pemLines = 0;
        }
        continue;
      }
    }
    out.push(redactLine(line));
  }
  return out.join("\n");
}

// ---------------------------------------------------------------------------
// Byte helpers (UTF-8 safe)
// ---------------------------------------------------------------------------
const byteLen = (s: string): number => Buffer.byteLength(s);

/** Longest prefix of `s` within `max` bytes, never splitting a character. */
function truncateBytes(s: string, max: number): string {
  if (max <= 0) return "";
  if (byteLen(s) <= max) return s;
  const buf = Buffer.from(s);
  let end = max;
  while (end > 0 && (buf[end] & 0xc0) === 0x80) end--; // back off continuation bytes
  return buf.subarray(0, end).toString("utf-8");
}

const MAX_LINE_BYTES = 512;
const MAX_EXCERPT_BYTES = 8192;
const MAX_SCAN_LINE_CHARS = 2048;

/** head/tail excerpt of ALREADY-MASKED lines: non-overlapping, capped per line and in total. */
function excerptLines(maskedLines: string[], head: number, tail: number, totalCap: number): string[] {
  const headPart = maskedLines.slice(0, head);
  const tailPart = maskedLines.slice(Math.max(headPart.length, maskedLines.length - tail));
  const omitted = maskedLines.length - headPart.length - tailPart.length;
  const count = headPart.length + tailPart.length + 1;
  const perLine = Math.max(16, Math.min(MAX_LINE_BYTES, Math.floor(totalCap / count) - 1));
  const cut = (l: string) => truncateBytes(l, perLine);
  const out = [...headPart.map(cut)];
  if (omitted > 0) out.push(`… (${omitted} lines omitted) …`);
  out.push(...tailPart.map(cut));
  return out;
}

// ---------------------------------------------------------------------------
// Action Fusion
// ---------------------------------------------------------------------------
export interface ValidatorResult {
  ran: boolean;
  ok: boolean;
  reason?: "no-validator" | "path-outside-cwd" | "disabled" | "spawn-error" | "no-go-mod" | "no-cargo-toml" | "skipped-build-file" | "sandbox-unavailable" | "no-netns";
  command?: string[];
  output: string;
  timedOut?: boolean;
}

const PROJECT_WIDE_EXT = new Set([".go", ".rs"]);
const EDIT_TOOLS = new Set(["edit", "write", "ast_edit"]);

export function isEditTool(name: string): boolean {
  return EDIT_TOOLS.has(name);
}

const CHILD_ENV_ALLOWLIST = [
  "PATH", "HOME", "USER", "LOGNAME", "LANG", "LC_ALL", "LC_CTYPE", "TERM", "TZ", "TMPDIR",
  "GOPATH", "GOCACHE", "GOMODCACHE", "GOFLAGS", "GOROOT", "GOTOOLCHAIN",
  "CARGO_HOME", "RUSTUP_HOME", "RUSTUP_TOOLCHAIN", "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME",
  "NIX_PATH", "NIX_REMOTE",
  // Without these a validator that must fetch a private module would ask the PUBLIC proxy/sumdb
  // for it and leak internal module paths. Proxy/TLS settings are configuration, not credentials.
  "GOPRIVATE", "GONOPROXY", "GONOSUMDB", "GOPROXY", "GOSUMDB", "GOINSECURE", "GOENV",
  "HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY", "https_proxy", "http_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
];

function childEnv(extra?: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {};
  for (const k of CHILD_ENV_ALLOWLIST) if (process.env[k] !== undefined) env[k] = process.env[k];
  return extra ? { ...env, ...extra } : env;
}

/**
 * `go vet` compiles and analyses; it does not run repo code. Closed here: a toolchain/module download (GOTOOLCHAIN=local,
 * GOPROXY=off) and GOFLAGS carrying -toolexec / -exec / -vettool, which would run an arbitrary program for every step.
 * The user's other GOFLAGS (-tags=..., -race ...) are kept, and -mod=readonly is added only when no -mod is given.
 * cgo is deliberately NOT disabled: cgo packages (Vald's ngt/faiss) cannot be vetted without it, so a C compiler may
 * still run on the repo's C sources (accepted). Not a sandbox: a compiler or analyzer bug runs with the user's privileges.
 */
export function goValidatorEnv(userFlags: string | undefined = process.env.GOFLAGS): NodeJS.ProcessEnv {
  // cmd/go reads GOFLAGS with quoting and accepts both `-flag` and `--flag`, so compare the normalised flag name. A value that
  // uses quotes cannot be split reliably here, so it is dropped entirely (the vet then runs with the defaults + -mod=readonly).
  const raw = userFlags ?? "";
  const flagName = (t: string): string => t.replace(/^-+/, "").split("=")[0];
  const tokens = /["']/.test(raw) ? [] : raw.split(/\s+/).filter((t) => t !== "");
  const kept = tokens.filter((t) => !["toolexec", "exec", "vettool"].includes(flagName(t)));
  if (!kept.some((t) => flagName(t) === "mod")) kept.push("-mod=readonly");
  // GOENV=off: the go env file (default ~/.config/go/env) is writable without any gate and can set GOFLAGS (-toolexec), CC,
  // CGO_CFLAGS=-fplugin=..., GOROOT ...; the validator must not read it. (GOROOT / PATH / GOCACHE still come from the
  // process environment, which is trusted; a poisoned GOCACHE could only forge a verdict, not run code.)
  return { GOENV: "off", GOPROXY: "off", GOTOOLCHAIN: "local", GOFLAGS: kept.join(" ") };
}

/** Throws for errors other than ENOENT (e.g. ELOOP / EACCES): callers must handle. */
function realpathOrSelf(p: string): string {
  try {
    return fs.realpathSync(p);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return p;
    throw e;
  }
}

function insideCwd(abs: string, cwd: string): boolean {
  const rel = path.relative(realpathOrSelf(cwd), realpathOrSelf(abs));
  if (rel === "") return true;
  return !(rel === ".." || rel.startsWith(".." + path.sep) || path.isAbsolute(rel));
}

/** Nearest ancestor directory (not above cwd) containing `marker`, else null. */
function findProjectRoot(start: string, cwd: string, marker: string): string | null {
  const root = realpathOrSelf(cwd);
  let dir = realpathOrSelf(start);
  for (;;) {
    if (fs.existsSync(path.join(dir, marker))) return dir;
    if (dir === root) return null;
    const parent = path.dirname(dir);
    if (parent === dir || !insideCwd(parent, cwd)) return null;
    dir = parent;
  }
}

/** Files whose edit may define code a build tool executes (build scripts, manifests, make includes). */
const BUILD_DEFINITION_NAMES = new Set([
  "build.rs", "Cargo.toml", "Cargo.lock", "go.mod", "go.work", "go.sum", "package.json",
  "Makefile", "makefile", "GNUmakefile", "setup.py", "pyproject.toml",
]);

/** True for build-definition files; also anything under a `.cargo/` directory or `*.mk`. */
export function isBuildDefinitionFile(abs: string, cwd: string): boolean {
  const base = path.basename(abs);
  if (BUILD_DEFINITION_NAMES.has(base) || base.endsWith(".mk")) return true;
  const rel = path.relative(realpathOrSelf(cwd), realpathOrSelf(abs));
  return rel.split(path.sep).includes(".cargo");
}

/** Tools that execute project code when they validate (build scripts, proc macros, Makefile parse, install hooks). */
const BUILD_TOOLS = new Set([
  "go", "cargo", "rustc", "cargo-clippy", "clippy-driver", "make", "gmake", "cmake", "ninja", "meson",
  "npm", "npx", "yarn", "pnpm", "bun", "pip", "pip3", "gradle", "mvn", "maturin", "nix", "nix-build",
]);
/** Build tools that must run inside pa-sandbox AND a network namespace (unshare -rn) (everything build-class except `go`, which is scoped instead). */
function mustSandbox(tool: string): boolean {
  return BUILD_TOOLS.has(tool) && tool !== "go";
}

/** pa-sandbox location: the installed ~/.local/bin copy, else the repo copy next to this extension tree; null if neither is executable. */
export function resolvePaSandbox(): string | null {
  const candidates = [path.join(os.homedir(), ".local", "bin", "pa-sandbox"), path.resolve(import.meta.dir, "..", "..", "..", "..", "scripts", "sandbox", "pa-sandbox")];
  for (const c of candidates) {
    try {
      fs.accessSync(c, fs.constants.X_OK);
      if (fs.statSync(c).isFile()) return c;
    } catch {
      // try next
    }
  }
  return null;
}

let netnsProbe: Promise<boolean> | undefined;
/** True when `unshare -rn` works here (unprivileged user + network namespace). Probed once per process. */
export function netnsAvailable(): Promise<boolean> {
  netnsProbe ??= runChild(["unshare", "-rn", "true"], os.tmpdir(), 5000).then((r) => !r.spawnError && !r.timedOut && r.status === 0);
  return netnsProbe;
}

interface ChildResult {
  status: number | null;
  stdout: string;
  stderr: string;
  spawnError?: Error;
  timedOut: boolean;
}

/**
 * Async child runner: own process group (detached), hard timeout kills the whole group, output capped.
 * Backstop: a grandchild that escaped the group (setsid) and holds the pipes cannot stall us past timeoutMs + 1s.
 */
function runChild(argv: string[], cwd: string, timeoutMs: number, env?: NodeJS.ProcessEnv): Promise<ChildResult> {
  return new Promise((resolve) => {
    const MAX = 1 << 20;
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let done = false;
    let child: ReturnType<typeof spawn>;
    const finish = (status: number | null, spawnError?: Error) => {
      if (done) return;
      done = true;
      clearTimeout(killTimer);
      clearTimeout(backstop);
      child?.stdout?.destroy();
      child?.stderr?.destroy();
      resolve({ status, stdout, stderr, spawnError, timedOut });
    };
    const killGroup = () => {
      try {
        if (child.pid) process.kill(-child.pid, "SIGKILL");
      } catch {
        try {
          child.kill("SIGKILL");
        } catch {
          // already gone
        }
      }
    };
    let killTimer: ReturnType<typeof setTimeout>;
    let backstop: ReturnType<typeof setTimeout>;
    try {
      child = spawn(argv[0], argv.slice(1), { cwd, env: childEnv(env), detached: true, stdio: ["ignore", "pipe", "pipe"] });
    } catch (e) {
      resolve({ status: null, stdout, stderr, spawnError: e as Error, timedOut: false });
      return;
    }
    killTimer = setTimeout(() => {
      timedOut = true;
      killGroup();
    }, timeoutMs);
    backstop = setTimeout(() => {
      timedOut = true;
      killGroup();
      finish(null);
    }, timeoutMs + 1000);
    child.stdout?.on("data", (d: Buffer) => {
      if (stdout.length < MAX) stdout += d.toString("utf-8");
    });
    child.stderr?.on("data", (d: Buffer) => {
      if (stderr.length < MAX) stderr += d.toString("utf-8");
    });
    child.on("error", (e) => finish(null, e));
    child.on("close", (code) => finish(code));
  });
}

/**
 * Runs the extension-specific validator asynchronously. No shell: argv array.
 * Guards, in order: disabled -> path inside cwd -> validator exists -> build-executing validators are skipped for
 * build-definition files -> cargo-class (non-go build tools) run only via `unshare -rn -- pa-sandbox` (no network), else skipped (sandbox-unavailable | no-netns) -> `go vet` is
 * scoped to the edited package. May reject on filesystem errors such as ELOOP/EACCES while resolving the path.
 * `deps.sandboxBin`: undefined = auto-resolve, null = force "unavailable" (tests).
 */
export async function runActionFusionValidator(
  filePath: string,
  cwd: string,
  config: SolPiConfig = loadSolPiConfig(),
  deps: { sandboxBin?: string | null; netns?: boolean } = {},
): Promise<ValidatorResult> {
  const af = config.actionFusionConfig;
  if (!af.enabled) return { ran: false, ok: true, reason: "disabled", output: "" };

  const abs = path.resolve(cwd, filePath);
  if (!insideCwd(abs, cwd)) return { ran: false, ok: false, reason: "path-outside-cwd", output: "" };

  const ext = path.extname(abs);
  const spec = af.defaultValidators[ext];
  if (!spec) return { ran: false, ok: true, reason: "no-validator", output: "" };

  let tokens = spec.split(/\s+/).filter(Boolean);
  // Defence in depth: python validators always run isolated (-I).
  if (/^python3?$/.test(path.basename(tokens[0] ?? "")) && !tokens.includes("-I")) tokens = [tokens[0], "-I", ...tokens.slice(1)];
  const tool = path.basename(tokens[0] ?? "");
  const buildClass = BUILD_TOOLS.has(tool);

  if (buildClass && isBuildDefinitionFile(abs, cwd)) {
    return { ran: false, ok: true, reason: "skipped-build-file", output: `${path.basename(abs)} can define code that ${tool} would execute; validator not run` };
  }

  let runDir = cwd;
  if (ext === ".go") {
    const root = findProjectRoot(path.dirname(abs), cwd, "go.mod");
    if (!root) return { ran: false, ok: true, reason: "no-go-mod", output: "" };
    runDir = root;
  } else if (ext === ".rs") {
    const root = findProjectRoot(path.dirname(abs), cwd, "Cargo.toml");
    if (!root) return { ran: false, ok: true, reason: "no-cargo-toml", output: "" };
    runDir = root;
  }

  let argv: string[];
  if (tokens.includes("{file}")) argv = tokens.map((t) => (t === "{file}" ? abs : t));
  else if (ext === ".go" && tokens[tokens.length - 1] === "./...") {
    // Vet the edited package only, not the whole module.
    const rel = path.relative(realpathOrSelf(runDir), realpathOrSelf(path.dirname(abs))).split(path.sep).join("/");
    argv = [...tokens.slice(0, -1), rel === "" ? "." : `./${rel}`];
  } else if (PROJECT_WIDE_EXT.has(ext) || tokens[tokens.length - 1] === "./...") argv = tokens;
  else argv = [...tokens, abs];

  if (mustSandbox(tool)) {
    const bin = deps.sandboxBin === undefined ? resolvePaSandbox() : deps.sandboxBin;
    if (!bin) return { ran: false, ok: true, reason: "sandbox-unavailable", output: `pa-sandbox not found; ${tool} validator skipped (never run unsandboxed)` };
    // pa-sandbox keeps the network ON, so cut it from outside: a fresh network namespace (loopback down, no routes).
    // No namespace support -> skip; never fall back to running with network.
    if (!(deps.netns ?? (await netnsAvailable()))) return { ran: false, ok: true, reason: "no-netns", output: `unshare -rn unavailable; ${tool} validator skipped (never run with network)` };
    argv = ["unshare", "-rn", "--", bin, "--", ...argv];
  }

  const r = await runChild(argv, runDir, af.timeoutMs, tool === "go" ? goValidatorEnv() : undefined);
  const output = redactSecrets(`${r.stdout}${r.stderr}`.trim());
  if (r.spawnError) return { ran: true, ok: false, command: argv, output: output || r.spawnError.message, reason: "spawn-error" };
  if (r.timedOut) return { ran: true, ok: false, command: argv, output: output || `timed out after ${af.timeoutMs}ms`, timedOut: true };
  if (r.status !== 0 && argv[0] !== tokens[0] && /^pa-sandbox:/.test(output)) {
    // The sandbox itself refused to start (no bwrap, no .git workspace ...): inconclusive, never a validator failure.
    return { ran: false, ok: true, reason: "sandbox-unavailable", command: argv, output };
  }
  return { ran: true, ok: r.status === 0, command: argv, output };
}

/** Anti-pattern: an edit immediately followed by a separate bash call. */
export function detectEditThenBash(recentTools: string[]): boolean {
  const n = recentTools.length;
  return n >= 2 && recentTools[n - 1] === "bash" && isEditTool(recentTools[n - 2]);
}

// ---------------------------------------------------------------------------
// Command / exit-code helpers
// ---------------------------------------------------------------------------
const SEGMENT_SPLIT = /&&|\|\||[;|\n]/;
const SEGMENT_PREFIX = String.raw`^[\s({!]*(?:(?:[A-Za-z_][A-Za-z0-9_]*=\S*|sudo|time|env|command|nice|nohup|exec)\s+)*`;
const BUILD_TARGET = String.raw`(?:go\s+(?:test|build|vet)|cargo\s+(?:test|build|check|clippy)|make|npm\s+(?:test|run)|bun\s+test|pytest|nix\s+build|nix-build|ctest|cmake\s+--build)(?:\s|$)`;
const BUILD_SEGMENT = new RegExp(SEGMENT_PREFIX + BUILD_TARGET);

/** True when some command SEGMENT starts with a build/test tool (not merely mentions one). */
export function isBuildOrTestCommand(command: string): boolean {
  return command.split(SEGMENT_SPLIT).some((seg) => BUILD_SEGMENT.test(seg));
}

/** Exit code from event.exitCode or event.result.exitCode (loop-controller convention); undefined when unknown. */
export function resolveExitCode(event: { exitCode?: unknown; result?: unknown }): number | undefined {
  if (typeof event.exitCode === "number") return event.exitCode;
  const r = event.result;
  if (isObj(r)) {
    if (typeof r.exitCode === "number") return r.exitCode;
    const d = r.details;
    if (isObj(d) && typeof d.exitCode === "number") return d.exitCode;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// ObservationPack
// ---------------------------------------------------------------------------
export interface PackedObservation {
  packed: boolean;
  text: string;
  handle?: string;
  archivePath?: string;
  bytes: number;
  turnIndex: number;
  compactText?: string;
}

/** Safe archive directory: XDG_RUNTIME_DIR first, else per-uid dir under os.tmpdir(). */
export function resolveArchiveDir(config: SolPiConfig): string {
  const configured = config.observationPackConfig.archiveDir;
  if (configured && configured !== LEGACY_ARCHIVE_DIR) {
    if (!path.isAbsolute(configured)) throw new Error(`observationPackConfig.archiveDir must be an absolute path: ${configured}`);
    return configured;
  }
  const xdg = process.env.XDG_RUNTIME_DIR;
  if (xdg && fs.existsSync(xdg)) return path.join(xdg, "omp-obs-pack");
  return path.join(os.tmpdir(), `omp-obs-pack-${process.getuid?.() ?? 0}`);
}

function ensureSafeDir(dir: string): void {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const st = fs.lstatSync(dir);
  if (st.isSymbolicLink()) throw new Error(`archive dir is a symlink, refusing: ${dir}`);
  if (!st.isDirectory()) throw new Error(`archive path is not a directory: ${dir}`);
  const uid = process.getuid?.();
  if (uid !== undefined && st.uid !== uid) throw new Error(`archive dir not owned by current user, refusing: ${dir}`);
  if ((st.mode & 0o777) !== 0o700) throw new Error(`archive dir mode must be 0700 (is ${(st.mode & 0o777).toString(8)}): ${dir}`);
}

const ARCHIVE_NAME = /^obs_([0-9a-f]{12})_[0-9a-f]{8}\.txt$/;

function isOwnRegular(st: fs.Stats): boolean {
  const uid = process.getuid?.();
  return st.isFile() && (uid === undefined || st.uid === uid);
}

/** Existing safe archive for this id with identical size, else null. */
function findExisting(dir: string, id: string, size: number): string | null {
  for (const name of fs.readdirSync(dir)) {
    const m = ARCHIVE_NAME.exec(name);
    if (!m || m[1] !== id) continue;
    const p = path.join(dir, name);
    const st = lstatOrNull(p); // another session may have pruned it meanwhile
    if (st && isOwnRegular(st) && (st.mode & 0o777) === 0o600 && st.size === size) return p;
  }
  return null;
}

/** lstat that treats a concurrently-deleted file (ENOENT) as absent; other errors propagate. */
function lstatOrNull(p: string): fs.Stats | null {
  try {
    return fs.lstatSync(p);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw e;
  }
}

/** Oldest-first eviction by count and total bytes; never removes `keep`. */
function pruneArchive(dir: string, keep: string, maxFiles: number, maxBytes: number): void {
  const entries: { p: string; mtime: number; size: number }[] = [];
  for (const name of fs.readdirSync(dir)) {
    if (!ARCHIVE_NAME.test(name)) continue;
    const p = path.join(dir, name);
    const st = lstatOrNull(p);
    if (st && isOwnRegular(st)) entries.push({ p, mtime: st.mtimeMs, size: st.size });
  }
  entries.sort((a, b) => a.mtime - b.mtime || a.p.localeCompare(b.p));
  let count = entries.length;
  let total = entries.reduce((s, e) => s + e.size, 0);
  for (const e of entries) {
    if (count <= maxFiles && total <= maxBytes) break;
    if (e.p === keep) continue;
    try {
      fs.unlinkSync(e.p);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err; // already pruned by another session
    }
    count--;
    total -= e.size;
  }
}

function writeArchive(dir: string, id: string, content: string): string {
  const flags = fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY | fs.constants.O_NOFOLLOW;
  for (let attempt = 0; attempt < 4; attempt++) {
    const p = path.join(dir, `obs_${id}_${randomBytes(4).toString("hex")}.txt`);
    let fd: number;
    try {
      fd = fs.openSync(p, flags, 0o600);
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code === "EEXIST") continue;
      throw e;
    }
    const buf = Buffer.from(content);
    let written = -1;
    try {
      written = fs.writeSync(fd, buf);
    } finally {
      fs.closeSync(fd);
      if (written !== buf.length) {
        // short write (disk/tmpfs full) or an exception: never leave a truncated archive behind
        try {
          fs.unlinkSync(p);
        } catch (e) {
          if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
        }
      }
    }
    if (written !== buf.length) throw new Error(`short write to archive (${written} of ${buf.length} bytes): ${p}`);
    return p;
  }
  throw new Error("could not create a unique archive file");
}

export interface ArchivedObservation {
  handle: string;
  archivePath: string;
  /** masked (and per-line capped) content that was written */
  masked: string;
}

/**
 * Archives the MASKED output in a verified-safe directory (reusing an identical existing file)
 * and prunes old archives. Throws if the directory is unsafe or unwritable.
 */
export function archiveObservation(
  toolName: string,
  output: string,
  config: SolPiConfig = loadSolPiConfig(),
  /** result of redactSecrets(output) when the caller already computed it (avoids masking twice) */
  premasked?: string,
): ArchivedObservation {
  const c = config.observationPackConfig;
  const id = createHash("sha256").update(toolName).update("\0").update(output).digest("hex").slice(0, 12);
  const dir = resolveArchiveDir(config);
  ensureSafeDir(dir);
  const masked = premasked ?? redactSecrets(output);
  let archivePath = findExisting(dir, id, byteLen(masked));
  if (archivePath) {
    try {
      const now = new Date();
      fs.utimesSync(archivePath, now, now); // refresh recency
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
      archivePath = writeArchive(dir, id, masked); // pruned by another session in between
    }
  } else {
    archivePath = writeArchive(dir, id, masked);
  }
  pruneArchive(dir, archivePath, c.maxArchiveFiles, c.maxArchiveBytes);
  return { handle: `#obs_${id}`, archivePath, masked };
}

/** Throws if the archive directory is unsafe or unwritable (caller reports it). */
export function packObservation(toolName: string, output: string, turnIndex: number, config: SolPiConfig = loadSolPiConfig()): PackedObservation {
  const c = config.observationPackConfig;
  const bytes = byteLen(output);
  if (!c.enabled || bytes <= c.minBytesThreshold) return { packed: false, text: output, bytes, turnIndex };

  const a = archiveObservation(toolName, output, config);
  // Cap strictly below the raw size so packing can never inflate the context.
  const cap = Math.min(MAX_EXCERPT_BYTES, Math.floor(c.minBytesThreshold / 2));
  const lines = a.masked.split("\n"); // masked FIRST, cut afterwards
  const header = `[${a.handle}] ${toolName} output packed: ${bytes} bytes, ${lines.length} lines → ${a.archivePath}`;
  const body = excerptLines(lines, c.headLines, c.tailLines, cap - byteLen(header) - 1);
  const compactText = truncateBytes([header, ...body].join("\n"), cap);
  return { packed: true, text: output, handle: a.handle, archivePath: a.archivePath, bytes, turnIndex, compactText };
}

/** Full text for `fullReplayTurns` turns after creation, compact handle afterwards. */
export function selectObservationReplay(obs: PackedObservation, currentTurn: number, config: SolPiConfig = loadSolPiConfig()): string {
  if (!obs.packed || !obs.compactText) return obs.text;
  return currentTurn - obs.turnIndex < config.observationPackConfig.fullReplayTurns ? obs.text : obs.compactText;
}

// ---------------------------------------------------------------------------
// Evidence-Preserving Reducer
// ---------------------------------------------------------------------------
export interface ReducedEvidence {
  reduced: boolean;
  fallback: boolean;
  reason?: "quote-mismatch" | "no-failure-lines";
  /** undefined = the harness did not report an exit code (never rendered as 0) */
  exitCode: number | undefined;
  failedTests: string[];
  locations: string[];
  quotes: string[];
  text: string;
  /** set by reduceAndArchive */
  handle?: string;
  archivePath?: string;
}

/** Every quote must be a non-blank exact substring of rawLog. */
export function verifyQuotesInRawLog(quotes: string[], rawLog: string): boolean {
  return quotes.every((q) => q.trim().length > 0 && rawLog.includes(q));
}

const FAIL_LINE = /(^|\s)(--- FAIL|FAIL\b|FAILED|not ok\b|panic:|error(\[|:|\s)|Error:|✗|✘)|\bfailed\b/;
const ZERO_FAILED = /\b0\s+failed\b|\bfailed[:=]\s*0\b|\bfailures?[:=]\s*0\b/i;
const LOCATION = /([A-Za-z0-9_./-]{1,200}\.[A-Za-z0-9]{1,5}):(\d+)(?::\d+)?/g;
const FAILED_TEST = /--- FAIL:\s+(\S+)|^not ok \d+\s+(?:-\s+)?(.+)$|^FAILED\s+(\S+)/;

function isFailLine(line: string): boolean {
  return line.trim() !== "" && FAIL_LINE.test(line) && !ZERO_FAILED.test(line);
}

function* locationsOf(line: string): Generator<string> {
  for (const m of line.slice(0, MAX_SCAN_LINE_CHARS).matchAll(LOCATION)) yield `${m[1]}:${m[2]}`;
}

/** Tail of `raw` within maxBytes, starting on a character and line boundary. */
function tailWithin(raw: string, maxBytes: number): string {
  const buf = Buffer.from(raw);
  if (buf.length <= maxBytes) return raw;
  let start = buf.length - maxBytes;
  while (start < buf.length && (buf[start] & 0xc0) === 0x80) start++; // skip continuation bytes
  const s = buf.subarray(start).toString("utf-8");
  const nl = s.indexOf("\n");
  return nl >= 0 ? s.slice(nl + 1) : s; // drop the (possibly partial) first line
}

export function reduceEvidencePreserving(
  command: string,
  rawLog: string,
  exitCode: number | undefined,
  config: SolPiConfig = loadSolPiConfig(),
  candidate?: { quotes?: string[] },
  /** redactSecrets(rawLog) when the caller already computed it (the whole log is masked at most once) */
  maskedRaw?: string,
): ReducedEvidence {
  const c = config.evidencePreservingReducerConfig;
  const mask = (s: string) => (c.redactSecrets ? redactSecrets(s) : s);
  /** mask the whole line first, then cut */
  const outLine = (s: string) => truncateBytes(mask(s), MAX_LINE_BYTES);
  const rawBytes = byteLen(rawLog);
  const base = { fallback: false, failedTests: [] as string[], locations: [] as string[], quotes: [] as string[] };

  if (!c.enabled || rawBytes <= c.minBytesThreshold) {
    return { ...base, reduced: false, exitCode, text: mask(rawLog) };
  }

  const cap = Math.min(MAX_EXCERPT_BYTES, Math.floor(rawBytes / 2));
  // mask the WHOLE command first, then cut (cutting first would leave the head of a straddling secret)
  const header = `command: ${truncateBytes(mask(command), 256)}\nexit code: ${exitCode === undefined ? "unknown" : exitCode}`;
  const o = config.observationPackConfig;
  let maskedMemo: string | undefined = c.redactSecrets ? maskedRaw : rawLog;
  const excerpt = (): string => {
    maskedMemo ??= mask(rawLog);
    const body = excerptLines(maskedMemo.split("\n"), o.headLines, o.tailLines, cap - byteLen(header) - 1);
    return truncateBytes([header, ...body].join("\n"), cap);
  };
  const failClosed = (reason: "quote-mismatch" | "no-failure-lines", failedTests: string[], locations: string[]): ReducedEvidence => ({
    reduced: true,
    fallback: true,
    reason,
    exitCode,
    failedTests: failedTests.map(mask),
    locations: locations.map(mask),
    quotes: [],
    text: excerpt(),
  });

  const lines = tailWithin(rawLog, c.maxInputBytes).split("\n");
  const failedTests: string[] = [];
  const locations: string[] = [];
  const rawQuotes: string[] = []; // verbatim raw lines (verified against rawLog)
  const addLoc = (line: string) => {
    for (const loc of locationsOf(line)) if (!locations.includes(loc)) locations.push(loc);
  };
  const addQuote = (line: string) => {
    if (line.trim() !== "" && !rawQuotes.includes(line)) rawQuotes.push(line);
  };

  // Detection and verification use the RAW line; test names / locations are extracted from the
  // MASKED line, so a secret can never contribute (or be sliced into) a "location" or "test name".
  lines.forEach((line, i) => {
    if (isFailLine(line)) {
      addQuote(line);
      const ml = mask(line);
      const m = FAILED_TEST.exec(ml);
      const name = m && (m[1] || m[2] || m[3]);
      if (name && !failedTests.includes(name)) failedTests.push(name);
      addLoc(ml);
    } else if (i > 0 && isFailLine(lines[i - 1]) && /\.\w{1,5}:\d+/.test(line.slice(0, MAX_SCAN_LINE_CHARS))) {
      addQuote(line);
      addLoc(mask(line));
    }
  });
  let kept = rawQuotes.slice(0, 60);

  if (candidate?.quotes && candidate.quotes.length > 0) {
    if (!verifyQuotesInRawLog(candidate.quotes, rawLog)) {
      if (c.failClosedOnQuoteMismatch) return failClosed("quote-mismatch", failedTests, locations);
      // Tolerated by config: unverifiable candidate quotes are dropped, deterministic ones kept.
    } else {
      for (const q of candidate.quotes) if (!kept.includes(q)) kept.push(q);
    }
  }

  // Final gate on the RAW lines (before masking/cutting): every quote must be an exact raw substring.
  if (!verifyQuotesInRawLog(kept, rawLog)) {
    if (c.failClosedOnQuoteMismatch) return failClosed("quote-mismatch", failedTests, locations);
    kept = kept.filter((q) => verifyQuotesInRawLog([q], rawLog));
  }

  if (kept.length === 0) {
    // exit code unknown counts as "not verified successful"
    if (c.verifyExitCode && exitCode !== 0) return failClosed("no-failure-lines", failedTests, locations);
    return { ...base, reduced: true, exitCode, text: excerpt() };
  }

  const maskedTests = failedTests.map(mask);
  const maskedLocs = locations.map(mask);
  let outs = kept.map(outLine); // mask whole line, then cut
  const bodyOf = (qs: string[]) =>
    [
      header,
      maskedTests.length ? `failed tests: ${maskedTests.join(", ")}` : "",
      maskedLocs.length ? `locations: ${maskedLocs.join(", ")}` : "",
      "evidence (verbatim, secrets masked):",
      ...qs,
    ]
      .filter(Boolean)
      .join("\n");
  // Enforce the byte cap by dropping trailing quotes (never by cutting one mid-line).
  while (outs.length > 1 && byteLen(bodyOf(outs)) > cap) outs = outs.slice(0, -1);
  return {
    reduced: true,
    fallback: false,
    exitCode,
    failedTests: maskedTests,
    locations: maskedLocs,
    quotes: outs,
    text: truncateBytes(bodyOf(outs), cap),
  };
}

/**
 * Reducer + archive: when the log is replaced, the MASKED raw log is archived first and the
 * handle/path are appended, so the full evidence stays retrievable. Throws if archiving
 * fails (callers must then leave the original output untouched).
 */
export function reduceAndArchive(
  command: string,
  rawLog: string,
  exitCode: number | undefined,
  config: SolPiConfig = loadSolPiConfig(),
  candidate?: { quotes?: string[] },
): ReducedEvidence {
  const masked = redactSecrets(rawLog); // computed once; shared by the excerpt and the archive
  const r = reduceEvidencePreserving(command, rawLog, exitCode, config, candidate, masked);
  if (!r.reduced) return r;
  const a = archiveObservation("bash", rawLog, config, masked);
  return { ...r, handle: a.handle, archivePath: a.archivePath, text: `${r.text}\n[raw log archived: ${a.handle} → ${a.archivePath}]` };
}

// ---------------------------------------------------------------------------
// Online compaction / Pricing Cliff (recommendation only)
// ---------------------------------------------------------------------------
export interface CompactionAdvice {
  level: "ok" | "warn" | "exceeded";
  cliff: number;
  inputTokens: number;
  shouldCompact: boolean;
  autoApply: false;
  message: string;
}

// Pricing Cliff source of truth: agent/models/catalog.json `models.*.compaction_threshold`.
// sol-pi.json keeps only the default fallback (tokenPressureThreshold), warnRatio and the respectPricingCliffs switch.
let cliffCatalog: ModelCatalogData | null | undefined; // undefined = not loaded yet
/** Test hook: pin the catalog used for Pricing Cliffs (null = none, undefined = reload lazily from disk). */
export function setPricingCliffCatalog(c: ModelCatalogData | null | undefined): void {
  cliffCatalog = c;
}

export function pricingCliffFor(modelId: string, config: SolPiConfig = loadSolPiConfig()): number {
  const c = config.onlineContextCompactConfig;
  if (c.respectPricingCliffs) {
    if (cliffCatalog === undefined) cliffCatalog = loadModelCatalog(import.meta.dir);
    const t = lookupCompactionThreshold(cliffCatalog, modelId);
    if (t !== undefined) return t;
  }
  return c.tokenPressureThreshold;
}

export function evaluateOnlineCompaction(
  inputTokens: number,
  modelId: string,
  cacheWriteReadRatio?: number,
  config: SolPiConfig = loadSolPiConfig(),
): CompactionAdvice {
  const ratio = cacheWriteReadRatio ?? config.cacheWriteReadRatio;
  const cliff = pricingCliffFor(modelId, config);
  const warnAt = cliff * config.onlineContextCompactConfig.warnRatio;
  const base = { cliff, inputTokens, autoApply: false as const };
  if (inputTokens >= cliff) {
    return {
      ...base,
      level: "exceeded",
      shouldCompact: true,
      message: `Pricing Cliff reached for ${modelId}: ${inputTokens} >= ${cliff} tokens. Cache write costs ${ratio}x a cache read; recommend compacting (/compact) at the next subtask boundary.`,
    };
  }
  if (inputTokens >= warnAt) {
    return {
      ...base,
      level: "warn",
      shouldCompact: false,
      message: `Approaching Pricing Cliff for ${modelId}: ${inputTokens}/${cliff} tokens (cache write ${ratio}x read). Plan a compaction before crossing.`,
    };
  }
  return { ...base, level: "ok", shouldCompact: false, message: `Context ${inputTokens}/${cliff} tokens for ${modelId}.` };
}
