#!/usr/bin/env bash
# shellcheck disable=SC2016 # backticks in patterns are literal markdown, not expansions
# Static + sandboxed checks for the prime-swarm-* markdown skills (T8).
# Offline: no model call (`prime-agent prompt` only assembles the system prompt).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
harness="$(dirname "$here")"
repo="$(cd "$harness/../../.." && pwd)"
adapter_init="$here/swarm-adapter/src/swarm_adapter/__init__.py"
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

# adapter calls in a skill must match the real signatures in src (arg count, keyword names, required args)
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
        required = params[:len(params) - len(n.args.defaults)]
        sigs[n.name] = (params, required)
text = open(sys.argv[2]).read()
pairs = {"(": ")", "[": "]", "{": "}", "<": ">"}
call_re = re.compile(r"(?<![\w.])(?:swarm_adapter\.)?(%s)\(" % "|".join(map(re.escape, sigs)))
for m in call_re.finditer(text):
    fn, i, depth, stack, args, cur = m.group(1), m.end(), 0, [], [], ""
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
    params, required = sigs[fn]
    wild = "..." in args
    pos = [a for a in args if a != "..." and not re.match(r"^[A-Za-z_]\w*\s*=(?!=)", a)]
    kws = [a.split("=", 1)[0].strip() for a in args if re.match(r"^[A-Za-z_]\w*\s*=(?!=)", a)]
    call = "%s(%s)" % (fn, ", ".join(args))
    if len(pos) > len(params):
        print("FAIL %s: %d positional args > %d: %s" % (fn, len(pos), len(params), call))
    for k in kws:
        if k not in params:
            print("FAIL %s: unknown keyword '%s': %s" % (fn, k, call))
        elif params.index(k) < len(pos):
            print("FAIL %s: '%s' given twice: %s" % (fn, k, call))
    if not wild:
        given = set(params[:len(pos)]) | set(kws)
        for r in required:
            if r not in given:
                print("FAIL %s: missing required '%s': %s" % (fn, r, call))
PY
}

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
	grep -qi 'human' "$f" || bad "$name: no human-only boundary"
	grep -Eqi 'Tier B' "$f" || bad "$name: no Tier B statement"

	# swarm_adapter.<fn> references
	while read -r fn; do
		[ -n "$fn" ] || continue
		printf '%s\n' "$adapter_all" | grep -qx "$fn" || bad "$name: unknown swarm_adapter.$fn"
	done < <(grep -oE 'swarm_adapter\.[a-z][a-z_]*' "$f" | sed 's/^swarm_adapter\.//' | sort -u)
	# ...and their arguments match the real signatures
	while read -r msg; do
		[ -n "$msg" ] && bad "$name: ${msg#FAIL }"
	done < <(check_calls "$f")

	# whole file on one line (whitespace squeezed) for phrases that wrap
	flat="$(tr -s ' \n\t' '   ' <"$f")"
	# merge boundary: user's main/remote is human-only; the old blanket wording contradicts the graph merge step
	case "$flat" in *"the user's main branch or any remote"*) ;; *) bad "$name: no user-main/remote merge boundary" ;; esac
	if printf '%s' "$flat" | grep -qiE 'no merge, push'; then bad "$name: ambiguous merge boundary ('no merge, push')"; fi
	# every backticked blocked* status must be one graph-compile.sh knows
	while read -r st; do
		[ -n "$st" ] || continue
		printf '%s\n' "$known_statuses" | grep -qxF "$st" || bad "$name: unknown status '$st'"
	done < <(grep -oE '`blocked[^`]*`' "$f" | tr -d '`' | sort -u)
	# fable_grant: only exit_code 0 grants
	if grep -q 'fable_grant' "$f"; then
		case "$flat" in *'only when `exit_code` is 0; any other value'*) ;; *) bad "$name: fable_grant: does not restrict grant to exit_code 0" ;; esac
		if printf '%s' "$flat" | grep -qE '`?exit_code`? 1 = denied'; then bad "$name: fable_grant: denial stated only for exit_code 1"; fi
	fi
	case "$name" in
	prime-swarm-graph)
		while read -r st; do
			case "$flat" in *"\`$st\`"*) ;; *) bad "$name: status '$st' from graph-compile.sh not used" ;; esac
		done <<<"$known_statuses"
		case "$flat" in *'graph_compile(plan_path, fit=True'*) ;; *) bad "$name: first compile without fit=True (exit 2 branch dead)" ;; esac
		case "$flat" in *'stale_closure'*) ;; *) bad "$name: no stale_closure handling" ;; esac
		case "$flat" in *'back to `pending`'*) ;; *) bad "$name: no retry path back to pending" ;; esac
		case "$flat" in *'git commit -m'*'git merge --no-ff'*'Set `done` only after that merge'*) ;; *) bad "$name: no commit before merge before done" ;; esac
		;;
	prime-swarm-meta)
		if grep -qE '(^|[^/A-Za-z0-9_.-])agent/skills/swarm-meta/' "$f"; then bad "$name: relative harness-select path"; fi
		grep -qF 'swarm_adapter.__file__' "$f" || bad "$name: harness-select not resolved from the adapter's real path"
		rel="$(sed -n 's/.*rel = "\([^"]*\)".*/\1/p' "$f" | head -1)"
		[ -n "$rel" ] && [ -f "$repo/agent/skills/$rel" ] || bad "$name: missing script agent/skills/$rel"
		;;
	esac

	# machine names: factory.run("..."), machines/<x>, and every backticked/quoted swarm-<x> token
	while read -r m; do
		[ -n "$m" ] || continue
		if [ ! -f "$harness/machines/$m/MACHINE.md" ] && [ ! -d "$here/$m" ] && [ ! -d "$here/prime-$m" ]; then bad "$name: unknown machine/skill '$m'"; fi
	done < <({ grep -oE 'rlm\.factory\.run\("[^"]+"\)' "$f" | sed 's/.*("\(.*\)")/\1/' || true
		grep -oE 'machines/[a-z-]+' "$f" | sed 's|machines/||' || true
		# shellcheck disable=SC2016
		grep -oE '[`"]swarm-[a-z-]+[`"]' "$f" | tr -d '`"' || true; } | sort -u)

	# no Skill() tool calls (prime has no Skill tool)
	if grep -q 'Skill(' "$f"; then bad "$name: contains Skill( call"; fi
	# Tier B is defined by write-scope-rules.json (shared procedure lives in prime-swarm-loop)
	grep -q 'write-scope-rules.json' "$f" || bad "$name: does not reference write-scope-rules.json"
	# every fable_grant call carries mission=
	while read -r call; do
		[ -n "$call" ] || continue
		case "$call" in *mission=*) ;; *) bad "$name: fable_grant without mission=: $call" ;; esac
	done < <(grep -oE 'fable_grant\([^)]*\)' "$f")
	# release-gate must not grant merge/push on instruction
	if [ "$name" = prime-swarm-release-gate ] && grep -qi 'direct instruction' "$f"; then bad "$name: grants action on direct instruction"; fi

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
neg_case prime-swarm-loop 's/`swarm-implement`/`swarm-implment`/' "unknown machine/skill 'swarm-implment'"
neg_case prime-swarm-graph 's/`blocked(budget)`/`blocked`/g' "unknown status 'blocked'"
neg_case prime-swarm-graph 's/back to `pending`/back to the queue/g' "no retry path back to pending"
neg_case prime-swarm-graph 's/git commit -m/git stash -m/' "no commit before merge before done"
neg_case prime-swarm-graph 's/stale_closure/closure/g' "no stale_closure handling"
neg_case prime-swarm-graph 's/fit=True, //' "first compile without fit=True"
neg_case prime-swarm-loop "s/Merging into or pushing to the user's main branch or any remote/No merge, push/" "ambiguous merge boundary"
neg_case prime-swarm-architect 's/Allowed only when `exit_code`/`exit_code` 1 = denied; allowed when `exit_code`/' "fable_grant: does not restrict grant to exit_code 0"
neg_case prime-swarm-meta 's|rel = "swarm-meta|rel = "agent/skills/swarm-meta|' "relative harness-select path"
neg_case prime-swarm-loop 's/fable_grant(task_id, mission=/fable_grant(task_id, missions=/' "fable_grant: unknown keyword 'missions'"
neg_case prime-swarm-loop 's/decide_shell(cmd, cwd)/decide_shell(cmd, cwd, 1)/' "decide_shell: 3 positional args > 2"
neg_case prime-swarm-loop 's/mission_init(slug, goal, scale, /mission_init(scale, /' "mission_init: missing required 'goal'"
}

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
