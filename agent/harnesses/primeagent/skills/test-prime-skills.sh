#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks in patterns are literal markdown, not expansions
# Static + sandboxed checks for the prime-swarm-* markdown skills (T8).
# Commit/merge behaviour is the swarm-adapter's and is tested by its pytest suite; here the skills are only checked
# to call it correctly (signatures, result keys), to use graph-compile.sh's status vocabulary,
# to run no git in the target repository (check_git below says what the scan recognises), and to state the
# human-only boundary identically.
# Offline: no model call (`prime-agent prompt` only assembles the system prompt).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness="$(dirname "$here")"
repo="$(cd "$harness/../../.." && pwd)"
adapter_init="$here/swarm-adapter/src/swarm_adapter/__init__.py"
adapter_md="$here/swarm-adapter/SKILL.md"
routing="$harness/model-routing.json"
expected=(prime-swarm-loop prime-swarm-graph prime-swarm-meta prime-swarm-architect prime-swarm-release-gate prime-swarm-secretary)
max_lines=150
# --static-only <dir>: run only the static checks against <dir> (used by the negative self-test)
static_only=0
skills_dir="$here"
if [ "${1:-}" = "--static-only" ]; then static_only=1; skills_dir="${2:?dir}"; fi
fail=0
bad() { echo "FAIL $*" >&2; fail=1; }

# adapter public API: parse __all__ without importing
adapter_all="$(python3 -I - "$adapter_init" <<'PY'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
for n in tree.body:
    if isinstance(n, ast.Assign) and any(getattr(t, "id", "") == "__all__" for t in n.targets):
        print("\n".join(ast.literal_eval(n.value)))
PY
)"
[ -n "$adapter_all" ] || bad "could not parse __all__ from $adapter_init"

# model selectors and tier names from model-routing.json
selectors="$(python3 -I - "$routing" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for t in d["tiers"].values():
    print(t["model"])
    for f in t.get("fallbacks", []):
        print(f["model"])
PY
)"
tiers="$(python3 -I -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["tiers"]))' "$routing")"

# status vocabulary graph-compile.sh accepts (KNOWN_STATUSES), parsed from the script itself
compile_sh="$repo/agent/skills/swarm-graph/scripts/graph-compile.sh"
known_statuses="$(python3 -I - "$compile_sh" <<'PY'
import ast, re, sys
m = re.search(r"KNOWN_STATUSES\s*=\s*(\{.*?\})", open(sys.argv[1]).read(), re.S)
print("\n".join(sorted(ast.literal_eval(m.group(1)))) if m else "")
PY
)"
[ -n "$known_statuses" ] || bad "could not parse KNOWN_STATUSES from $compile_sh"

# the adapter's "Commit and merge (caller side)" section is the single SoT the skills point at: it must hold both
# blocks with the commit chain and the merge chain
adapter_sec="$(python3 -I - "$adapter_md" <<'PY'
import sys
s = open(sys.argv[1]).read()
print(s.split("## Commit and merge (caller side)\n", 1)[1].split("\n## ", 1)[0] if "## Commit and merge (caller side)\n" in s else "")
PY
)"
case "$adapter_sec" in
*'swarm_adapter.commit_tree(wt["path"], st["tree"]'*'swarm_adapter.update_ref(wt["path"]'*'swarm_adapter.tier_b_hits(mission_wt, inc["paths"]'*'swarm_adapter.commit_tree(mission_wt'*'checkout=True'*'swarm_adapter.verify_merge(mission_wt'*) ;;
*) bad "swarm-adapter/SKILL.md: 'Commit and merge (caller side)' section lacks the commit or merge block" ;;
esac

# adapter calls in a skill must match the real signatures in src (arg count, keyword names incl. keyword-only,
# required args; expect_common_dir is REQUIRED wherever a function takes it)
check_calls() {
	python3 -I - "$adapter_init" "$1" <<'PY'
import ast, re, sys
tree = ast.parse(open(sys.argv[1]).read())
names = next(ast.literal_eval(n.value) for n in tree.body
             if isinstance(n, ast.Assign) and any(getattr(t, "id", "") == "__all__" for t in n.targets))
sigs = {}
for n in tree.body:
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name in names:
        params = [a.arg for a in n.args.args]
        kwonly = [a.arg for a in n.args.kwonlyargs]
        required = params[:len(params) - len(n.args.defaults)]
        required += [k for k, d in zip(kwonly, n.args.kw_defaults) if d is None and k != "expect_common_dir"]
        if "expect_common_dir" in kwonly:
            required.append("expect_common_dir")
        sigs[n.name] = (params, kwonly, required)
text = open(sys.argv[2]).read()
pairs = {"(": ")", "[": "]", "{": "}", "<": ">"}
call_re = re.compile(r"(?<![\w.])(?:swarm_adapter\.)?(%s)\(" % "|".join(map(re.escape, sigs)))
for m in call_re.finditer(text):
    fn, i, stack, args, cur = m.group(1), m.end(), [], [], ""
    while i < len(text):
        c = text[i]
        if stack and c == pairs[stack[-1]]:
            stack.pop()
        elif c in pairs:
            stack.append(c)
        elif c == ")" and not stack:
            break
        if c == "," and not stack:
            args.append(cur.strip()); cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        args.append(cur.strip())
    params, kwonly, required = sigs[fn]
    wild = "..." in args
    kw_re = r"^[A-Za-z_]\w*\s*=(?!=)"
    pos = [a for a in args if a != "..." and not re.match(kw_re, a)]
    kws = [a.split("=", 1)[0].strip() for a in args if re.match(kw_re, a)]
    call = "%s(%s)" % (fn, ", ".join(args))
    if len(pos) > len(params):
        print("FAIL %s: %d positional args > %d: %s" % (fn, len(pos), len(params), call))
    for k in kws:
        if k not in params + kwonly:
            print("FAIL %s: unknown keyword '%s': %s" % (fn, k, call))
        elif k in params and params.index(k) < len(pos):
            print("FAIL %s: '%s' given twice: %s" % (fn, k, call))
    if not wild:
        given = set(params[:len(pos)]) | set(kws)
        for r in required:
            if r not in given:
                print("FAIL %s: missing required '%s': %s" % (fn, r, call))
PY
}

# result keys a skill reads from adapter results (`st`, `cs`, `inc`, `hv`, `hc`, `nc`, `pre`) must be keys the adapter returns
check_keys() {
	python3 -I - "$adapter_init" "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
for k in sorted(set(re.findall(r'\b(?:st|cs|inc|hv|hc|nc|pre)\["([A-Za-z_]+)"\]', open(sys.argv[2]).read()))):
    if '"%s"' % k not in src:
        print("FAIL unknown adapter result key '%s'" % k)
PY
}

# (1) git and gh in a skill. The adapter SoT (swarm-adapter/SKILL.md: "No git command runs in the target repository",
# for its seven commit/merge primitives) says any git run there, read-only ones included, executes maker-writable
# config, so ALLOW is empty and every git invocation the scan recognises fails. Scope: a regression check on skill
# text this repo writes, not a defence against markdown crafted to evade it; everything below is a heuristic that
# approximates rendering and CommonMark, and the forms it recognises are the examples named here and in the negative
# self-tests. The scan first normalises each line toward how it renders (not a renderer): HTML character references decoded (`&#103;it`), NFKD compatibility forms folded (fullwidth `ｇｉｔ`),
# combining marks and format characters (zero-width space, soft hyphen) dropped, `<code>`/`<kbd>`/`<samp>`/`<tt>`/
# `<pre>` tags read as a backtick, `~~~` fences read as backtick fences, backslash escapes other than an escaped backtick
# dropped, every `*` dropped, and a `_`/`~` run at a word edge dropped (`_git_`, `__gh__`, `~~git~~`; `GIT_DIR`,
# `commit_tree`, `HEAD~1` and `~/git` keep theirs). Code spans follow CommonMark: a run of n backticks (`x`, ``x``, ...)
# up to the next run of exactly n, inside one paragraph and across its line breaks; a fenced block is one span.
# Recognised git: a bare `git` (any case; not preceded by a letter, digit, `_`, `.`, `/`, `~` or `-`), a path ending
# in `/git` (`/usr/bin/git`, `./git`) or the dashed form `git-<cmd>` with or without a path (`git-update-ref`,
# `/usr/lib/git-core/git-commit`), in prose, code spans, fenced blocks, link text, table cells or HTML comments,
# followed by its options and subcommand (across line breaks, up to the next backtick); a quoted shell string
# starting with it (`"git -C x log"`); a list starting with it (`["git", "-C", wt, "log"]`). A quoted git that is not
# one plain literal (`["git"] + [...]`, `"git" + "..."`, f-strings, `%`/`.format`) fails closed. DENY options (write a
# file, run a diff driver/textconv/pager/editor/transport command, or redirect the repository/config) fail on their
# own, whatever ALLOW holds. Prose: a bare `git` directly followed by `.,;:!?)` or the end of the text (`with git.`,
# `using Git,`) fails as git named as the tool; any other word after a bare `git` is taken as its subcommand and fails,
# except "git command(s)" and "git error" outside code spans and fenced blocks (inside them `command`/`error` is a
# subcommand), nouns that pass unless the rest of that sentence after them (up to the first `. `, `.<newline>` or `;`
# outside a code span) has, outside code spans, a verb from WRITE, or has a code span whose first token, or whose
# first token after leading options (and the value of a VALUE option), is shaped like a git subcommand (SUBLIKE:
# letters/digits joined by single dashes, any case, e.g. `filter-branch`, `notes`, `merge-base`, `incoming`, `HEAD`;
# not `commit_tree`, `<wt>`, `a.b`, `./x`), whether or not git has that subcommand, or, failing both, has a backtick
# run that pairs with none (fail-closed). `gh` (any case; bare, a path ending in `/gh`, or the start of a quoted
# string or list item, `["gh", ...]`; same normalisation and preceding characters as git) fails wherever the scan
# finds it: followed, after any global flags (`-R x`, `--repo x`, `--hostname x`), by any token, as a gh command
# whatever that token is; directly followed by `.,;:!?)` or the end of the text (`with gh.`), as gh named as the
# tool; and otherwise fail-closed. Prose that has the maker commit fails too (only the adapter's blocks commit). Not
# recognised: git or gh reached through a variable or alias (`[GIT, ...]`, `shutil.which`, `$GIT`); the dashed
# `gh-<name>` form; look-alike letters NFKD does not fold (Cyrillic `і` in `gіt`); invocations split across several
# string literals elsewhere in the text; git run by another program the text names (`make`, a script such as
# `harness-select.sh`); in a "git command(s)"/"git error" sentence, verbs not in WRITE and subcommands written as
# plain, emphasised or link text rather than a code span (`filter-branch`, `_filter-branch_`, `[bisect](x)`), WRITE
# verbs or code spans placed before "git command(s)"/"git error", and a subcommand in a code span that is neither its
# first token nor its first token after leading options (`<wt> commit`, `a; bisect`); write verbs or code spans in a
# later sentence; an indented (4-space) code block, which is read as prose, so "git command(s)" there is the noun;
# block structure beyond blank lines and backtick fences (list items, block quotes, tables do not end a paragraph,
# and an escaped backtick still pairs), so where a renderer pairs backticks differently a span can be missed;
# backticks the normalisation creates from `&#96;`, `&grave;` or fullwidth U+FF40, which a renderer shows as literal
# characters, so they can shift span pairing; inline HTML tags or comments splitting git or gh (`g<!-- -->it`,
# `g<b>i</b>t`); fence rules that differ from CommonMark (a `~~~` fence is closed by a backtick fence, and a fence
# indented four or more spaces is still taken as a fence); and
# prose that asks for git work without naming git (e.g. "commit the worktree"); this is a text scan of markdown, not
# an interpreter.
check_git() {
	python3 -I - "$1" <<'PY'
import html, re, sys, unicodedata
def norm(s):  # one line of markdown -> the characters it renders as (line breaks kept, so line numbers hold)
    s = html.unescape(s).replace("\n", " ").replace("\r", " ")  # &#103;it, &lt;code&gt;
    s = "".join(c for c in unicodedata.normalize("NFKD", s) if unicodedata.category(c) not in ("Mn", "Cf"))
    s = re.sub(r"(?i)</?(?:code|kbd|samp|tt|pre)\b[^<>]*>", "`", s)  # inline HTML code reads as a code span
    s = re.sub(r"^(\s*)~{3,}", r"\1```", s)  # ~~~ fence
    s = re.sub(r"\\([!-/:-@\[-^_{-~])", r"\1", s)  # backslash escapes, except an escaped backtick
    s = s.replace("*", "")  # emphasis (`*git*`, `**gh**`, `g*i*t`)
    # `_`/`~` emphasis and strikethrough delimiters at a word edge (`_git_`, `__gh__`, `~~git~~`); `GIT_DIR`,
    # `commit_tree`, `HEAD~1` and `~/git` keep theirs
    return re.sub(r"(?<![^\W_])[_~]+(?=[^\W_])|(?<=[^\W_])[_~]+(?![^\W_])", "", s)
text = "\n".join(norm(x) for x in open(sys.argv[1]).read().split("\n"))
# code spans (CommonMark): a run of n backticks up to the next run of exactly n, within one paragraph and across its
# line breaks; a fenced block is one span. An unpaired run is literal (LOOSE).
SPANS, LOOSE, BT = [], [], re.compile(r"`+")
def inline(a, b):
    i = a
    while (m := BT.search(text, i, b)):
        j, i = m.end(), m.end()
        while (c := BT.search(text, j, b)):
            if len(c.group()) == len(m.group()):
                SPANS.append((m.start(), c.end(), " ".join(text[m.end():c.start()].split()))); i = c.end(); break
            j = c.end()
        else:
            LOOSE.append(m.start())
off, start, fence = 0, None, None
for ln in text.split("\n"):
    if fence:
        if re.fullmatch(r"\s*`{%d,}\s*" % fence[1], ln):
            SPANS.append((fence[0], off + len(ln), " ".join(text[fence[2]:off].split()))); fence = None
    else:
        f = re.match(r"\s*(`{3,})[^`]*$", ln)
        if f or not ln.strip():
            if start is not None:
                inline(start, off); start = None
            if f:
                fence = (off, len(f.group(1)), off + len(ln) + 1)
        elif start is None:
            start = off
    off += len(ln) + 1
if fence:
    SPANS.append((fence[0], len(text), " ".join(text[fence[2]:].split())))
if start is not None:
    inline(start, len(text))
def in_span(pos):
    return any(s <= pos < e for s, e, _ in SPANS)
def sentence_end(pos):  # first `. `, `.<newline>` or `;` after pos that is not inside a code span
    k = pos
    while True:
        end = min([x for x in (text.find(". ", k), text.find(".\n", k), text.find(";", k)) if x >= 0] or [len(text)])
        inside = next((e for s, e, _ in SPANS if s <= end < e), None)
        if inside is None:
            return end
        k = inside
ALLOW = frozenset()
PROSE = {"command", "commands", "error"}  # "no git command in the target repository", "a git error": nouns
# verbs that write or are human-only (delete/remove a branch or worktree, land/force-update/fast-forward main)
WRITE = re.compile(r"(?i)\b(?:commit\w*|merg\w*|push\w*|reset\w*|checkout|check\s+out|rebas\w*|stash\w*|cherry-pick\w*"
                   r"|revert\w*|restor\w*|switch\w*|clean|tag|tags|tagging|amend\w*|update-ref|delet\w*|remov\w*"
                   r"|forc\w*|fast-forward\w*|land|lands|landed|landing|rewrit\w*|prun\w*|drop\w*|creat\w*|renam\w*"
                   r"|move|moves|moved|moving|overwrit\w*|discard\w*|undo\w*|squash\w*|apply|applies|applied)\b")
VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--super-prefix"}
DENY = {"--config-env", "--exec-path", "--git-dir", "--work-tree", "--namespace", "--super-prefix",
        "--output", "--output-directory", "-o", "-O", "--open-files-in-pager", "--ext-diff", "--textconv",
        "--no-index", "--upload-pack", "--receive-pack", "--exec", "--edit", "--tool", "--extcmd"}
GLOBAL_DENY = {"-p", "--paginate"}  # before the subcommand: pager
# `git` may end a sentence or clause (`with git.`, `Git,`); `.git` paths and `git.example` are not git
GIT = re.compile(r"(?i)(?<![\w./~-])((?:[\w.~<>-]*/)*git)(?:-([a-z][a-z0-9]*(?:-[a-z0-9]+)*))?(?![\w/-]|\.[\w/])")
# a code-span token that reads as a git subcommand (fail-closed: shape only, no list of git's subcommands)
SUBLIKE = re.compile(r"(?i)[a-z][a-z0-9]*(?:-[a-z0-9]+)*")
GH = re.compile(r"(?i)(?<![\w./~-])((?:[\w.~<>-]*/)*gh)(?![\w/-]|\.[\w/])")
GH_VALUE = {"-R", "--repo", "--hostname"}  # global flags that take a value (`gh -R owner/repo pr merge`)
def line(pos):
    return text.count("\n", 0, pos) + 1
def span_sub(span):  # the span's first token, or its first token after leading options, if shaped like a subcommand
    toks, i = span.split(), 0
    while i < len(toks) and toks[i].startswith("-"):
        i += 2 if toks[i] in VALUE else 1
    return next((t for t in toks[:1] + toks[i:i + 1] if SUBLIKE.fullmatch(t)), None)
def judge(kind, pos, toks, literal):
    i, glob = 0, []
    while i < len(toks) and toks[i].startswith("-"):
        glob.append(toks[i])
        i += 2 if toks[i] in VALUE else 1
    sub = toks[i] if i < len(toks) else ""
    if kind == "shell" and i == 0 and sub.lower() in PROSE and not in_span(pos):  # in code it is a subcommand
        end = sentence_end(pos)
        spans = [x for x in SPANS if pos <= x[0] < end]
        sent = "".join(text[a:b] for a, b in zip([pos] + [e for _, e, _ in spans], [s for s, _, _ in spans] + [end]))
        w = WRITE.search(sent)  # prose words (code spans: below)
        w = w.group(0) if w else next((x for _, _, c in spans for x in [span_sub(c)] if x), None)
        if w:
            print("prose has git run to %s at line %d" % (w.lower(), line(pos)))
        elif any(pos <= k < end for k in LOOSE):
            print("git command sentence with an unpaired backtick (fail-closed) at line %d" % line(pos))
        return
    form = " (list form)" if kind == "list" else ""
    where = "line %d: git %s" % (line(pos), " ".join(toks[:i + 3]))
    for o in glob + [t for t in toks[i + 1:] if t.startswith("-")]:
        name = o.split("=", 1)[0]
        if o in glob and (name == "-c" or (o[:2] == "-c" and not o.startswith("--"))):
            print("git -c config override%s at %s" % (form, where))
        elif name in DENY or (o in glob and name in GLOBAL_DENY) or (not o.startswith("--") and o[:2] in ("-o", "-O")):
            print("git option that writes a file or runs a command%s (%s) at %s" % (form, o, where))
    if sub not in ALLOW or not literal[i:i + 1] == [True]:
        print("git command outside the allowlist%s at %s" % (form, where))
def closed(pos, why):
    print("git invocation that is not one plain literal (fail-closed: %s) at line %d" % (why, line(pos)))
for m in GH.finditer(text):  # every gh fails: GitHub/remote access is human-only
    e = m.end()
    if e == len(text) or text[e] in ".,;:!?)":
        print("gh named in prose as the tool to use (fail-closed) at line %d" % line(m.start()))
        continue
    toks = [x for x in re.split(r"[\s,\"'`\])]+", text[e:e + 200]) if x]
    i = 0
    while i < len(toks) and toks[i].startswith("-"):  # global flags before the command group
        i += 2 if toks[i] in GH_VALUE else 1
    if i < len(toks):
        print("gh command (GitHub/remote access) at line %d: gh %s" % (line(m.start()), " ".join(toks[:i + 1])))
    else:
        print("gh with no command (fail-closed) at line %d" % line(m.start()))
for m in GIT.finditer(text):
    s, e = m.span()
    dash = [m.group(2)] if m.group(2) else []
    q = text[s - 1] if s else ""
    if q in "\"'":
        pre = re.search(r"([A-Za-z]{0,2})$", text[max(0, s - 3):s - 1]).group(1)
        close = text.find(q, e)
        if close < 0 or "\n" in text[e:close]:
            closed(s, "unterminated string"); continue
        after = text[close + 1:close + 40].lstrip()
        before = text[:s - 1 - len(pre)].rstrip()
        if "f" in pre.lower():
            closed(s, "f-string"); continue
        if before.endswith("+") or after[:1] in ("+", "%") or after.startswith((".format", "*")):
            closed(s, "concatenation or formatting"); continue
        if close == e:  # "git" alone: the first item of a list
            if after[:1] != ",":
                closed(s, "list built from pieces"); continue
            seg = re.split(r"[\])]", text[close + 1:close + 400], maxsplit=1)[0]
            tail = text[close + 1 + len(seg) + 1:close + 1 + len(seg) + 40].lstrip()
            if tail[:1] in ("+", "*"):
                closed(s, "list concatenation"); continue
            items = [x.strip() for x in seg.split(",") if x.strip()]
            lit = [bool(re.fullmatch(r"""(["'])[^"'\\\n]*\1""", x)) for x in items]
            judge("list", s, dash + [x.strip("\"'") for x in items], [True] * len(dash) + lit)
            continue
        toks = dash + text[e:close].split()
        judge("shell", s, toks, [True] * len(toks))
        continue
    if not dash and (e == len(text) or text[e] in ".,;:!?)"):  # `with git.`, `using Git,`: git named as the tool
        print("git named in prose as the tool to use (fail-closed) at line %d: %s" % (line(s), text[max(0, s - 40):e + 1].split("\n")[-1]))
        continue
    seg = text[e:e + 400].split("`", 1)[0]
    toks = dash + [t for t in (t.strip("\"'.,;:()[]") for t in seg.split()[:12]) if t]
    judge("shell", s, toks, [True] * len(toks))
prose = re.compile(r"(?i)(?:maker|it)\s+(?:has\s+|had\s+)?already\s+committed|\bmakers?\b(?:\W+\w+){0,3}?\W+commit(?:s|ted|ting)?\b"
                   r"|staged\W{0,3}\s+(?:is\s+)?empty[^.]{0,80}committed")
for m in prose.finditer(text):
    print("prose has the maker commit at line %d: %s" % (text.count("\n", 0, m.start()) + 1, " ".join(m.group(0).split())))
PY
}

# the human-only boundary paragraph, whitespace-squeezed, from the "## Human-only boundaries" section
boundary() { awk '/^## Human-only boundaries$/{f=1; next} f && /^$/ && n {exit} f && !/^$/ {n=1; print}' "$1" | tr -s ' \n\t' '   '; }
ref_boundary="$(boundary "$skills_dir/prime-swarm-loop/SKILL.md")"
[ -n "$ref_boundary" ] || bad "prime-swarm-loop: no '## Human-only boundaries' paragraph"

# (6) the escalation fields the skills branch on exist in the swarm-implement machine spec
implement_md="$harness/machines/swarm-implement/MACHINE.md"
grep -qF '{\"judgement\": {\"verdict\": \"PASS\"|\"FAIL\"|\"TAMPER\"}}' "$implement_md" || bad "MACHINE.md: checker judgement.verdict TAMPER not found"
grep -qF '\"budget\": \"ok\"|\"exceeded\"' "$implement_md" || bad "MACHINE.md: maker verify.budget exceeded not found"
grep -qF 'write RUN/outcome.json with exactly {\"status\": \"escalated\"}' "$implement_md" || bad "MACHINE.md: escalate outcome.json shape changed"

for name in "${expected[@]}"; do
	dir="$skills_dir/$name"
	f="$dir/SKILL.md"
	if [ ! -f "$f" ]; then bad "$name: SKILL.md missing"; continue; fi

	# frontmatter (skill-creator rules)
	if [ "$(sed -n 1p "$f")" != "---" ]; then bad "$name: no frontmatter"; continue; fi
	fm="$(awk 'NR==1{next} /^---$/{exit} {print}' "$f")"
	fname="$(printf '%s\n' "$fm" | sed -n 's/^name:[[:space:]]*//p' | head -1)"
	desc="$(printf '%s\n' "$fm" | sed -n 's/^description:[[:space:]]*//p' | head -1)"
	[ "$fname" = "$name" ] || bad "$name: frontmatter name '$fname' != directory"
	if [ "${#fname}" -gt 64 ] || ! printf '%s' "$fname" | grep -Eq '^[a-z0-9]+(-[a-z0-9]+)*$'; then
		bad "$name: invalid name"
	fi
	if [ -z "$desc" ] || [ "${#desc}" -gt 1024 ]; then bad "$name: description empty or >1024 chars"; fi

	lines="$(wc -l <"$f")"
	[ "$lines" -le "$max_lines" ] || bad "$name: $lines lines > $max_lines"

	# governance boundaries must be stated
	grep -q 'SWARM.md' "$f" || bad "$name: does not reference SWARM.md"
	grep -Eqi 'Tier B' "$f" || bad "$name: no Tier B statement"
	grep -q 'write-scope-rules.json' "$f" || bad "$name: does not reference write-scope-rules.json"
	# (2) the human-only boundary paragraph is word-for-word the same in every skill
	b="$(boundary "$f")"
	[ -n "$b" ] && [ "$b" = "$ref_boundary" ] || bad "$name: human-only boundary text differs from prime-swarm-loop"
	case "$b" in *"the user's main branch or any remote"*"removes a worktree"*"deletes a branch"*"approves a Tier B change"*"approves the GATE"*"never the target repo's copy"*"Commit and merge (caller side)"*"no git command in the target repository, read-only ones included"*) ;;
	*) bad "$name: human-only boundary incomplete" ;; esac
	case "$b" in *'Residual risk: the adapter'"'"'s seven primitives `change_set`, `tier_b_hits`, `stage_task`, `incoming`, `verify_merge`, `commit_tree` and `update_ref` are all that its "no git command runs in the target repository" guarantee covers.'*'Steps outside them, `swarm_adapter.worktree_alloc`, `swarm_adapter.mission_init`, `harness-select.sh`, the `swarm-implement` init (`rev-parse HEAD`, MACHINE.md) and Checker (`diff <init.base>`, `ls-files`), `swarm-review` (`merge-base`, `diff`, `ls-files`) and `swarm-explore` (`log`, `show`), run git commands in the target repository, so its config and hooks can run there; the repo'"'"'s own gate commands (release gate step 2) are maker-writable too. Maker-written config (`diff.external`, `textconv`, ...) can shape the output of those git commands, and the Checker verdict and the review summary rest on that output.'*) ;;
	*) bad "$name: boundary hides a path that runs git or maker-writable commands in the target repository" ;; esac

	# swarm_adapter.<fn> references
	while read -r fn; do
		[ -n "$fn" ] || continue
		printf '%s\n' "$adapter_all" | grep -qx "$fn" || bad "$name: unknown swarm_adapter.$fn"
	done < <(grep -oE 'swarm_adapter\.[a-z][a-z_]*' "$f" | sed 's/^swarm_adapter\.//' | sort -u)
	# ...their arguments match the real signatures, and the result keys read exist
	while read -r msg; do
		[ -n "$msg" ] && bad "$name: ${msg#FAIL }"
	done < <(check_calls "$f"; check_keys "$f")

	# (1) no git in the target repository (commit/merge and reads only via the adapter), and no copy of the blocks
	# themselves (SoT = swarm-adapter/SKILL.md)
	while read -r msg; do
		[ -n "$msg" ] && bad "$name: $msg"
	done < <(check_git "$f")
	if grep -nE '(commit_tree|update_ref)\(' "$f" >&2; then bad "$name: copies the adapter's commit/merge block (call it by reference)"; fi

	# whole file on one line (whitespace squeezed) for phrases that wrap
	flat="$(tr -s ' \n\t' '   ' <"$f")"
	if printf '%s' "$flat" | grep -qiE 'no merge, push'; then bad "$name: ambiguous merge boundary ('no merge, push')"; fi
	# (5) every backticked blocked* status, and every status a task is set/moved to, is one graph-compile.sh knows
	while read -r st; do
		[ -n "$st" ] || continue
		printf '%s\n' "$known_statuses" | grep -qxF "$st" || bad "$name: unknown status '$st'"
	done < <({ grep -oE '`blocked[^`]*`' "$f" || true
		printf '%s' "$flat" | grep -oE '([Ss]et|back to) `[a-z_()]+`' | grep -oE '`[^`]+`' || true; } | tr -d '`' | sort -u)
	# fable_grant: only exit_code 0 grants
	if grep -q 'fable_grant' "$f"; then
		case "$flat" in *'only when `exit_code` is 0; any other value'*) ;; *) bad "$name: fable_grant: does not restrict grant to exit_code 0" ;; esac
		if printf '%s' "$flat" | grep -qE '`?exit_code`? 1 = denied'; then bad "$name: fable_grant: denial stated only for exit_code 1"; fi
	fi
	case "$name" in
	prime-swarm-loop | prime-swarm-graph)
		case "$flat" in *'Commit rule'*) ;; *) bad "$name: does not use the Commit rule" ;; esac
		;;
	esac
	case "$name" in
	prime-swarm-graph)
		while read -r st; do
			case "$flat" in *"\`$st\`"*) ;; *) bad "$name: status '$st' from graph-compile.sh not used" ;; esac
		done <<<"$known_statuses"
		case "$flat" in *'graph_compile(plan_path, fit=True'*) ;; *) bad "$name: first compile without fit=True (exit 2 branch dead)" ;; esac
		case "$flat" in *'stale_closure'*) ;; *) bad "$name: no stale_closure handling" ;; esac
		case "$flat" in *'back to `pending`'*) ;; *) bad "$name: no retry path back to pending" ;; esac
		# (1) commit in the task worktree, then incoming + the adapter's merge block; done only after the merge
		case "$flat" in *"apply the loop's **Commit rule**"*'swarm_adapter.incoming(<mission worktree>, <task branch>'*"the adapter's merge block with \`inc\`"*'Set `done` only after the merge block finished (or on `zero_diff`)'*) ;; *) bad "$name: no commit rule / incoming / merge block before done" ;; esac
		# (3) stale re-runs are capped, overflow is blocked + human
		case "$flat" in *'Stale re-runs are capped by `attempts`'*'never touched by `note` edits'*'increments its `attempts` first, and at 3 the task goes to `blocked(budget)`'*'report to the human'*) ;; *) bad "$name: stale re-run not capped" ;; esac
		if printf '%s' "$flat" | grep -qE '`rerun` in its `note`'; then bad "$name: stale cap kept in the note cell (overwritten/truncated)"; fi
		# (4) update_ref losing the race re-runs incoming, capped
		case "$flat" in *'**`STOP: update_ref:`** (first time for that task)'*'re-run `incoming` and the block at most once more for that task'*) ;; *) bad "$name: update_ref retry from incoming not capped" ;; esac
		# (2) before the retry: old head..new HEAD is ancestry- and Tier B-checked, and the index/working tree state too
		case "$flat" in *'may be left at the merge result'*'swarm_adapter.verify_merge(<mission worktree>, inc["head"]'*'swarm_adapter.change_set(<mission worktree>, inc["head"]'*'swarm_adapter.tier_b_hits(<mission worktree>, list(cs["paths"])'*'`cs["commits"]` >= 1'*'within `set(pre["paths"])`'*) ;; *) bad "$name: update_ref retry adopts the moved mission HEAD unchecked" ;; esac
		if printf '%s' "$flat" | grep -qE 'moved nothing'; then bad "$name: claims a failed update_ref moved nothing"; fi
		# mission tip: recorded, checked at allocation and before the merge block, advanced only by a finished merge
		case "$flat" in *'`<mission tip>` = the commit the mission branch must be at: the INIT `worktree_alloc` `base`, then the `c["commit"]` of each merge block that finished'*'its `base` (the mission HEAD the allocation saw) must equal `<mission tip>`'*'`inc["head"]` must equal `<mission tip>`'*'set `<mission tip>` to `c["commit"]`'*'with `pre["head"]` in place of `<mission tip>`'*) ;; *) bad "$name: mission HEAD not pinned to a recorded mission tip" ;; esac
		case "$flat" in *'`inc["sha"]` must equal that task'"'"'s `<tip>`'*) ;; *) bad "$name: merged branch commit not pinned to the committed task tip" ;; esac
		# a lost tip stops the mission; HEAD == mission tip before REVIEW and before the GATE, which gets the tip
		case "$flat" in *'If `<mission tip>`, a task'"'"'s `<tip>` or `<common_dir>` is unknown'*'STOP and ask the human; never re-derive it from HEAD, the commit history, a worktree or `@fix_plan.md`'*) ;; *) bad "$name: lost tip not a STOP" ;; esac
		case "$flat" in *'run the loop'"'"'s **HEAD check** on the MISSION worktree with `<mission tip>` as `<tip>` and the INIT `branch` as the allocated `branch`, then `swarm-review`'*'run the HEAD check again, then read'*'with `<mission tip>` as its `<tip>` and the INIT `branch` as its `<branch>`'*) ;; *) bad "$name: REVIEW/GATE without the HEAD check" ;; esac
		# a failing gate is a counted REPLAN; a STOP stops and blocks every other in-flight run
		case "$flat" in *'A failing gate command (its step 2) or a failed gate step 3 check (HEAD, branch or not-committed paths) is a STOP for the human, as the gate says. Only when the human explicitly asks for a fix of failing gate commands is it a REPLAN (step 4, counted in its max 2)'*'No replan left: stop and report to the human.'*) ;; *) bad "$name: gate failure has no graph transition" ;; esac
		case "$flat" in *'**A STOP with other runs in flight** (any STOP in this skill, among them'*'an unknown `<mission tip>`/`<tip>`/`<common_dir>`, compile `warnings` or a `metrics.nodes` mismatch'*'for every other `in_progress` task `await rlm.factory.stop(run_id)` and adopt none of its results'*'set it to `blocked(design)`'*) ;; *) bad "$name: in-flight runs after a STOP undefined" ;; esac
		case "$flat" in *'Failed lenses are a REPLAN (step 4, counted in its max 2): add one `pending` task row per failed lens'*'No replan left: stop and report to the human'*) ;; *) bad "$name: failed review lenses have no graph transition" ;; esac
		if printf '%s' "$flat" | grep -qF 'back to EXECUTE'; then bad "$name: failed review lenses have no graph transition (EXECUTE is a loop state)"; fi
		# note cells are one line without `|`; compile warnings and a node-count mismatch stop the mission
		case "$flat" in *'cell = lambda s: " ".join(str(s).replace("|", "/").split())[:120]'*'STOP if `warnings` is non-empty'*'`metrics.nodes` differs from the number of rows in the `## Tasks` table'*) ;; *) bad "$name: note cells unsanitised / warnings and row count not checked" ;; esac
		case "$flat" in *'Any other `escalated` (neither kind identifiable): `blocked(design)`'*'so no task stays `in_progress`'*) ;; *) bad "$name: unclassified escalated stays in_progress" ;; esac
		case "$flat" in *'`swarm-explore`, at most 3 runs'*'at most 3 runs per review round'*) ;; *) bad "$name: explore/review retries unbounded" ;; esac
		case "$flat" in *'`ready` is empty AND no task is `in_progress` AND some task is not `done`'*) ;; *) bad "$name: replan trigger ignores in_progress" ;; esac
		case "$flat" in *'`done` without `outcome.json`, which includes a refused `init`'*) ;; *) bad "$name: refused init not a non-success retry" ;; esac
		case "$flat" in *'`judgement.verdict` `"TAMPER"`'*'`verify.budget` `"exceeded"`'*) ;; *) bad "$name: TAMPER/budget escalation not told apart by output fields" ;; esac
		if printf '%s' "$flat" | grep -qE 'keep the task `in_progress`|worktree remove|branch -[dD]'; then bad "$name: keeps a task in_progress or deletes a worktree/branch"; fi
		;;
	prime-swarm-loop)
		# (1)(4) the commit chain and the single success rule
		case "$flat" in *'Branch invariant'*'`swarm-prime/*` branch'*'only the adapter'"'"'s `update_ref`'*) ;; *) bad "$name: no branch invariant" ;; esac
		case "$flat" in *'swarm_adapter.change_set(<wt>, <tip>'*'swarm_adapter.tier_b_hits(<wt>, list(cs["paths"])'*'swarm_adapter.stage_task(<wt>, <tip>'*'commit block with `st`'*) ;; *) bad "$name: commit chain change_set -> tier_b_hits -> stage_task -> commit block missing" ;; esac
		# (1) HEAD pinned to the recorded tip (not a run's init.base): a branch moved by a maker is never committed on top of
		case "$flat" in *'`<tip>` = the commit that branch must be at: `worktree_alloc`'"'"'s `base`, then the `c["commit"]`'*'never take it from a run'"'"'s `init.base`'*'fails unless `cs["commits"] == 0`'*'fails unless `st["head"]` equals `<tip>`'*'set `<tip>` to its `c["commit"]`'*'A retry keeps the same `<tip>`'*) ;; *) bad "$name: commit rule does not pin HEAD to the recorded tip" ;; esac
		case "$flat" in *'If `<tip>` or `<common_dir>` is unknown'*'STOP and ask the human; never re-derive it from HEAD, the commit history, a worktree or `@fix_plan.md`'*) ;; *) bad "$name: lost tip not a STOP" ;; esac
		if printf '%s' "$flat" | grep -qF '`cs["commits"] == 0`: HEAD is still `<tip>`'; then bad "$name: claims commits == 0 proves HEAD is the tip"; fi
		case "$flat" in *'0 does not prove HEAD is `<tip>`'*) ;; *) bad "$name: claims commits == 0 proves HEAD is the tip" ;; esac
		case "$flat" in *'**HEAD check** (before REVIEW and before the GATE): `hv = await swarm_adapter.verify_merge(<wt>, <tip>, expect_common_dir=<common_dir>)` must succeed (Success rule) and `hv["head"]` must equal `<tip>`, then `hc = await swarm_adapter.change_set(<wt>, <tip>, expect_common_dir=<common_dir>)` must succeed with `hc["branch"]` equal to the allocated `branch`'*'run the **HEAD check** on the mission worktree, then `swarm-review`'*'run the **HEAD check** again, then present'*'with this `<tip>` as its `<tip>` and the INIT `branch` as its `<branch>`'*) ;; *) bad "$name: REVIEW/GATE without the HEAD check" ;; esac
		case "$flat" in *'**Success rule** (one rule for every call above and for both adapter blocks)'*'`exit_code` 0, no `error` key, an empty `hits`/`tier_b`'*'Anything else = nothing further is committed or merged'*'STOP'*'`st["zero_diff"]` true means the task is done with no change'*) ;; *) bad "$name: no single success rule for the commit chain" ;; esac
		case "$flat" in *'A refused `init` (`init.ok` false) goes to `escalate`'*'never a spec block'*) ;; *) bad "$name: refused init not a non-success retry" ;; esac
		case "$flat" in *'`judgement.verdict` is `"TAMPER"` = TAMPER'*'`verify.budget` is `"exceeded"` = budget exhausted'*) ;; *) bad "$name: TAMPER/budget escalation not told apart by output fields" ;; esac
		case "$flat" in *'at most 3 runs per task in total'*) ;; *) bad "$name: non-success retries unbounded" ;; esac
		case "$flat" in *'at most 3 explore runs in total'*) ;; *) bad "$name: explore retries unbounded" ;; esac
		case "$flat" in *'at most 3 review runs per review round'*) ;; *) bad "$name: review retries unbounded" ;; esac
		;;
	prime-swarm-meta)
		# harness-select runs from an empty temp cwd with PYTHONSAFEPATH=1
		case "$flat" in *'tempfile.TemporaryDirectory() as d'*'cwd=d, env={**os.environ, "PYTHONSAFEPATH": "1"}'*) ;; *) bad "$name: harness-select run without empty cwd + PYTHONSAFEPATH" ;; esac
		if grep -qE '(^|[^/A-Za-z0-9_.-])agent/skills/swarm-meta/' "$f"; then bad "$name: relative harness-select path"; fi
		grep -qF 'swarm_adapter.__file__' "$f" || bad "$name: harness-select not resolved from the adapter's real path"
		rel="$(sed -n 's/.*rel = "\([^"]*\)".*/\1/p' "$f" | head -1)"
		[ -n "$rel" ] && [ -f "$repo/agent/skills/$rel" ] || bad "$name: missing script agent/skills/$rel"
		;;
	prime-swarm-release-gate)
		# the gate lists committed, index, working-tree and untracked changes (a commit cannot hide a change)
		case "$flat" in *'swarm_adapter.change_set(<worktree>, <base>'*'`committed`, `index`, `worktree`, `untracked`'*'swarm_adapter.tier_b_hits(<worktree>'*) ;; *) bad "$name: gate hides the committed or the working-tree change" ;; esac
		case "$flat" in *'`<tip>` = the tip the calling skill recorded'*'never re-derive it from HEAD or the commit history'*'swarm_adapter.verify_merge(<worktree>, <tip>, expect_common_dir=<common_dir>)` must succeed with `hv["head"]` equal to `<tip>`'*'swarm_adapter.change_set(<worktree>, <base>'*) ;; *) bad "$name: gate does not check HEAD against the recorded tip" ;; esac
		case "$flat" in *'`cs = await swarm_adapter.change_set(<worktree>, <base>, expect_common_dir=<common_dir>)` must succeed with `cs["branch"]` equal to `<branch>`'*) ;; *) bad "$name: gate does not check the allocated branch" ;; esac
		case "$flat" in *'Present: the merge target, branch `<branch>` at sha `<tip>`'*'this sha is what the human merges'*) ;; *) bad "$name: gate does not name the exact sha to merge" ;; esac
		case "$flat" in *'`nc = await swarm_adapter.change_set(<worktree>, <tip>, expect_common_dir=<common_dir>)`: every path in `nc["paths"]`'*'list those paths separately and STOP'*'paths that are only `untracked`'*'no public adapter call tells them apart'*) ;; *) bad "$name: gate hides not-committed paths" ;; esac
		case "$flat" in *'when `prime-swarm-graph` called this skill, to its REPLAN (step 4, counted in its max 2'*) ;; *) bad "$name: gate failure from graph goes to a loop state" ;; esac
		case "$flat" in *'A failing gate command (step 2) or a failed step 3 check: report it and STOP for the human, whichever skill called this one. Only when the human explicitly asks for a fix'*) ;; *) bad "$name: gate failure resumes without the human" ;; esac
		if grep -qi 'direct instruction' "$f"; then bad "$name: grants action on direct instruction"; fi
		;;
	esac

	# machine names: factory.run("..."), machines/<x>, and every backticked/quoted swarm-<x> token
	while read -r m; do
		[ -n "$m" ] || continue
		if [ ! -f "$harness/machines/$m/MACHINE.md" ] && [ ! -d "$here/$m" ] && [ ! -d "$here/prime-$m" ]; then bad "$name: unknown machine/skill '$m'"; fi
	done < <({ grep -oE 'rlm\.factory\.run\("[^"]+"\)' "$f" | sed 's/.*("\(.*\)")/\1/' || true
		grep -oE 'machines/[a-z-]+' "$f" | sed 's|machines/||' || true
		grep -oE '[`"]swarm-[a-z-]+[`"]' "$f" | tr -d '`"' || true; } | sort -u)

	# no Skill() tool calls (prime has no Skill tool)
	if grep -q 'Skill(' "$f"; then bad "$name: contains Skill( call"; fi
	# every fable_grant call carries mission=
	while read -r call; do
		[ -n "$call" ] || continue
		case "$call" in *mission=*) ;; *) bad "$name: fable_grant without mission=: $call" ;; esac
	done < <(grep -oE 'fable_grant\([^)]*\)' "$f")

	# script paths
	while read -r p; do
		[ -n "$p" ] || continue
		[ -f "$repo/$p" ] || bad "$name: missing script $p"
	done < <(grep -oE 'agent/skills/[A-Za-z0-9_./-]+\.(sh|py)' "$f" | sort -u)

	# model selectors and tier names
	while read -r s; do
		[ -n "$s" ] || continue
		printf '%s\n' "$selectors" | grep -qxF "$s" || bad "$name: selector '$s' not in model-routing.json"
	done < <(grep -oE '(prime-inference|opencode-go)/[A-Za-z0-9_./-]+[A-Za-z0-9]' "$f" | sort -u)
	while read -r t; do
		[ -n "$t" ] || continue
		printf '%s\n' "$tiers" | grep -qx "$t" || bad "$name: unknown tier '$t'"
	done < <(grep -oE 'tiers\.[A-Za-z]+' "$f" | sed 's/^tiers\.//' | sort -u)

	if [ "$fail" -eq 0 ]; then echo "ok   static $name ($lines lines)"; fi
done

if [ "$static_only" -eq 1 ]; then
	if [ "$fail" -ne 0 ]; then echo "FAILED" >&2; exit 1; fi
	echo "STATIC OK"; exit 0
fi

# negative self-tests: each mutation of a pristine copy must make the static checks FAIL with the given message
neg_case() { # <skill> <sed expression> <expected FAIL substring>
	local neg out
	neg="$(mktemp -d "${TMPDIR:-/tmp}/prime-skills-neg.XXXXXX")"
	command cp -r "$here"/prime-swarm-* "$neg"/
	sed -i "$2" "$neg/$1/SKILL.md"
	if cmp -s "$here/$1/SKILL.md" "$neg/$1/SKILL.md"; then
		bad "negative self-test: mutation '$2' did not change $1"
	else
		out="$("$here/test-prime-skills.sh" --static-only "$neg" 2>&1 || true)"
		if printf '%s\n' "$out" | grep -qF "$3"; then
			echo "ok   negative self-test ($1: $3)"
		else
			bad "negative self-test: '$3' NOT detected after '$2' on $1"
		fi
	fi
	find "$neg" -delete
}
# shellcheck disable=SC2016
{
# vocabulary, machines, signatures
neg_case prime-swarm-loop 's/`swarm-implement`/`swarm-implment`/' "unknown machine/skill 'swarm-implment'"
neg_case prime-swarm-graph 's/`blocked(budget)`/`blocked`/g' "unknown status 'blocked'"
neg_case prime-swarm-graph 's/`. Set `done`$/`. Set `finished`/' "unknown status 'finished'"
neg_case prime-swarm-graph 's/back to `pending`/back to the queue/g' "no retry path back to pending"
neg_case prime-swarm-graph 's/stale_closure/closure/g' "no stale_closure handling"
neg_case prime-swarm-graph 's/fit=True, //' "first compile without fit=True"
neg_case prime-swarm-architect 's/Allowed only when `exit_code`/`exit_code` 1 = denied; allowed when `exit_code`/' "fable_grant: does not restrict grant to exit_code 0"
neg_case prime-swarm-meta 's|rel = "swarm-meta|rel = "agent/skills/swarm-meta|' "relative harness-select path"
neg_case prime-swarm-loop 's/fable_grant(task_id, mission=/fable_grant(task_id, missions=/' "fable_grant: unknown keyword 'missions'"
neg_case prime-swarm-loop 's/decide_shell(cmd, cwd)/decide_shell(cmd, cwd, 1)/' "decide_shell: 3 positional args > 2"
neg_case prime-swarm-loop 's/mission_init(slug, goal, scale, /mission_init(scale, /' "mission_init: missing required 'goal'"
neg_case prime-swarm-loop 's/stage_task(<wt>, <tip>, expect_common_dir=<common_dir>)/stage_task(<wt>, <tip>)/' "stage_task: missing required 'expect_common_dir'"
neg_case prime-swarm-graph 's/expect_common_dir=<common_dir>)` (`<task branch>`/common_dir=<common_dir>)` (`<task branch>`/' "incoming: unknown keyword 'common_dir'"
neg_case prime-swarm-loop 's/`st\["zero_diff"\]` true/`st["zero_diffs"]` true/' "unknown adapter result key 'zero_diffs'"
# (1) git outside the allowlist, a copied block, the commit chain and its single success rule
neg_case prime-swarm-graph 's/merge one task at a time into the MISSION worktree:/merge one task at a time: `git merge --no-ff <task branch>`;/' "git command outside the allowlist"
neg_case prime-swarm-loop 's/^Branch invariant:/Then `git -C <wt> commit -m x`. Branch invariant:/' "git command outside the allowlist"
neg_case prime-swarm-loop 's/^Branch invariant:/Run `git add -- <path>` first. Branch invariant:/' "git command outside the allowlist"
neg_case prime-swarm-release-gate 's/^5\. STOP\./5. `git update-ref refs\/heads\/x HEAD`. STOP./' "git command outside the allowlist"
neg_case prime-swarm-loop 's/^Branch invariant:/`c = await swarm_adapter.commit_tree(wt, st["tree"], [st["head"]], msg)`. Branch invariant:/' "copies the adapter's commit/merge block"
neg_case prime-swarm-loop 's/swarm_adapter.tier_b_hits(<wt>, list(cs\["paths"\])/swarm_adapter.verify(<wt>, list(cs["paths"])/' "commit chain change_set -> tier_b_hits -> stage_task -> commit block missing"
neg_case prime-swarm-loop 's/an empty `hits`\/`tier_b`/a non-empty `staged`/' "no single success rule for the commit chain"
neg_case prime-swarm-graph "s/apply the loop's \*\*Commit rule\*\*/run \`git status\`/" "no commit rule / incoming / merge block before done"
neg_case prime-swarm-release-gate 's/`committed`, `index`, `worktree`, `untracked`/`worktree`/' "gate hides the committed or the working-tree change"
# (2) identical human-only boundary
neg_case prime-swarm-secretary 's/approves the GATE/approves the gate/' "prime-swarm-secretary: human-only boundary text differs"
neg_case prime-swarm-loop "s/Only the human merges into or pushes to the user's main branch or any remote/No merge, push/" "ambiguous merge boundary"
neg_case prime-swarm-architect "s/, never the target repo's copy//" "prime-swarm-architect: human-only boundary text differs"
neg_case prime-swarm-loop 's/deletes a branch, approves/approves/' "prime-swarm-loop: human-only boundary incomplete"
# (3)(4) caps
neg_case prime-swarm-graph 's/Stale re-runs are capped by `attempts`/Stale re-runs are free/' "stale re-run not capped"
neg_case prime-swarm-graph 's/Stale re-runs are capped by `attempts`/Mark `rerun` in its `note`; stale re-runs are capped by `attempts`/' "stale cap kept in the note cell"
neg_case prime-swarm-graph 's/at most once more for that task/until it succeeds/' "update_ref retry from incoming not capped"
neg_case prime-swarm-loop 's/^Branch invariant:/Branch rule:/' "no branch invariant"
# (2) update_ref retry pre-checks
neg_case prime-swarm-graph 's/`pre = await swarm_adapter.verify_merge(<mission worktree>, inc\["head"\], expect_common_dir=<common_dir>)`/the mission HEAD/' "update_ref retry adopts the moved mission HEAD unchecked"
neg_case prime-swarm-graph 's/`cs\["commits"\]` >= 1 and //' "update_ref retry adopts the moved mission HEAD unchecked"
neg_case prime-swarm-graph 's/the mission branch ref did not move/the merge moved nothing/' "claims a failed update_ref moved nothing"
# (1) HEAD pinned to the recorded tip
neg_case prime-swarm-loop 's/(fails unless$/(no check)/' "commit rule does not pin HEAD to the recorded tip"
neg_case prime-swarm-loop 's/equals `<tip>`), then/is any commit), then/' "commit rule does not pin HEAD to the recorded tip"
neg_case prime-swarm-loop 's/change_set(<wt>, <tip>,/change_set(<wt>, <init.base>,/' "commit chain change_set -> tier_b_hits -> stage_task -> commit block missing"
neg_case prime-swarm-loop 's/ and report. A retry keeps the same `<tip>`./ and report./' "commit rule does not pin HEAD to the recorded tip"
# (1) git commands that move refs/files, in every form, and prose that has the maker commit
neg_case prime-swarm-loop 's/^Branch invariant:/`subprocess.run(["git", "-C", wt, "commit", "-m", "x"])`. Branch invariant:/' "git command outside the allowlist (list form)"
neg_case prime-swarm-loop 's/^Branch invariant:/`subprocess.run(["git", "-C", wt, "worktree", "remove", p])`. Branch invariant:/' "git command outside the allowlist (list form)"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Undo with `git -C <wt> reset --hard <tip>`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git -C <wt> cherry-pick <sha>`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git rm -r <dir>`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git -C <wt> branch -f <b> <sha>`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git -c core.hooksPath=\/dev\/null checkout <b>`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git stash push -u`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git push origin HEAD`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git worktree add <p> <b>`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-graph 's/^4\. \*\*REPLAN/Then `git -C <wt>\n   restore <path>`.\n4. **REPLAN/' "git command outside the allowlist"
neg_case prime-swarm-loop 's/^written in `swarm-adapter\/SKILL.md`./written in `swarm-adapter\/SKILL.md`. Empty `st["staged"]`: the maker already committed everything./' "prose has the maker commit"
neg_case prime-swarm-loop 's/^written in `swarm-adapter\/SKILL.md`./written in `swarm-adapter\/SKILL.md`. The maker should commit its own work./' "prose has the maker commit"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> clean -fdx`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git symbolic-ref HEAD refs/heads/other`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> fetch origin main:swarm-prime/x`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> read-tree -m -u <sha>`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> update-index --add`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> branch swarm-prime/new <sha>`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> checkout-index -a -f`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> commit-tree <tree> -p <sha> -m x`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -C <wt> config core.hooksPath <dir>`.\n4. **REPLAN|' "git command outside the allowlist"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `git -c core.fsmonitor=<cmd> log`.\n4. **REPLAN|' "git -c config override"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `subprocess.run(["git", "-C", wt, "clean", "-fd"])`.\n4. **REPLAN|' "git command outside the allowlist (list form)"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Then `subprocess.run(["git", "-C", wt, sub])`.\n4. **REPLAN|' "git command outside the allowlist (list form)"
neg_case prime-swarm-graph 's|^4\. \*\*REPLAN|Have the maker commit its work before the merge.\n4. **REPLAN|' "prose has the maker commit"
neg_case prime-swarm-loop 's|^written in `swarm-adapter/SKILL.md`.|written in `swarm-adapter/SKILL.md`. The maker commits its own work; empty `st["staged"]` is fine.|' "prose has the maker commit"
# graph: mission tip and committed task tip
neg_case prime-swarm-graph 's/^     allocation saw) must equal `<mission tip>`;/     allocation saw) is used;/' "mission HEAD not pinned to a recorded mission tip"
neg_case prime-swarm-graph 's/`inc\["head"\]` must equal `<mission tip>` and //' "mission HEAD not pinned to a recorded mission tip"
neg_case prime-swarm-graph 's/Then set `<mission tip>` to `c\["commit"\]`. //' "mission HEAD not pinned to a recorded mission tip"
neg_case prime-swarm-graph 's/with `pre\["head"\]` in place of `<mission tip>` in the/without the/' "mission HEAD not pinned to a recorded mission tip"
neg_case prime-swarm-graph 's/and `inc\["sha"\]` must equal that task.s `<tip>`/and `inc["sha"]` is merged/' "merged branch commit not pinned to the committed task tip"
# loop/graph orchestration regressions kept from earlier attempts
neg_case prime-swarm-graph 's/AND no task is `in_progress` //' "replan trigger ignores in_progress"
neg_case prime-swarm-graph 's/which includes a refused/which excludes a refused/' "refused init not a non-success retry"
neg_case prime-swarm-graph 's/`verify.budget` `"exceeded"`/`verify.reason` `"exceeded"`/' "TAMPER/budget escalation not told apart by output fields"
neg_case prime-swarm-graph 's/Any other `escalated` (neither kind identifiable): `blocked(design)`/Any other `escalated`: leave it/' "unclassified escalated stays in_progress"
neg_case prime-swarm-graph 's/replace("|", "\/")/replace("|", "")/' "note cells unsanitised / warnings and row count not checked"
neg_case prime-swarm-graph 's/`swarm-explore`, at most 3 runs/`swarm-explore`/' "explore/review retries unbounded"
neg_case prime-swarm-loop 's/never a spec block/or `blocked(spec)`/' "prime-swarm-loop: refused init not a non-success retry"
neg_case prime-swarm-loop 's/`verify.budget` is `"exceeded"`/`outcome.reason` is `"exceeded"`/' "prime-swarm-loop: TAMPER/budget escalation not told apart"
neg_case prime-swarm-loop 's/at most 3 runs per task in total/as often as needed/' "non-success retries unbounded"
neg_case prime-swarm-loop 's/at most 3 explore runs in total/as many explore runs as needed/' "explore retries unbounded"
neg_case prime-swarm-loop 's/most 3 review runs per review round/many review runs as needed/' "review retries unbounded"
neg_case prime-swarm-meta 's/, "PYTHONSAFEPATH": "1"//' "harness-select run without empty cwd + PYTHONSAFEPATH"
# (1) git forms the earlier scan missed: path forms, concatenation, formatting, read-only subcommands, DENY options
R='s|^4\. \*\*REPLAN|'; E='\n4. **REPLAN|'
neg_case prime-swarm-graph "${R}Then \`/usr/bin/git -C <wt> commit -am x\`.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then \`./git -C <wt> commit -am x\`.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then \`subprocess.run([\"/usr/bin/git\", \"-C\", wt, \"commit\", \"-am\", \"x\"])\`.$E" "git command outside the allowlist (list form)"
neg_case prime-swarm-graph "${R}Then \`subprocess.run([\"git\"] + [\"-C\", wt, \"commit\", \"-am\", \"x\"])\`.$E" "fail-closed: list built from pieces"
neg_case prime-swarm-graph "${R}Then \`subprocess.run([\"git\", \"-C\", wt] + [\"commit\"])\`.$E" "fail-closed: list concatenation"
neg_case prime-swarm-graph "${R}Then \`subprocess.run(\"git\" + \" commit -am x\", shell=True)\`.$E" "fail-closed: concatenation or formatting"
neg_case prime-swarm-graph "${R}Then \`subprocess.run(\"git -C \" + wt + \" stash\", shell=True)\`.$E" "fail-closed: concatenation or formatting"
neg_case prime-swarm-graph "${R}Then \`subprocess.run(f\"git -C {wt} commit -am x\", shell=True)\`.$E" "fail-closed: f-string"
neg_case prime-swarm-graph "${R}Then \`subprocess.run(\"git -C %s commit\" % wt, shell=True)\`.$E" "fail-closed: concatenation or formatting"
neg_case prime-swarm-graph "${R}Then \`subprocess.run(\" \".join([\"git\", \"-C\", wt, \"commit\"]), shell=True)\`.$E" "git command outside the allowlist (list form)"
neg_case prime-swarm-graph "${R}Then \`git -C <wt> diff --output=.git/hooks/pre-commit\`.$E" "git option that writes a file or runs a command (--output=.git/hooks/pre-commit)"
neg_case prime-swarm-graph "${R}Then \`git -C <wt> log -1 --ext-diff -p\`.$E" "git option that writes a file or runs a command (--ext-diff)"
neg_case prime-swarm-graph "${R}Then \`git -C <wt> log -p --textconv\`.$E" "git option that writes a file or runs a command (--textconv)"
neg_case prime-swarm-graph "${R}Then \`git diff --no-index a b\`.$E" "git option that writes a file or runs a command (--no-index)"
neg_case prime-swarm-graph "${R}Then \`git --git-dir=<d> --work-tree=<wt> log\`.$E" "git option that writes a file or runs a command (--git-dir=<d>)"
neg_case prime-swarm-graph "${R}Then \`git --exec-path=<d> log\`.$E" "git option that writes a file or runs a command (--exec-path=<d>)"
neg_case prime-swarm-graph "${R}Then \`git --config-env=core.pager=X log\`.$E" "git option that writes a file or runs a command (--config-env=core.pager=X)"
neg_case prime-swarm-graph "${R}Then \`git -p log\`.$E" "git option that writes a file or runs a command (-p)"
neg_case prime-swarm-graph "${R}Then \`git ls-remote --upload-pack=<cmd> origin\`.$E" "git option that writes a file or runs a command (--upload-pack=<cmd>)"
neg_case prime-swarm-graph "${R}Then \`git -C <wt> format-patch -o <dir> HEAD~1\`.$E" "git option that writes a file or runs a command (-o)"
neg_case prime-swarm-graph "${R}Then \`git -C <wt> grep -O <cmd> x\`.$E" "git option that writes a file or runs a command (-O)"
neg_case prime-swarm-graph "${R}Then \`subprocess.run([\"git\", \"-C\", wt, \"diff\", \"--output=x\"])\`.$E" "git option that writes a file or runs a command (list form) (--output=x)"
# read-only git in the target repo runs maker config (adapter SoT): no longer allowed
neg_case prime-swarm-graph "${R}Inspect with \`git -C <wt> log --oneline -3\`.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Inspect with \`subprocess.run([\"git\", \"-C\", wt, \"rev-parse\", \"HEAD\"])\`.$E" "git command outside the allowlist (list form)"
# (2) lost tips, (3) HEAD == tip before REVIEW/GATE and in the release gate, (4) wording and graph lens transition
neg_case prime-swarm-loop 's/STOP and ask the human; never re-derive it from HEAD,/re-derive it from HEAD,/' "prime-swarm-loop: lost tip not a STOP"
neg_case prime-swarm-graph 's/STOP and ask the human; never re-derive it from HEAD,/re-derive it from HEAD,/' "prime-swarm-graph: lost tip not a STOP"
neg_case prime-swarm-loop 's/run the \*\*HEAD check\*\* on the mission worktree, then/run/' "prime-swarm-loop: REVIEW/GATE without the HEAD check"
neg_case prime-swarm-loop 's/run the \*\*HEAD check\*\* again, then present/present/' "prime-swarm-loop: REVIEW/GATE without the HEAD check"
neg_case prime-swarm-loop 's/and `hv\["head"\]` must equal `<tip>`/and `hv["head"]` is shown/' "prime-swarm-loop: REVIEW/GATE without the HEAD check"
neg_case prime-swarm-graph 's/run the loop.s \*\*HEAD check\*\* on the MISSION worktree with$/run the review on the MISSION worktree with/' "prime-swarm-graph: REVIEW/GATE without the HEAD check"
neg_case prime-swarm-graph 's/run the HEAD check again, then read/read/' "prime-swarm-graph: REVIEW/GATE without the HEAD check"
neg_case prime-swarm-release-gate 's/must$/is shown/' "gate does not check HEAD against the recorded tip"
neg_case prime-swarm-release-gate 's/never re-derive it from HEAD or the$/take it from HEAD or the/' "gate does not check HEAD against the recorded tip"
neg_case prime-swarm-loop 's/0 does not prove HEAD is `<tip>`: a HEAD reset to an ancestor of `<tip>` also gives 0, and$/HEAD is still `<tip>`, and/' "claims commits == 0 proves HEAD is the tip"
neg_case prime-swarm-graph 's/Failed lenses are a REPLAN (step 4, counted in its max 2)/Failed lenses become new tasks (back to EXECUTE)/' "failed review lenses have no graph transition"
neg_case prime-swarm-secretary 's/, read-only ones$/,/' "human-only boundary text differs"
# attempt 12: dashed git-<cmd> forms, gh, prose that runs git to write
neg_case prime-swarm-graph "${R}Then \`/usr/lib/git-core/git-commit -am x\`.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then \`git-update-ref refs/heads/swarm-prime/x <sha>\`.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then \`subprocess.run([\"/usr/lib/git-core/git-commit\", \"-am\", \"x\"])\`.$E" "git command outside the allowlist (list form)"
neg_case prime-swarm-graph "${R}Then \`git-diff --output=x\`.$E" "git option that writes a file or runs a command (--output=x)"
neg_case prime-swarm-graph "${R}Then run git commands in <wt> to commit the work.$E" "prose has git run to commit"
neg_case prime-swarm-graph "${R}On a conflict, a git error means: reset the branch.$E" "prose has git run to reset"
neg_case prime-swarm-release-gate 's/^5\. STOP\./5. Then `gh pr merge 12 --merge`. STOP./' "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then \`subprocess.run([\"gh\", \"api\", \"-X\", \"PUT\", url])\`.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then \`/usr/bin/gh release create v1\`.$E" "gh command (GitHub/remote access) at line"
# attempt 12: boundary states the residual risk; HEAD check and gate pin the allocated branch and the exact sha
neg_case prime-swarm-meta 's/`swarm_adapter.mission_init`, `harness-select.sh`, the/`swarm_adapter.mission_init`, the/' "boundary hides a path that runs git"
neg_case prime-swarm-loop 's/must succeed with `hc\["branch"\]`$/must succeed/' "prime-swarm-loop: REVIEW/GATE without the HEAD check"
neg_case prime-swarm-graph 's/`<mission tip>` as `<tip>` and the INIT `branch` as the allocated `branch`, then/`<mission tip>` as `<tip>`, then/' "prime-swarm-graph: REVIEW/GATE without the HEAD check"
neg_case prime-swarm-release-gate 's/succeed with `cs\["branch"\]` equal to `<branch>` (HEAD/succeed (HEAD/' "gate does not check the allocated branch"
neg_case prime-swarm-release-gate 's/Present: the merge target, branch `<branch>` at sha `<tip>` (the full id), and/Present:/' "gate does not name the exact sha to merge"
neg_case prime-swarm-release-gate 's/list those paths separately and STOP/list those paths/' "gate hides not-committed paths"
neg_case prime-swarm-release-gate 's/when `prime-swarm-graph` called this skill, to its REPLAN/when graph called it, to EXECUTE/' "gate failure from graph goes to a loop state"
neg_case prime-swarm-graph 's/is a$/is never a/' "gate failure has no graph transition"
neg_case prime-swarm-graph 's/and adopt none of its results/and adopt its finished results/' "in-flight runs after a STOP undefined"
# attempt 13: git named as the tool, code-span write verbs, gh global flags; full residual-risk list; gate STOP and
# ignored output; in-flight runs on every STOP
neg_case prime-swarm-graph "${R}Then commit the task worktree and push the mission branch with git.$E" "git named in prose as the tool to use"
neg_case prime-swarm-graph "${R}Then merge the task branch into the mission worktree using Git.$E" "git named in prose as the tool to use"
neg_case prime-swarm-graph "${R}Finally delete the old task branch and remove its worktree with git.$E" "git named in prose as the tool to use"
neg_case prime-swarm-graph "${R}Run the git commands \`commit -am x\` and \`push\` in <wt>.$E" "prose has git run to commit"
neg_case prime-swarm-graph "${R}Then \`gh -R owner/repo pr merge 12 --merge\`.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then \`gh --repo owner/repo release create v1\`.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-secretary 's/ and `swarm-explore` (`log`, `show`),/,/' "boundary hides a path that runs git"
neg_case prime-swarm-loop 's/^can run there; the repo.s own gate commands (release gate step 2) are maker-writable too./can run there./' "boundary hides a path that runs git"
neg_case prime-swarm-architect 's/^summary rest on that output/summary need not rest on that output/' "boundary hides a path that runs git"
neg_case prime-swarm-release-gate 's/report it and STOP for the human, whichever$/report it and go back, whichever/' "gate failure resumes without the human"
neg_case prime-swarm-release-gate 's/call tells them apart/call is used/' "gate hides not-committed paths"
neg_case prime-swarm-graph 's/compile `warnings` or a `metrics.nodes` mismatch, //' "in-flight runs after a STOP undefined"
# attempt 14: every gh fails (no list of command groups); any subcommand-shaped code span in a "git command(s)"
# sentence fails (no list of writing subcommands); human-only verbs in WRITE; the boundary keeps its code spans out of
# its "git command(s)" sentences, so moving them back in fails
neg_case prime-swarm-graph "${R}Then \`gh agent-task create \"merge the mission branch into main\"\`.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then \`gh -R o/r discussion create --title x\`.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then \`gh agent create ...\`.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then \`subprocess.run([\"gh\", \"discussion\", \"comment\", ...])\`.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then open the pull request with gh.$E" "gh named in prose as the tool to use"
neg_case prime-swarm-graph "${R}Run the git command \`filter-branch --tree-filter x HEAD\` in <wt>.$E" "prose has git run to filter-branch"
neg_case prime-swarm-graph "${R}Run the git command \`replace <tip> <sha>\` in <wt>.$E" "prose has git run to replace"
neg_case prime-swarm-graph "${R}Run the git command \`sparse-checkout set\` in <wt>.$E" "prose has git run to sparse-checkout"
neg_case prime-swarm-graph "${R}Run the git command \`submodule update --init\` in <wt>.$E" "prose has git run to submodule"
neg_case prime-swarm-graph "${R}Run the git command \`bisect start\` in <wt>.$E" "prose has git run to bisect"
neg_case prime-swarm-graph "${R}Run the git command \`notes remove\` in <wt>.$E" "prose has git run to notes"
neg_case prime-swarm-graph "${R}Run the git command \`-C <wt> notes add\` there.$E" "prose has git run to notes"
neg_case prime-swarm-graph "${R}Use git commands to delete the old task branch and remove its worktree.$E" "prose has git run to delete"
neg_case prime-swarm-graph "${R}Use git commands to land the mission branch on main.$E" "prose has git run to land"
neg_case prime-swarm-graph "${R}Use git commands to force-update the task branch.$E" "prose has git run to force"
neg_case prime-swarm-graph "${R}Use git commands to fast-forward main to the mission tip.$E" "prose has git run to fast-forward"
neg_case prime-swarm-loop 's/^summary rest on that output./summary rest on that output; the git commands are `textconv` and `log`./' "prose has git run to textconv"
# attempt 15: CommonMark code spans (any backtick run length, across line breaks, fenced blocks), emphasis and other
# markdown decoration around git/gh, and git written as it renders (entities, fullwidth, zero-width characters)
neg_case prime-swarm-graph "${R}Run the git command \`\`filter-branch --tree-filter x HEAD\`\` in <wt>.$E" "prose has git run to filter-branch"
neg_case prime-swarm-graph "${R}Run the git command \`\`replace <tip> <sha>\`\` in <wt>.$E" "prose has git run to replace"
neg_case prime-swarm-graph "${R}On a git error, run \`\`update-index --chmod=+x f\`\` and retry.$E" "prose has git run to update-index"
neg_case prime-swarm-graph "${R}Run the git command \`filter-branch\n--tree-filter x HEAD\` in <wt>.$E" "prose has git run to filter-branch"
neg_case prime-swarm-graph "${R}Run the git commands \`bisect\nstart\` in <wt>.$E" "prose has git run to bisect"
neg_case prime-swarm-graph "${R}Run the git command \`\`\`notes add; x\`\`\` in <wt>.$E" "prose has git run to notes"
neg_case prime-swarm-graph "${R}Run the git command \`a. b\` then \`bisect\` in <wt>.$E" "prose has git run to bisect"
neg_case prime-swarm-graph "${R}Run the git command \`filter-branch x in <wt>.\n$E" "git command sentence with an unpaired backtick"
neg_case prime-swarm-graph "${R}\`\`\`sh\ngit -C <wt> commit -am x\n\`\`\`$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}\`\`\`sh\n# run the git commands\nfilter-branch x\n\`\`\`$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}~~~\ngh pr merge 12\n~~~$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Run \`git commands\` in <wt>.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run _git_ commit -am x in <wt>.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run _gh_ pr merge 12.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then run __git__ commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run **gh** pr merge 12.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then run ~~git~~ commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run g*i*t commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run \\\\_git\\\\_ commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run <code>git commit -am x<\\/code>.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Run the git command <code>filter-branch x<\\/code> in <wt>.$E" "prose has git run to filter-branch"
neg_case prime-swarm-graph "${R}Then <kbd>gh<\\/kbd> pr merge 12.$E" "gh command (GitHub/remote access) at line"
neg_case prime-swarm-graph "${R}Then <git> commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then [git commit](https:\\/\\/x) the work.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run \\&#103;it commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Run the git command \\&#96;filter-branch x\\&#96; in <wt>.$E" "prose has git run to filter-branch"
neg_case prime-swarm-graph "${R}Then run ｇｉｔ commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run g$(printf '​')it commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}Then run gi$(printf '­')t commit -am x.$E" "git command outside the allowlist at"
neg_case prime-swarm-graph 's#^4\. \*\*REPLAN#| step | 1 |\n|---|---|\n| run | git commit -am x |\n4. **REPLAN#' "git command outside the allowlist at"
neg_case prime-swarm-graph "${R}<!-- git commit -am x -->$E" "git command outside the allowlist at"
}

# positive control: mentions of git that are not invocations still pass (the scan is not "any 'git' substring"):
# git as a noun, `.git` paths, `gitlink`, GIT_* names, `--git-dir` inside prose about the adapter
pos="$(mktemp -d "${TMPDIR:-/tmp}/prime-skills-pos.XXXXXX")"
command cp -r "$here"/prime-swarm-* "$pos"/
sed -i 's|^4\. \*\*REPLAN|A git error, a `<wt>/.git` file or `.git/hooks/pre-commit`, the `/usr/lib/git-core/` directory, a gitlink entry, GIT_DIR, GitHub, the high-level design and git commands in the target repository that only read are not git commands. The `.github/workflows` dir, `gh-pages`, enough, through and the `commit_tree` call pass too, as do _GIT_DIR_, *a git error*, `HEAD~1` and `swarm_adapter.__file__`.\n4. **REPLAN|' "$pos/prime-swarm-graph/SKILL.md"
if out="$("$here/test-prime-skills.sh" --static-only "$pos" 2>&1)" && ! cmp -s "$here/prime-swarm-graph/SKILL.md" "$pos/prime-swarm-graph/SKILL.md"; then
	echo "ok   positive self-test (git nouns, .git paths, git-core dir, gitlink, GIT_DIR, .github, gh-pages, emphasis, prose without a write verb pass)"
else
	bad "positive self-test: non-invocation git mention rejected: $(printf '%s\n' "$out" | grep FAIL | head -3)"
fi
find "$pos" -delete

# behavioural checks (offline, sandboxed HOME, no model call)
beh="$(mktemp -d "${TMPDIR:-/tmp}/prime-skills-beh.XXXXXX")"
# (1) premise: with A in_progress and B,C depending on it, graph-compile.sh reports an empty ready list, so a
# trigger on "ready is empty" alone would replan a healthy DAG
printf '%s\n' '## Tasks' '' '| task-id | summary | depends | worktree | status | attempts | domain | note |' \
	'|---|---|---|---|---|---|---|---|' '| A | a | - | - | in_progress | 0 | x | - |' \
	'| B | b | A | - | pending | 0 | x | - |' '| C | c | A | - | pending | 0 | x | - |' >"$beh/plan.md"
if (cd "$beh" && bash "$repo/agent/skills/swarm-graph/scripts/graph-compile.sh" plan.md) | python3 -I -c \
	'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d["ready"]==[] and any(n["status"]=="in_progress" for n in d["nodes"]) else 1)'; then
	echo "ok   behaviour graph: ready empty while in_progress (replan must also require no in_progress)"
else
	bad "behaviour graph: premise check failed"
fi
# (3) a json.py planted in the cwd: runs without the defence (repro), not with the skill's snippet
mkdir -p "$beh/home" "$beh/repo"
git -C "$beh/repo" init -q
printf 'import pathlib\npathlib.Path(%s).write_text("pwned")\n' "'$beh/PWNED'" >"$beh/repo/json.py"
hs="$repo/agent/skills/swarm-meta/scripts/harness-select.sh"
(cd "$beh/repo" && env -u PYTHONSAFEPATH HOME="$beh/home" bash "$hs" "fix a typo" "$beh/repo" >/dev/null 2>&1 || true)
if [ -f "$beh/PWNED" ]; then echo "ok   behaviour meta: planted json.py runs from cwd without the defence (repro)"; else bad "behaviour meta: repro did not trigger (test would pass vacuously)"; fi
command rm -f "$beh/PWNED"
snippet="$(python3 -I - "$here/prime-swarm-meta/SKILL.md" <<'PY'
import sys, textwrap
lines = open(sys.argv[1]).read().splitlines()
i = next(k for k, l in enumerate(lines) if l.strip() == "import os, subprocess, tempfile")
j = next(k for k in range(i, len(lines)) if "subprocess.run(" in lines[k])
print(textwrap.dedent("\n".join(lines[i:j + 1])))
PY
)"
if (cd "$beh/repo" && env -u PYTHONSAFEPATH HOME="$beh/home" python3 -I - "$hs" "$beh/repo" <<PY
import sys; script, repo, goal = sys.argv[1], sys.argv[2], "fix a typo"
$snippet
import json as _j; d = _j.loads(r.stdout); sys.exit(0 if r.returncode == 0 and "recommendation" in d else 1)
PY
) && [ ! -f "$beh/PWNED" ]; then
	echo "ok   behaviour meta: skill snippet runs harness-select without importing the planted json.py"
else
	bad "behaviour meta: skill snippet failed or imported the planted json.py"
fi
# graph note cells: `cell` from the skill; a raw `|` row is dropped by graph-compile.sh (repro), the sanitised row is kept
cellfn="$(sed -n 's/.*`\(cell = lambda s: [^`]*\)`.*/\1/p' "$here/prime-swarm-graph/SKILL.md" | head -1)"
[ -n "$cellfn" ] || bad "behaviour graph: cell lambda not found in the skill"
gplan() { # <note> -> plan with tasks A (done) and B (pending, depends A), B's note as given
	printf '%s\n' '## Tasks' '' '| task-id | summary | depends | worktree | status | attempts | domain | note |' '|---|---|---|---|---|---|---|---|' \
		'| A | a | - | - | done | 0 | x | - |' "| B | b | A | - | pending | 1 | x | $1 |" '| C | c | A | - | pending | 0 | x | - |' >"$beh2/plan.md"
	(cd "$beh2" && bash "$repo/agent/skills/swarm-graph/scripts/graph-compile.sh" plan.md) | python3 -I -c 'import json,sys; d=json.load(sys.stdin); print(len(d["warnings"]), d["metrics"]["nodes"])'
}
beh2="$(mktemp -d "${TMPDIR:-/tmp}/prime-skills-beh2.XXXXXX")"
raw='fatal: bad | pipe'
if [ "$(gplan "$raw")" = "1 2" ]; then echo "ok   behaviour graph: a raw '|' in note drops the row (warnings=1, nodes 2 of 3 rows) - why the skill stops on warnings/node count"; else bad "behaviour graph: raw '|' repro changed: $(gplan "$raw")"; fi
safe="$(python3 -I -c "$cellfn
print(cell('$raw' + chr(10) + 'second line ' + 'x' * 300))")"
case "$safe" in *'|'*|*$'\n'*) bad "behaviour graph: cell() output has | or newline" ;; esac
if [ "${#safe}" -le 120 ] && [ "$(gplan "$safe")" = "0 3" ]; then echo "ok   behaviour graph: cell() output is one line, <= 120 chars, no '|'; the row survives (warnings=0, nodes 3 of 3)"; else bad "behaviour graph: cell() output not accepted: $(gplan "$safe")"; fi
command rm -rf "$beh2"
command rm -rf "$beh"


# sandboxed prime-agent: every skill appears in the skills-inventory
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/prime-skills.XXXXXX")"
trap 'command rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/agent/skills" "$sandbox/cwd"
for name in "${expected[@]}"; do
	if [ -d "$here/$name" ]; then ln -s "$here/$name" "$sandbox/agent/skills/$name"; fi
done
if HOME="$sandbox" PRIME_AGENT_CODING_AGENT_DIR="$sandbox/agent" PRIME_AGENT_DAEMON_SOCKET="$sandbox/d.sock" \
	timeout 120 prime-agent prompt --json --cwd "$sandbox/cwd" >"$sandbox/prompt.json" 2>"$sandbox/err"; then
	python3 -I - "$sandbox/prompt.json" "${expected[@]}" <<'PY' || fail=1
import json, sys
d = json.load(open(sys.argv[1]))
seg = [s for s in d["segments"] if s["name"] == "skills-inventory"]
if not seg or seg[0]["chars"] <= 0:
    print("FAIL no skills-inventory segment", file=sys.stderr); sys.exit(1)
inv = d["prompt"].split("<available_skills>", 1)[-1]
rc = 0
for n in sys.argv[2:]:
    if f"<name>{n}</name>" in inv:
        print(f"ok   inventory {n}")
    else:
        print(f"FAIL {n} not in skills-inventory", file=sys.stderr); rc = 1
sys.exit(rc)
PY
else
	bad "prime-agent prompt failed: $(tail -n 3 "$sandbox/err")"
fi

if [ "$fail" -ne 0 ]; then echo "FAILED" >&2; exit 1; fi
echo "ALL OK"
