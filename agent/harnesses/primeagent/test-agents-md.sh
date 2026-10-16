#!/usr/bin/env bash
# Tests for the generated agent/harnesses/primeagent/AGENTS.md (gen-agents-md.sh):
#   drift (byte-equal to a fresh generation) + negative control, line/byte limits + negative controls,
#   negative controls for enforcement/wiring claims, unauthenticated providers (CONTEXT P-6) and an
#   unusable decide.py, no known misleading phrase in the output, guard table rows == decide.py now,
#   guard words (GUARD_WORDS) outside the guard table only in ALLOWED_SENTENCES, async
#   rlm/swarm_adapter/bundled-skill calls awaited, model= selectors authenticated (each + negative
#   controls), tier table == model-routing.json, referenced paths
#   exist in the repo (~/.prime/agent/* through the expected install mapping; the live install.mk
#   wiring is T10's and is not checked), unknown path-like tokens fail, no SYSTEM.md, and
#   `prime-agent prompt --json` (offline: it only assembles the system prompt, run without network)
#   loads the file from a sandbox HOME. Never touches the real ~/.prime/agent.
# exit: 0 = all pass, 1 = at least one [FAIL]. [SKIP] = prerequisite missing (not a failure).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../../.." && pwd)"
gen="$here/gen-agents-md.sh"
out="$here/AGENTS.md"
sandbox="$(mktemp -d)"
trap 'command rm -r -- "$sandbox"' EXIT

fails=0
ok() { echo "[OK] $1"; }
ng() { echo "[FAIL] $1"; fails=$((fails + 1)); }

# --- drift ---
if "$gen" --check >/dev/null; then ok "AGENTS.md is byte-equal to a fresh generation"; else ng "AGENTS.md drifted: run $gen"; fi

# --- limits (the constants live only in gen-agents-md.sh) ---
max_lines="$(sed -n 's/^readonly MAX_LINES=\([0-9][0-9]*\)$/\1/p' "$gen")"
max_bytes="$(sed -n 's/^readonly MAX_BYTES=\([0-9][0-9]*\)$/\1/p' "$gen")"
lines="$(wc -l <"$out")"
bytes="$(wc -c <"$out")"
if [[ -n "$max_lines" && -n "$max_bytes" && "$lines" -le "$max_lines" && "$bytes" -le "$max_bytes" ]]; then
    ok "size $lines lines / $bytes bytes within $max_lines / $max_bytes"
else
    ng "size $lines lines / $bytes bytes vs limits '$max_lines' / '$max_bytes'"
fi

# --- negative controls on a copy of the inputs ---
copy="$sandbox/repo"
mkdir -p "$copy/agent/scripts/hooks" "$copy/agent/harnesses/primeagent"
command cp -- "$root/agent/AGENTS.md" "$root/agent/security-rules.json" "$copy/agent/"
command cp -- "$root/agent/scripts/hooks/decide.py" "$root/agent/scripts/hooks/rule_engine.py" "$copy/agent/scripts/hooks/"
command cp -- "$root/agent/scripts/harness-check-lib.sh" "$copy/agent/scripts/"
command cp -r -- "$root/agent/agents" "$copy/agent/"
command cp -- "$gen" "$here/AGENTS-supplement.md" "$here/model-routing.json" "$out" "$copy/agent/harnesses/primeagent/"
cgen="$copy/agent/harnesses/primeagent/gen-agents-md.sh"
csupp="$copy/agent/harnesses/primeagent/AGENTS-supplement.md"
crouting="$copy/agent/harnesses/primeagent/model-routing.json"
ccore="$copy/agent/AGENTS.md"
restore() { command cp -- "$here/AGENTS-supplement.md" "$csupp"; command cp -- "$here/model-routing.json" "$crouting"; command cp -- "$root/agent/AGENTS.md" "$ccore"; }
if "$cgen" --check >/dev/null; then ok "copy is in sync before mutation"; else ng "copy not in sync before mutation"; fi
echo "tampered" >>"$copy/agent/harnesses/primeagent/AGENTS.md"
if "$cgen" --check >/dev/null 2>&1; then ng "--check accepted a tampered AGENTS.md"; else ok "--check rejects a tampered AGENTS.md"; fi
# expect_gen_fail <description> <stderr substring>: generation on the mutated copy must fail for that reason.
expect_gen_fail() {
    local msg
    if msg="$("$cgen" 2>&1)"; then ng "generation accepted $1"
    elif grep -qF -- "$2" <<<"$msg"; then ok "generation rejects $1"
    else ng "generation for $1 failed for another reason: $msg"; fi
    restore
}
seq 1 "$max_lines" >>"$csupp"
expect_gen_fail "output over the line limit" "limit $max_lines"
# one long line: stays far below the line limit, exceeds only the byte limit
head -c "$((max_bytes + 1))" /dev/zero | tr '\0' 'x' >>"$csupp"
echo >>"$csupp"
expect_gen_fail "output over the byte limit (line count within limit)" "limit $max_bytes"
printf "\n## Injected\n\n- Writes to ~/.ssh/ are blocked\n" >>"$ccore"
expect_gen_fail "an enforcement claim in the neutral part" "enforcement/wiring claim"
printf '\n## Injected\n\n- A root session shares this configuration via symlink\n' >>"$ccore"
expect_gen_fail "a symlink wiring claim in the neutral part" "enforcement/wiring claim"
jq '.tiers.Low.fallbacks += [{"provider": "anthropic", "model": "anthropic/claude-x", "trigger": "x"}]' "$here/model-routing.json" >"$crouting"
expect_gen_fail "an unauthenticated fallback provider" "not authenticated"
jq '.tiers.Medium.model = "openrouter/some-model"' "$here/model-routing.json" >"$crouting"
expect_gen_fail "a selector whose prefix is an unauthenticated provider" "not authenticated"
command mv -- "$copy/agent/scripts/hooks/decide.py" "$sandbox/decide.py.bak"
expect_gen_fail "a missing decide.py" "could not decide the GUARD_EXAMPLES"
command mv -- "$sandbox/decide.py.bak" "$copy/agent/scripts/hooks/decide.py"
echo '{}' >"$copy/agent/security-rules.json"
expect_gen_fail "decide.py in fail-open (empty rules file)" "could not decide the GUARD_EXAMPLES"
command cp -- "$root/agent/security-rules.json" "$copy/agent/"

# --- no enforcement/wiring claim that is false on prime-agent (independent of gen's regex) ---
# Known misleading phrases from agent/AGENTS.md's Security / Specialized sections (Checker T4 a1).
bad=""
for phrase in "are blocked" "blocked outright" "via symlink" "tool-specific supplement" "full, current list"; do
    if hit="$(grep -niF -- "$phrase" "$out")"; then bad+="$hit"$'\n'; fi
done
if [[ -z "$bad" ]]; then ok "no known misleading enforcement/wiring phrase in AGENTS.md"; else ng "misleading phrase(s) in AGENTS.md: $bad"; fi
if grep -qx '## Security' "$out" && grep -qF 'prime-agent has no write-time check' "$out"; then
    ok "prime-specific Security section present"
else ng "prime-specific Security section missing"; fi

# --- guard table, guard words outside it, awaited async calls, prose selectors ---
# Guard table: every row "| `<command>` | block|ask|allow |" must equal what
# agent/scripts/hooks/decide.py returns now with prime-shell-guard.sh's request (family
# security_shell, harness primeagent), and the table must have at least one row.
# Guard words: outside those table rows, any line of AGENTS.md (prose, headings, other tables,
# code, comments) that contains a word from GUARD_WORDS (whole-word, case-insensitive match; no
# polarity or negation analysis, so "does not allow" fails too) must be part of a sentence listed
# verbatim in ALLOWED_SENTENCES. An ALLOWED_SENTENCES entry that matches no sentence FAILs. File
# names (FILE_NAME_RE, e.g. prime-shell-guard.sh) are removed before the match.
# Async calls: public `async def`s are enumerated by ast (read only) from swarm_adapter, the
# installed prime-agent runtime's rlm/__init__.py and its bundled skills (~/.local/share/prime-agent/
# skills/*/src/<module>/: edit, websearch, ...; a module with `run` is also callable as
# `<module>(`). Each call form must be preceded by `await ` (or `async ` in a signature).
# Selectors: a `model=`/`model:` value with a "/" anywhere (prose or code, backticks or not) must be
# an authenticated, routed selector.
read -r -d '' prose_py <<'PY' || true
import ast, glob, json, os, pwd, re, subprocess, sys

path, root, routing_path, allowed_csv, cwd = sys.argv[1:6]
text = open(path, encoding="utf-8").read()
routing = json.load(open(routing_path, encoding="utf-8"))
allowed = allowed_csv.split(",")
errors = []

# The only list of words that state what a guard does. Whole-word match, any polarity.
GUARD_WORDS = (r"refus\w*|block\w*|den(?:y|ies|ied|ying)|reject\w*|prevent\w*|forbid\w*|forbade"
               r"|prohibit\w*|halt\w*|stop(?:s|ped|ping)?|guard(?:s|ed|ing)?|protect\w*"
               r"|ask(?:s|ed|ing)? the human|confirm\w*|approv\w*|allow\w*|disallow\w*|permit\w*"
               r"|enforc\w*|intercept\w*")
GUARD_WORDS_RE = re.compile(rf"(?i)\b(?:{GUARD_WORDS})\b")
FILE_NAME_RE = re.compile(r"[\w./~-]+\.(?:sh|py|json|md)\b")
# The only sentences that may contain a guard word, verbatim, each with the reason.
_INSTR = "instruction to the agent, not a statement of what the guard does"
ALLOWED_SENTENCES = {
    "run tests/build to confirm correctness — don't assume it works":
        "agent/AGENTS.md: confirm = verify the agent's own work",
    "if it returns `block` or `ask`, do not run the command and ask the human.":
        _INSTR + "; `block`/`ask` are decide_shell results",
    "ask the human.": _INSTR + " (no pa-sandbox)",
    "if a task needs one, ask the human.": _INSTR + " (credential paths)",
    "Destructive commands (recursive `rm`/`chmod`, force-push, piping a download into a shell, mass `git add`, production-namespace `kubectl`/`helm` deletes) need the human's confirmation whatever decide.py returns for them.":
        _INSTR,
    "`agent/scripts/prime-shell-guard.sh` refuses a `bash()` command when decide.py returns `block` or `ask` for it.":
        "table preamble: prime-shell-guard.sh exits 126 on block and on ask",
    "decide.py returns `block` or `ask` only for a command that matches a pattern in `agent/security-rules.json`, and `allow` for every other command.":
        "table preamble: decide.py handle_security_shell (harness primeagent skips the Laya stage)",
}
ROW_RE = re.compile(r"^\| `([^`]+)` \| (block|ask|allow) \|$")


def decide(cmd):
    req = {"family": "security_shell", "command": cmd, "cwd": cwd,
           "rules_file": os.path.join(root, "agent/security-rules.json"),
           "resolve_command_target": False, "harness": "primeagent"}
    r = subprocess.run([sys.executable, "-I", "-B", os.path.join(root, "agent/scripts/hooks/decide.py")],
                       input=json.dumps(req), capture_output=True, text=True, timeout=10, check=True)
    d = json.loads(r.stdout)
    if "fail-open" in (d.get("reason") or ""):
        return "fail-open"
    return d.get("decision")


# guard table
n_rows = 0
for line in text.split("\n"):
    m = ROW_RE.match(line)
    if m:
        n_rows += 1
        cmd = m.group(1).replace("\\|", "|")
        got = decide(cmd)
        if got != m.group(2):
            errors.append(f"guard table says {m.group(2)} but decide.py says {got} for `{cmd}`")
if n_rows == 0:
    errors.append("no guard table row in AGENTS.md")

# guard words: units are paragraphs / list items; any other line is its own unit
units, cur = [], []
for line in text.split("\n"):
    item = re.match(r"\s*(?:- |\d+\. )", line)
    plain = line.strip() and not line.startswith(("#", "|", "<!--", "```")) and not item
    if (not plain or item) and cur:
        units.append(" ".join(cur))
        cur = []
    if ROW_RE.match(line) or not line.strip():
        continue
    if plain or item:
        cur.append(re.sub(r"^\s*(?:- |\d+\. )", "", line).strip())
    else:
        units.append(line)
if cur:
    units.append(" ".join(cur))
used, n_hits = set(), 0
for unit in units:
    codes = []
    masked = re.sub(r"`[^`]*`", lambda m: codes.append(m.group(0)) or f"\0{len(codes) - 1}\0", unit)
    for sent in re.split(r"(?<=[.;:])\s+", masked):
        sent = re.sub(r"\0(\d+)\0", lambda m: codes[int(m.group(1))], sent).replace("*", "")
        hit = GUARD_WORDS_RE.search(FILE_NAME_RE.sub(" ", sent))
        if not hit:
            continue
        n_hits += 1
        if sent in ALLOWED_SENTENCES:
            used.add(sent)
        else:
            errors.append(f"guard word '{hit.group(0)}' outside the guard table "
                          f"(rephrase, or add the sentence to ALLOWED_SENTENCES with a reason): {sent}")
for k in ALLOWED_SENTENCES.keys() - used:
    errors.append(f"stale ALLOWED_SENTENCES entry (matches no sentence verbatim): {k}")

# awaited async calls
home = pwd.getpwuid(os.getuid()).pw_dir
adapter = os.path.join(root, "agent/harnesses/primeagent/skills/swarm-adapter/src/swarm_adapter/__init__.py")
rlm_src = os.path.join(home, ".local/share/prime-agent/prime-agent-runtime/src/rlm/__init__.py")
skills_dir = os.path.join(home, ".local/share/prime-agent/skills")


def async_names(*paths):
    names = set()
    for p in paths:
        t = ast.parse(open(p, encoding="utf-8").read())
        names |= {n.name for n in ast.walk(t) if isinstance(n, ast.AsyncFunctionDef) and not n.name.startswith("_")}
    return names


apis = {"swarm_adapter": async_names(adapter)}
notes = []
if os.path.isfile(rlm_src):
    apis["rlm"] = async_names(rlm_src)
    notes.append("rlm from runtime")
else:
    apis["rlm"] = {"spawn"}  # rlm/__init__.py:170 `async def spawn`; runtime not installed here
    notes.append("rlm runtime not found, spawn only")
callable_mods = set()
skill_srcs = sorted(glob.glob(os.path.join(skills_dir, "*", "src", "*", "*.py")))
for pkg_dir in sorted({os.path.dirname(p) for p in skill_srcs}):
    names = async_names(*glob.glob(os.path.join(pkg_dir, "*.py")))
    if names:
        apis[os.path.basename(pkg_dir)] = names
        if "run" in names:
            callable_mods.add(os.path.basename(pkg_dir))  # the kernel makes `await <module>(...)` call run
if skill_srcs:
    notes.append(f"{len(apis) - 2} bundled skill modules")
else:
    apis.update({"edit": {"run"}, "websearch": {"run"}})  # skills/{edit,websearch}: `async def run`
    callable_mods.update({"edit", "websearch"})
    notes.append("bundled skills not found, edit/websearch run only")
if "spawn" not in apis["rlm"] or "decide_shell" not in apis["swarm_adapter"] or "run" not in apis.get("edit", ()):
    errors.append(f"async API enumeration looks wrong: {apis}")
n_calls = 0
calls = [(rf"(?<![\w.]){re.escape(mod)}\.({'|'.join(sorted(names))})\(", mod) for mod, names in apis.items()]
calls += [(rf"(?<![\w.])({re.escape(mod)})\(", mod) for mod in sorted(callable_mods)]
for rx, mod in calls:
    for m in re.finditer(rx, text):
        n_calls += 1
        if text[max(0, m.start() - 6):m.start()] not in ("await ", "async "):
            ln = text.count("\n", 0, m.start()) + 1
            errors.append(f"line {ln}: {m.group(0)}...) is a coroutine but is not awaited")

# selectors given as model=/model: values, with or without backticks
selectors = {v["model"] for v in routing["tiers"].values()} | {
    f["model"] for v in routing["tiers"].values() for f in v.get("fallbacks", [])}
n_sel = 0
for m in re.finditer(r"\bmodel\s*[=:]\s*[\"'`]?([^\s\"'`,)]+)", text):
    val = m.group(1).rstrip(".;")
    if "/" not in val or val.startswith("<"):
        continue
    n_sel += 1
    if val.split("/")[0] not in allowed:
        errors.append(f"selector {val} uses a provider not authenticated for prime-agent ({','.join(allowed)})")
    elif val not in selectors:
        errors.append(f"selector {val} is not in model-routing.json")

if errors:
    sys.exit("\n".join(errors))
print(f"{n_rows} guard table rows match decide.py; {n_hits} sentences with guard words, all allowed; "
      f"{n_calls} async calls awaited ({', '.join(notes)}); {n_sel} model= selectors")
PY
allowed_providers="$(sed -n 's/^readonly ALLOWED_PROVIDERS=(\(.*\)).*$/\1/p' "$gen" | tr -d '"' | tr ' ' ',')"
check_prose() { python3 -I -B -c "$prose_py" "$1" "$root" "$here/model-routing.json" "$allowed_providers" "$sandbox"; }
if [[ -z "$allowed_providers" ]]; then ng "ALLOWED_PROVIDERS not found in $gen"
elif msg="$(check_prose "$out" 2>&1)"; then ok "guard table/guard words/await/selectors: $msg"
else ng "guard table/guard words/await/selectors: $msg"; fi
# negative controls: each mutation of a copy of AGENTS.md must fail for the stated reason
mut="$sandbox/prose.md"
expect_prose_fail() { # <description> <stderr substring>
    local msg
    if msg="$(check_prose "$mut" 2>&1)"; then ng "prose check accepted $1"
    elif grep -qF -- "$2" <<<"$msg"; then ok "prose check rejects $1"
    else ng "prose check for $1 failed for another reason: $msg"; fi
}
sed 's/= await rlm\.spawn(/= rlm.spawn(/' "$out" >"$mut"
expect_prose_fail "rlm.spawn without await" "is not awaited"
# shellcheck disable=SC2016 # literal markdown backticks
sed 's/`await swarm_adapter\.decide_shell(/`swarm_adapter.decide_shell(/' "$out" >"$mut"
expect_prose_fail "swarm_adapter.decide_shell without await" "is not awaited"
# shellcheck disable=SC2016 # literal markdown backticks
sed 's/`await edit\.run(/`edit.run(/' "$out" >"$mut"
expect_prose_fail "edit.run without await" "is not awaited"
# shellcheck disable=SC2016 # literal markdown backticks
{ cat "$out"; printf '\n- Or call the module: `edit(path=p, old_str=a, new_str=b)`.\n'; } >"$mut"
expect_prose_fail "a skill module call without await" "is not awaited"
{ cat "$out"; printf '\nFor drafts spawn with model=openrouter/foo instead.\n'; } >"$mut"
expect_prose_fail "an unauthenticated selector in prose without backticks" "not authenticated"
sed '0,/ | allow |$/s// | block |/' "$out" >"$mut"
expect_prose_fail "a guard table row edited from allow to block" "but decide.py says allow"
sed '0,/ | block |$/s// | allow |/' "$out" >"$mut"
expect_prose_fail "a guard table row edited from block to allow" "but decide.py says block"
grep -v '^| `' "$out" >"$mut"
expect_prose_fail "a missing guard table" "no guard table row"
perl -0pe 's/if a task\s+needs one, ask the human\./if a task needs one, ask the human first./' "$out" >"$mut"
expect_prose_fail "an edited allowed sentence" "stale ALLOWED_SENTENCES entry"
# One appended line each: guard words outside the table fail whatever their polarity.
while IFS= read -r line; do
    { cat "$out"; printf '\n%s\n' "$line"; } >"$mut"
    expect_prose_fail "\"$line\"" "outside the guard table"
done <<'EOF'
- The shell guard does not allow `rm -rf /usr`.
- prime-shell-guard.sh asks the human before `rm -rf /usr`.
- Commands that match no pattern are allowed.
- `chmod -R 755 /etc` is refused.
- Every recursive `rm` is stopped.
| `rm -rf /usr` | blocked by the guard |
## What the guard blocks
EOF

# --- tier table, referenced paths, SYSTEM.md ---
if msg="$(python3 -I - "$out" "$here/model-routing.json" "$root" 2>&1 <<'PY'
import json, os, re, sys

text = open(sys.argv[1], encoding="utf-8").read()
routing = json.load(open(sys.argv[2], encoding="utf-8"))
root = sys.argv[3]
errors = []

rows = re.findall(r"^\| (\w+) \| `([^`]+)` \| (\w+) \| (.*) \|$", text, re.M)
got = [(t, m, e, re.findall(r"`([^`]+)` \((\w+)\)", fb)) for t, m, e, fb in rows]
want = [(t, v["model"], v["effort"], [(f["model"], f["trigger"]) for f in v.get("fallbacks", [])])
        for t, v in routing["tiers"].items()]
if got != want:
    errors.append(f"tier table {got} != model-routing.json {want}")

prime_skills = os.path.join(root, "agent/harnesses/primeagent/skills")
listed = [l.strip() for l in open(os.path.join(root, "agent/harnesses/primeagent/skills.list"))
          if l.strip() and not l.startswith("#")]
selectors = {v["model"] for v in routing["tiers"].values()} | {
    f["model"] for v in routing["tiers"].values() for f in v.get("fallbacks", [])}
# Path-like tokens that are deliberately not resolved to a file, with the reason. Any other
# path-like token that fits no category below is a FAIL, never a silent skip.
NOT_REPO_FILES = {
    "/": "the filesystem root (ancestor walk in Context Files)",
    ".": "the `git add .` argument",
    ".proto": "a file extension (Vald Law)",
    "provider/model": "selector format placeholder",
    "vdaas/vald": "GitHub repository name",
    "/home/kpango/go/src/github.com/kpango/": "host path from agent/AGENTS.md Identity",
    "/home/kpango/go/src/github.com/kpango/dotfiles": "host path from agent/AGENTS.md Identity",
    "~/.prime/agent/auth.json": "written by prime-agent login, never by dotfiles (CONTEXT P-6)",
    "~/.ssh/": "credential path named as do-not-write example",
    "~/.gnupg/": "credential path named as do-not-write example",
    "~/.aws/": "credential path named as do-not-write example",
    "~/.kube/config": "credential path named as do-not-write example",
    "~/.cargo/credentials": "credential path named as do-not-write example",
    "~/.npmrc": "credential path named as do-not-write example",
    "AGENTS.md": "generic context file name",
    "auth.json": "prime-agent's own credential file name",
}
# ~/.prime/agent/<rel> -> repo source. This is the mapping install (T10) is expected to wire; the
# live install.mk wiring is NOT checked here (until T10 it still installs pi's AGENTS.md).
INSTALL_MAP = {"model-routing.json": "agent/harnesses/primeagent/model-routing.json",
               "AGENTS.md": "agent/harnesses/primeagent/AGENTS.md",
               "settings.json": "agent/harnesses/primeagent/settings.json"}
counts = {"checked": 0, "excluded": 0, "pattern": 0}
toks = {t for t in re.findall(r"`([^`\n]+)`", text) if not re.search(r"\s", t)}
for tok in sorted(toks):
    path = None
    pathlike = (tok.startswith(("~", "/", ".")) or "/" in tok
                or re.fullmatch(r"[\w.-]+\.(md|json|sh|py|toml|ya?ml)", tok))
    if tok in NOT_REPO_FILES:
        counts["excluded"] += 1
        continue
    if pathlike and ("<" in tok or "*" in tok):
        counts["pattern"] += 1  # glob or <placeholder>: not a concrete file
        continue
    if "/" in tok and tok.split("/")[0] in ("prime-inference", "opencode-go"):
        counts["checked"] += 1
        if tok not in selectors:
            errors.append(f"selector {tok} is not in model-routing.json")
        continue
    if tok.startswith("agent/"):
        path = os.path.join(root, tok)
    elif tok == "Makefile.d/":
        path = os.path.join(root, tok)
    elif tok.startswith("~/.prime/agent/"):
        rel = tok[len("~/.prime/agent/"):]
        if rel == "SYSTEM.md":
            if os.path.exists(os.path.join(root, "agent/harnesses/primeagent/SYSTEM.md")):
                errors.append("agent/harnesses/primeagent/SYSTEM.md must not exist")
            counts["checked"] += 1
            continue
        if rel.startswith("skills/"):
            name, _, rest = rel[len("skills/"):].partition("/")
            path = os.path.join(prime_skills, name, rest)
            if not os.path.exists(path) and name in listed:
                path = os.path.join(root, "agent/skills", name, rest)
        elif rel.startswith("agents/"):
            path = os.path.join(root, "agent", rel)
        elif rel in INSTALL_MAP:
            path = os.path.join(root, INSTALL_MAP[rel])
        else:
            errors.append(f"unmapped install path {tok}")
            continue
    elif pathlike:
        errors.append(f"unclassified path-like token {tok} (map it or add it to NOT_REPO_FILES)")
        continue
    elif re.fullmatch(r"prime-swarm-[a-z-]+|swarm-adapter", tok):
        path = os.path.join(prime_skills, tok, "SKILL.md")
    elif re.fullmatch(r"[a-z-]+-(reviewer|audit)", tok):
        path = os.path.join(root, "agent/agents", tok + ".md")
    if path is None:
        continue  # not path-like: identifier or code, nothing to resolve
    counts["checked"] += 1
    if not os.path.exists(path):
        errors.append(f"{tok} -> {os.path.relpath(path, root)} does not exist")
if errors:
    sys.exit("\n".join(errors))
print(f"{len(got)} tiers, {counts['checked']} referenced paths/selectors checked, "
      f"{counts['excluded']} listed exclusions, {counts['pattern']} patterns; "
      "~/.prime/agent/* resolved via the repo mapping, live install wiring is T10's (not checked)")
PY
)"; then ok "tier table and referenced paths: $msg"; else ng "$msg"; fi

# --- prime-agent prompt --json in a sandbox HOME, without network ---
if ! command -v prime-agent >/dev/null; then
    echo "[SKIP] prime-agent not in PATH"
elif ! unshare -rn true 2>/dev/null; then
    echo "[SKIP] unshare -rn unavailable (cannot guarantee an offline run)"
else
    home="$sandbox/home"
    mkdir -p "$home/.prime/agent" "$sandbox/cwd"
    command cp -- "$out" "$home/.prime/agent/AGENTS.md"
    if (cd "$sandbox/cwd" && env -u PRIME_AGENT_CODING_AGENT_DIR HOME="$home" \
        PRIME_AGENT_DAEMON_SOCKET="$sandbox/d.sock" timeout 60 unshare -rn \
        prime-agent prompt --json --cwd "$sandbox/cwd") >"$sandbox/prompt.json" 2>"$sandbox/prompt.err"; then
        if msg="$(python3 -I - "$sandbox/prompt.json" "$home/.prime/agent/AGENTS.md" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
body = open(sys.argv[2], encoding="utf-8").read().strip()
seg = [s for s in d["segments"] if s["name"] == "project-context"]
if not seg:
    sys.exit("no project-context segment")
if f"## {sys.argv[2]}\n\n{body}" not in d["prompt"]:
    sys.exit("AGENTS.md text not found verbatim in the assembled prompt")
print(f"project-context {seg[0]['chars']} chars")
PY
)"; then ok "prompt --json loads AGENTS.md: $msg"; else ng "prompt --json: $msg"; fi
    else
        ng "prime-agent prompt --json failed: $(head -c 300 "$sandbox/prompt.err")"
    fi
fi

[[ "$fails" -eq 0 ]] || exit 1
