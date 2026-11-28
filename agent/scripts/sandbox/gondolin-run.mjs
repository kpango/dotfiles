#!/usr/bin/env node
// gondolin-run.mjs -- run a command in the strongest available isolation backend.
//
//   gondolin   : @earendil-works/gondolin Micro-VM (QEMU) with placeholder-secret isolation.
//                Usable when the package imports AND a qemu-system-* binary is in PATH.
//   pa-sandbox : bwrap --clearenv wrapper (agent/scripts/sandbox/pa-sandbox).
//
// usage: gondolin-run.mjs [--check | --dry-run] [--backend auto|gondolin|pa-sandbox]
//                         [--allow-host HOST]... [--secret NAME@host1,host2]... [--] <command> [args...]
//   --check        print backend detection and the backend that would be chosen (exit 1 if none)
//   --dry-run      print the chosen backend and command; run nothing
//   --backend      auto (default) picks gondolin when usable, else pa-sandbox. An explicit
//                  backend never falls back: gondolin failing is an error, not a silent downgrade.
//   --allow-host   egress allowlist for the VM (default: none = deny all)
//   --secret       NAME@hosts: value is read from host env NAME; the guest only sees a placeholder
//                  --allow-host/--secret require the gondolin backend: with pa-sandbox (no egress or
//                  secret isolation) they are a hard error (exit 2), never silently ignored.
//
// Args are passed as arrays (never joined into a shell string). The pa-sandbox path forwards only
// allowlisted env vars (extend with GONDOLIN_RUN_ENV_ALLOW=A,B); the gondolin path forwards none.
// Test hooks: GONDOLIN_RUN_PA_SANDBOX (pa-sandbox path), GONDOLIN_RUN_MODULE (gondolin specifier).
import { spawnSync } from "node:child_process";
import { accessSync, constants, readdirSync } from "node:fs";
import { delimiter, dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ENV_ALLOW = ["PATH", "HOME", "USER", "LANG", "LC_ALL", "TERM", "TZ"];
const USAGE = "usage: gondolin-run.mjs [--check | --dry-run] [--backend auto|gondolin|pa-sandbox] [--allow-host HOST]... [--secret NAME@hosts]... [--] <command> [args...]";

// Host secret values; every message we print passes through scrub() so a third-party error
// text that echoes a secret cannot leak it.
const secretValues = [];
// Replaces each value and its JSON-escaped form (what JSON.stringify would print), longest first.
function scrub(text) {
  let t = String(text);
  const forms = new Set();
  for (const v of secretValues) {
    if (!v) continue;
    forms.add(v);
    forms.add(JSON.stringify(v).slice(1, -1));
  }
  for (const f of [...forms].sort((a, b) => b.length - a.length)) t = t.split(f).join("***");
  return t;
}
// All --check/--dry-run output goes through here so nothing printed can carry a secret value.
// Callers scrub individual values BEFORE JSON.stringify as well; this is the backstop.
function emit(lines, code = 0) {
  for (const l of lines) console.log(scrub(l));
  process.exit(code);
}
function die(msg, code = 2) {
  console.error(`gondolin-run: ${scrub(msg)}`);
  process.exit(code);
}

function isExecutable(p) {
  try {
    accessSync(p, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

const pathDirs = () => (process.env.PATH ?? "").split(delimiter).filter(Boolean);

function findPaSandbox() {
  const override = process.env.GONDOLIN_RUN_PA_SANDBOX;
  if (override) return isExecutable(override) ? override : null;
  const here = join(dirname(fileURLToPath(import.meta.url)), "pa-sandbox");
  if (isExecutable(here)) return here;
  return pathDirs().map((d) => join(d, "pa-sandbox")).find(isExecutable) ?? null;
}

function findQemu() {
  for (const d of pathDirs()) {
    let names = [];
    try {
      names = readdirSync(d);
    } catch {
      continue;
    }
    const n = names.find((x) => x.startsWith("qemu-system-") && isExecutable(join(d, x)));
    if (n) return n;
  }
  return null;
}

// Returns { mod, qemu, state: "available" | "detected" | "not installed", reason }.
async function detectGondolin() {
  const spec = process.env.GONDOLIN_RUN_MODULE ?? "@earendil-works/gondolin";
  let mod;
  try {
    mod = await import(spec.startsWith("/") ? pathToFileURL(spec).href : spec);
  } catch {
    return { state: "not installed", reason: "package not importable" };
  }
  if (typeof mod.VM?.create !== "function" || typeof mod.createHttpHooks !== "function") {
    return { state: "detected", reason: "package lacks VM.create/createHttpHooks" };
  }
  const qemu = findQemu();
  if (!qemu) return { state: "detected", reason: "qemu-system-* not in PATH" };
  return { mod, qemu, state: "available", reason: `module + ${qemu}` };
}

// GONDOLIN_RUN_ENV_ALLOW may add ordinary variables, but never ones that steer pa-sandbox's own
// guards (PA_SANDBOX_*) or this wrapper (GONDOLIN_RUN_*): forwarding those would weaken isolation.
const extraEnv = (process.env.GONDOLIN_RUN_ENV_ALLOW ?? "").split(",").map((k) => k.trim()).filter(Boolean);
if (extraEnv.some((k) => /^(PA_SANDBOX_|GONDOLIN_RUN_)/.test(k))) {
  die("GONDOLIN_RUN_ENV_ALLOW may not name PA_SANDBOX_* or GONDOLIN_RUN_* variables");
}

function buildEnv() {
  const env = {};
  for (const k of [...ENV_ALLOW, ...extraEnv]) {
    if (process.env[k] !== undefined) env[k] = process.env[k];
  }
  return env;
}

// ---- args ----
const argv = process.argv.slice(2);
let mode = "run";
let backendOpt = "auto";
const allowHosts = [];
const secretSpecs = [];
const value = (opt) => {
  if (argv.length === 0 || argv[0].startsWith("--")) die(`${opt} needs a value`);
  return argv.shift();
};
while (argv.length > 0 && argv[0].startsWith("-") && argv[0] !== "--") {
  const a = argv.shift();
  if (a === "--check") mode = "check";
  else if (a === "--dry-run") mode = "dry-run";
  else if (a === "--backend") backendOpt = value(a);
  else if (a === "--allow-host") {
    const h = value(a).trim();
    if (h === "") die("--allow-host needs a non-empty host");
    if (!hostAllowed(h)) die(`--allow-host #${allowHosts.length + 1}: host not allowed (ASCII host name only: letters, digits, dot, hyphen, optional :port; a wildcard must be a leading label followed by at least two labels)`);
    allowHosts.push(h);
  }
  else if (a === "--secret") secretSpecs.push(value(a));
  else die("unknown option (argument text not echoed: it may hold a secret)");
}
if (argv[0] === "--") argv.shift();
if (!["auto", "gondolin", "pa-sandbox"].includes(backendOpt)) die("unknown --backend value (want auto|gondolin|pa-sandbox)");

// Names that would collide with Object.prototype members (e.g. __proto__, toString) are refused.
const RESERVED = new Set([...Object.getOwnPropertyNames(Object.prototype), "prototype"]);
const MIN_SECRET_LEN = 4;
// Hosts (egress allowlist and secret hosts alike): ASCII labels [A-Za-z0-9-] separated by dots, an
// optional leading wildcard label, an optional :port (wildcard + port is allowed; the port only
// narrows the match). A wildcard needs at least two further labels, so a bare wildcard or a whole TLD
// never matches. Anything else (non-ASCII such as a fullwidth asterisk, IDN, spaces, %, /) is refused,
// so no later URL/IDNA normalisation can turn an accepted string into a broader pattern.
function hostAllowed(h) {
  const m = /^(\*\.)?([A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*)(?::([0-9]{1,5}))?$/.exec(h);
  if (!m) return false;
  if (m[3] !== undefined && Number(m[3]) > 65535) return false;
  return !m[1] || m[2].includes(".");
}
const secrets = {};
// Error text below names the --secret by position only: the argument may be a mistyped value.
secretSpecs.forEach((spec, idx) => {
  const n = idx + 1;
  const m = /^([A-Za-z_][A-Za-z0-9_]*)@(.+)$/.exec(spec);
  if (!m) die(`bad --secret #${n} (format is NAME@host1,host2)`);
  if (RESERVED.has(m[1])) die(`--secret #${n}: reserved name`);
  if (Object.hasOwn(secrets, m[1])) die(`--secret #${n}: name given twice`);
  const hosts = m[2].split(",").map((h) => h.trim()).filter(Boolean);
  if (hosts.length === 0) die(`--secret #${n} needs at least one host`);
  // A real secret may only go to named hosts: wildcard only as a leading "*." with at least two
  // further labels (so "*.com" is refused; "*.example.com" is fine).
  for (const h of hosts) {
    if (!hostAllowed(h)) die(`--secret #${n}: host not allowed (ASCII host name only: letters, digits, dot, hyphen, optional :port; a wildcard must be a leading label followed by at least two labels)`);
  }
  secrets[m[1]] = { hosts, n };
});

// Same check for --check, --dry-run and a real run: every secret must be present in the host env.
function buildHookSecrets() {
  const out = {};
  for (const [name, sec] of Object.entries(secrets)) {
    const v = process.env[name];
    if (v === undefined || v === "") die(`--secret #${sec.n}: host env var is not set`);
    if (v.length < MIN_SECRET_LEN) die(`--secret #${sec.n}: value shorter than ${MIN_SECRET_LEN} chars is refused (not a credible secret; cannot be scrubbed reliably)`);
    out[name] = { hosts: sec.hosts, value: v };
    secretValues.push(v);
  }
  secretValues.sort((a, b) => b.length - a.length); // scrub longest first
  return out;
}

function failClosedPaSandbox() {
  if (allowHosts.length > 0 || secretSpecs.length > 0) {
    die("pa-sandbox provides neither egress restriction nor secret isolation, so --allow-host/--secret cannot be honored; the gondolin backend is required (refusing to run with weaker isolation than requested)");
  }
}

// ---- backend selection ----
const gon = await detectGondolin();
const pa = findPaSandbox();
let backend = null;
if (backendOpt === "gondolin") backend = gon.state === "available" ? "gondolin" : null;
else if (backendOpt === "pa-sandbox") backend = pa ? "pa-sandbox" : null;
else backend = gon.state === "available" ? "gondolin" : pa ? "pa-sandbox" : null;

if (mode === "check") {
  const note = (v) => (process.env[v] ? " [overridden (test hook)]" : "");
  const lines = [
    `gondolin: ${gon.state === "available" ? "available" : gon.state === "detected" ? "detected but unavailable" : "not installed"} (${gon.reason})${note("GONDOLIN_RUN_MODULE")}`,
    `pa-sandbox: ${pa ? `available (${pa})` : "unavailable"}${note("GONDOLIN_RUN_PA_SANDBOX")}`,
  ];
  // Same fail-closed checks as a real run, BEFORE anything is printed (output then goes through emit()).
  if (backend === "pa-sandbox") failClosedPaSandbox();
  if (backend === "gondolin") buildHookSecrets();
  if (!backend) emit([...lines, `backend: none (--backend ${backendOpt})`], 1);
  emit([...lines, `backend: ${backend}`]);
}

if (argv.length === 0) die(USAGE);
if (!backend) {
  die(`backend '${backendOpt}' unavailable (gondolin: ${gon.state}, ${gon.reason}; pa-sandbox: ${pa ? "ok" : "not found"})`, 1);
}

if (backend === "pa-sandbox") {
  failClosedPaSandbox();
  const cmd = [pa, "--", ...argv];
  if (mode === "dry-run") emit(["backend: pa-sandbox", `command: ${JSON.stringify(cmd.map(scrub))}`]);
  const r = spawnSync(cmd[0], cmd.slice(1), { env: buildEnv(), stdio: "inherit" });
  if (r.error) die(`spawn failed: ${r.error.message}`, 1);
  process.exit(r.status ?? 128);
}

// ---- gondolin ----
const guestArgv = ["/bin/sh", "-c", 'exec -- "$@"', "sh", ...argv];
const hookSecrets = buildHookSecrets();
if (mode === "dry-run") {
  emit([
    "backend: gondolin",
    `allowed hosts: ${JSON.stringify(allowHosts.map(scrub))}`,
    `secrets (placeholders only): ${JSON.stringify(Object.fromEntries(Object.entries(secrets).map(([k, v]) => [k, v.hosts.map(scrub)])))}`,
    `command: ${JSON.stringify(guestArgv.map(scrub))}`,
  ]);
}

const { VM, createHttpHooks } = gon.mod;
let vm;
try {
  const { httpHooks, env } = createHttpHooks({ allowedHosts: allowHosts, secrets: hookSecrets });
  vm = await VM.create({ httpHooks, env });
} catch (e) {
  die(`gondolin VM.create failed: ${e?.message ?? e}; not falling back silently - rerun with --backend pa-sandbox to use bwrap isolation`, 1);
}
let code = 1;
try {
  const r = await vm.exec(guestArgv);
  if (r.stdout) process.stdout.write(scrub(r.stdout));
  if (r.stderr) process.stderr.write(scrub(r.stderr));
  if (r.exitCode === undefined || r.exitCode === null) code = 128;
  else if (Number.isInteger(r.exitCode) && r.exitCode >= 0 && r.exitCode <= 255) code = r.exitCode;
  else {
    console.error("gondolin-run: unexpected exit code from guest");
    code = 1;
  }
} catch (e) {
  console.error(`gondolin-run: ${scrub(`exec failed: ${e?.message ?? e}`)}`);
} finally {
  try {
    await vm.close();
  } catch (e) {
    console.error(`gondolin-run: warning: vm.close failed: ${scrub(e?.message ?? e)}`);
  }
}
process.exit(code);
