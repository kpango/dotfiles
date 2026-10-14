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
		# (2) Tier B check on every path to be committed, before commit and merge; hit = blocked(spec) + report
		case "$flat" in *'`changed(<task worktree>, <init.base>)`'*'base..HEAD + index + working tree + untracked'*'any protected (Tier B) path means NO commit and NO merge; set `blocked(spec)`'*'git commit -m'*) ;; *) bad "$name: no Tier B check (committed range) before commit" ;; esac
			case "$flat" in *'test `incoming(<mission worktree>, <task branch>)`'*'NO merge'*) ;; *) bad "$name: no pre-merge incoming() check" ;; esac
			# (2b) a failing git is fail closed: blocked(design), never "no changes"
			case "$flat" in *'A git error (exception, e.g. a missing worktree) is fail closed: NO commit, NO merge, `blocked(design)`'*) ;; *) bad "$name: git failure not fail-closed" ;; esac
			# (3b) note cells are one line without `|`; compile warnings and a node-count mismatch stop the mission
			case "$flat" in *'cell = lambda s: " ".join(str(s).replace("|", "/").split())[:120]'*'STOP if `warnings` is non-empty'*'`metrics.nodes` differs from the number of rows in the `## Tasks` table'*) ;; *) bad "$name: note cells unsanitised / warnings and row count not checked" ;; esac
		# (3) zero-diff PASS is an explicit done branch (commit rc=1 / merge "Already up to date" create nothing)
		case "$flat" in *'Zero-diff PASS (`stageable(changed)` empty and `commits(<task worktree>, <init.base>)` is 0'*'set `done` directly'*'merge commit exists, or after a zero-diff PASS'*) ;; *) bad "$name: no zero-diff PASS done branch" ;; esac
		# (5) every escalated / failed-git outcome maps to a blocked(*) state, never left in_progress
		case "$flat" in *'Any other `escalated` (neither kind identifiable): `blocked(design)`'*'so no task stays `in_progress`'*) ;; *) bad "$name: unclassified escalated stays in_progress" ;; esac
		case "$flat" in *'A failed commit or a merge that fails for a reason other than a conflict'*'set `blocked(design)`, the error in `note`, and report. A merge conflict'*) ;; *) bad "$name: failed commit/merge stays in_progress" ;; esac
		# (4) explore / review non-success runs are capped
		case "$flat" in *'`swarm-explore`, at most 3 runs'*'at most 3 runs per review round'*) ;; *) bad "$name: explore/review retries unbounded" ;; esac
		# (1) replan only on a true deadlock: an empty ready list is normal while a task is in_progress
		case "$flat" in *'`ready` is empty AND no task is `in_progress` AND some task is not `done`'*) ;; *) bad "$name: replan trigger ignores in_progress" ;; esac
		if printf '%s' "$flat" | grep -qiE 'empty `ready` list with tasks left'; then bad "$name: replan trigger ignores in_progress"; fi
		# (2) merge conflict: abort, back to pending, NEW worktree from mission HEAD; no worktree/branch removal
		case "$flat" in *'A merge conflict: `git merge --abort`'*'set the task back to `pending` while `attempts` < 3'*'NEW worktree from the mission HEAD'*) ;; *) bad "$name: merge conflict has no retry path" ;; esac
		if printf '%s' "$flat" | grep -qE 'keep the task `in_progress`|worktree remove|branch -[dD]'; then bad "$name: merge conflict keeps task in_progress or deletes worktree/branch"; fi
		# (5) a refused init is a non-success retry, never blocked(spec)
		case "$flat" in *'`done` without `outcome.json`, which includes a refused `init`'*) ;; *) bad "$name: refused init not a non-success retry" ;; esac
		if printf '%s' "$flat" | grep -qE 'refused `init`[^.]*`blocked\(spec\)`'; then bad "$name: refused init mapped to blocked(spec)"; fi
		# (6) escalation kinds by real output fields
		case "$flat" in *'`judgement.verdict` `"TAMPER"`'*'`verify.budget` `"exceeded"`'*) ;; *) bad "$name: TAMPER/budget escalation not told apart by output fields" ;; esac
		;;
	prime-swarm-loop)
		# (4) Tier B rules never from cwd / target repo
		case "$flat" in *'NEVER read a cwd-relative path or a copy inside the target repo'*) ;; *) bad "$name: Tier B rules may come from the target repo" ;; esac
		if grep -qF 'open("<rules path>")' "$f" || grep -qE 'open\("agent/write-scope-rules' "$f"; then bad "$name: Tier B rules may come from the target repo"; fi
		# (5)(6)(7)
		case "$flat" in *'A refused `init` (`init.ok` false) goes to `escalate`'*'never a spec block'*) ;; *) bad "$name: refused init not a non-success retry" ;; esac
		case "$flat" in *'`judgement.verdict` is `"TAMPER"` = TAMPER'*'`verify.budget` is `"exceeded"` = budget exhausted'*) ;; *) bad "$name: TAMPER/budget escalation not told apart by output fields" ;; esac
		case "$flat" in *'at most 3 runs per task in total'*) ;; *) bad "$name: non-success retries unbounded" ;; esac
		# (1) prime worktrees live outside the repo: protected() also tests the main-checkout twin
		case "$flat" in *'def protected(target)'*'if top and common: c.append('*) ;; *) bad "$name: write-scope check ignores prime worktree layout" ;; esac
		# (2) commit check before the commit; (3) zero-diff PASS skips the commit
		case "$flat" in *'`changed(<worktree>, <init.base>)`: any protected path (`@fix_plan.md` included) means NO commit'*'`stageable(changed)` empty AND `commits(...)` 0 = zero-diff PASS'*'git commit -m'*) ;; *) bad "$name: no Tier B check / zero-diff branch before commit" ;; esac
			# (2b) git failures fail closed; the committed range is part of the union; @fix_plan.md is never staged
			case "$flat" in *'A git error (exception) is fail closed: stop and report'*) ;; *) bad "$name: git failure not fail-closed" ;; esac
			case "$flat" in *'if p.returncode: raise RuntimeError('*) ;; *) bad "$name: git helper ignores the exit code" ;; esac
			case "$flat" in *'def changed(wt, base): # base..HEAD + index + working tree + untracked'*'D + (base, "HEAD", "--")'*'D + ("--cached", base, "--")'*'D + (base, "--")'*) ;; *) bad "$name: changed() ignores base..HEAD, the index or the working tree" ;; esac
			case "$flat" in *'raise RuntimeError("no write-scope-rules.json: every edit is protected; stop and ask the human")'*) ;; *) bad "$name: missing rules file not an explicit stop" ;; esac
			case "$flat" in *'`@fix_plan.md` is untracked in the worktree'*'never stage it'*'x != "@fix_plan.md"'*|*'x != "@fix_plan.md"'*'`@fix_plan.md` is untracked in the worktree'*'never stage it'*) ;; *) bad "$name: @fix_plan.md not excluded from staging" ;; esac
		# (4) explore / review non-success runs are capped
		case "$flat" in *'at most 3 explore runs in total'*) ;; *) bad "$name: explore retries unbounded" ;; esac
		case "$flat" in *'at most 3 review runs per review round'*) ;; *) bad "$name: review retries unbounded" ;; esac
		;;
	prime-swarm-meta)
		# (3) harness-select runs from an empty temp cwd with PYTHONSAFEPATH=1
		case "$flat" in *'tempfile.TemporaryDirectory() as d'*'cwd=d, env={**os.environ, "PYTHONSAFEPATH": "1"}'*) ;; *) bad "$name: harness-select run without empty cwd + PYTHONSAFEPATH" ;; esac
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
	if [ "$name" != prime-swarm-loop ]; then
		case "$flat" in *"never the target repo's copy"*) ;; *) bad "$name: Tier B rules may come from the target repo" ;; esac
	fi
	# every fable_grant call carries mission=
	while read -r call; do
		[ -n "$call" ] || continue
		case "$call" in *mission=*) ;; *) bad "$name: fable_grant without mission=: $call" ;; esac
	done < <(grep -oE 'fable_grant\([^)]*\)' "$f")
	# release-gate shows the committed diff too, so a commit cannot hide a change
	if [ "$name" = prime-swarm-release-gate ]; then
		case "$flat" in *'`git diff --stat <base> HEAD` (committed)'*'`git diff --stat <base>` (working tree'*) ;; *) bad "$name: gate hides the committed or the working-tree diff" ;; esac
	fi
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
# T8 attempt 4 regressions (1-7)
neg_case prime-swarm-graph 's/AND no task is `in_progress` //' "replan trigger ignores in_progress"
neg_case prime-swarm-graph 's/(the mission worktree is back/keep the task `in_progress` (the mission worktree is back/' "merge conflict keeps task in_progress or deletes worktree/branch"
neg_case prime-swarm-graph 's/set the task back to `pending` while `attempts` < 3 (at 3/leave the task while `attempts` < 3 (at 3/' "merge conflict has no retry path"
neg_case prime-swarm-graph 's/which includes a refused/which excludes a refused/' "refused init not a non-success retry"
neg_case prime-swarm-graph 's/`blocked(spec)`; the checker/`blocked(spec)`, as is a refused `init`: `blocked(spec)`; the checker/' "refused init mapped to blocked(spec)"
neg_case prime-swarm-graph 's/`verify.budget` `"exceeded"`/`verify.reason` `"exceeded"`/' "TAMPER/budget escalation not told apart by output fields"
neg_case prime-swarm-loop 's/\. NEVER$/. Prefer not to/' "prime-swarm-loop: Tier B rules may come from the target repo"
neg_case prime-swarm-architect "s/, never the target repo's copy//" "prime-swarm-architect: Tier B rules may come from the target repo"
neg_case prime-swarm-loop 's/never a spec block/or `blocked(spec)`/' "prime-swarm-loop: refused init not a non-success retry"
neg_case prime-swarm-loop 's/`verify.budget` is `"exceeded"`/`outcome.reason` is `"exceeded"`/' "prime-swarm-loop: TAMPER/budget escalation not told apart"
neg_case prime-swarm-loop 's/at most 3 runs per task in total/as often as needed/' "non-success retries unbounded"
neg_case prime-swarm-meta 's/, "PYTHONSAFEPATH": "1"//' "harness-select run without empty cwd + PYTHONSAFEPATH"
# T8 attempt 5 regressions (1-5)
neg_case prime-swarm-loop 's/if top and common: c.append(/if top and common: pass; c.extend(/' "write-scope check ignores prime worktree layout"
neg_case prime-swarm-loop 's/included) means NO commit/included) is noted/' "no Tier B check / zero-diff branch before commit"
neg_case prime-swarm-loop 's/`commits(...)` 0 = zero-diff/`commits(...)` 0 = commit anyway/' "no Tier B check / zero-diff branch before commit"
neg_case prime-swarm-loop 's/at most 3 explore runs in total/as many explore runs as needed/' "explore retries unbounded"
neg_case prime-swarm-loop 's/most 3 review runs per review round/many review runs as needed/' "review retries unbounded"
neg_case prime-swarm-graph 's/means NO commit and NO merge/means log it/' "no Tier B check (committed range) before commit"
neg_case prime-swarm-graph 's/or after a zero-diff PASS/and nothing else/' "no zero-diff PASS done branch"
neg_case prime-swarm-graph 's/set `done` directly/wait/' "no zero-diff PASS done branch"
neg_case prime-swarm-graph 's/Any other `escalated` (neither kind identifiable): `blocked(design)`/Any other `escalated`: leave it/' "unclassified escalated stays in_progress"
neg_case prime-swarm-graph 's/`blocked(design)`, the error in `note`, and report\. A merge/leave it, with the error in `note`. A merge/' "failed commit/merge stays in_progress"
neg_case prime-swarm-graph 's/at most 3 runs per review round/any number of runs/' "explore/review retries unbounded"
# T8 attempt 6 regressions
neg_case prime-swarm-loop 's/D + (base, "HEAD", "--"), //' "changed() ignores base..HEAD, the index or the working tree"
neg_case prime-swarm-loop 's/D + ("--cached", base, "--"), //' "changed() ignores base..HEAD, the index or the working tree"
neg_case prime-swarm-loop 's/if rules is None: raise RuntimeError/if rules is None: print/' "missing rules file not an explicit stop"
neg_case prime-swarm-loop 's/if p.returncode: raise RuntimeError(/if False: raise RuntimeError(/' "git helper ignores the exit code"
neg_case prime-swarm-loop 's/x != "@fix_plan.md"/True/' "@fix_plan.md not excluded from staging"
neg_case prime-swarm-loop 's/(exception) is fail closed: stop and report/(exception) is ignored/' "git failure not fail-closed"
neg_case prime-swarm-graph 's/`changed(<task worktree>, <init.base>)`/`changed(<task worktree>)`/' "no Tier B check (committed range) before commit"
neg_case prime-swarm-graph 's/Immediately before the merge also test `incoming(/Immediately before the merge also test `inbound(/' "no pre-merge incoming() check"
neg_case prime-swarm-release-gate 's/`git diff --stat <base> HEAD` (committed)/`git diff --stat <base>` (committed)/' "gate hides the committed or the working-tree diff"
neg_case prime-swarm-graph 's/A git error (exception, e.g. a missing worktree) is fail closed/A git error is retried/' "git failure not fail-closed"
neg_case prime-swarm-graph 's/replace("|", "\/")/replace("|", "")/' "note cells unsanitised / warnings and row count not checked"
neg_case prime-swarm-graph 's/STOP if `warnings` is non-empty/note `warnings` if non-empty/' "note cells unsanitised / warnings and row count not checked"
neg_case prime-swarm-graph 's/`metrics.nodes` differs from the/`metrics.width` differs from the/' "note cells unsanitised / warnings and row count not checked"
neg_case prime-swarm-graph 's/`swarm-explore`, at most 3 runs/`swarm-explore`/' "explore/review retries unbounded"
}

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
# (4) the write-scope snippet's definitions (up to its first print), extracted from the skill itself into a file
wdefs="$beh/ws_defs.py"
python3 -I - "$here/prime-swarm-loop/SKILL.md" "$wdefs" <<'PY'
import sys, textwrap
lines = open(sys.argv[1]).read().splitlines()
i = next(k for k, l in enumerate(lines) if l.strip().startswith("import json, os, fnmatch"))
j = next(k for k in range(i, len(lines)) if lines[k].strip().startswith("print("))
open(sys.argv[2], "w").write(textwrap.dedent("\n".join(lines[i:j])) + "\n")
PY
cat >"$beh/ws_driver.py" <<'PY'
import json, os, sys
exec(open(sys.argv[1]).read())
if sys.argv[2] == "protected":
    for label, path, want in json.loads(sys.argv[3]):
        got = protected(path)
        print("ok" if got == want else "FAIL", label, "->", got)
elif sys.argv[2] == "meta":
    ch = changed(sys.argv[3], sys.argv[4])
    print(json.dumps({"stageable": stageable(ch), "commits": commits(sys.argv[3], sys.argv[4])}))
elif sys.argv[2] == "incoming":
    try:
        print(json.dumps(incoming(sys.argv[3], sys.argv[4])))
    except (RuntimeError, ValueError):
        print("raised")
elif sys.argv[2] == "raises":
    try:
        changed(sys.argv[3], sys.argv[4])
        print("returned")
    except (RuntimeError, ValueError) as e:
        print("raised")
else:
    wt = sys.argv[3]
    ch = changed(wt, sys.argv[4])
    print(json.dumps({"changed": sorted(ch), "bad": sorted(x for x in ch if protected(os.path.join(wt, x)))}))
PY
# (4a) a target repo planting agent/write-scope-rules.json with no patterns must not empty Tier B
mkdir -p "$beh/repo/agent"
printf '{"suffix_patterns": [], "fixed_absolute_path_patterns": []}\n' >"$beh/repo/agent/write-scope-rules.json"
command rm -f "$beh/repo/json.py"
out="$(cd "$beh/repo" && PYTHONPATH="$here/swarm-adapter/src" HOME="$beh/home" python3 "$beh/ws_driver.py" "$wdefs" protected '[["planted rules","/x/agent/hooks/claude/gate.sh",true]]' 2>&1 || true)"
case "$out" in "ok planted rules -> True") echo "ok   behaviour loop: planted repo write-scope-rules.json ignored (hook path protected)" ;; *) bad "behaviour loop: Tier B check returned '$out'" ;; esac
# (4b) prime worktree layout (worktree_alloc: <repo parent>/.worktrees/<repo>/<slug>-<ts>) in a sandboxed HOME:
# fixed paths only name the main checkouts, so the worktree copies of .claude/settings*.json need the main-checkout twin
wsb="$(realpath "$beh")/ws"
whome="$wsb/home"
mkdir -p "$whome"
gitq() { env -u SWARM_WORKTREE_DIR -u GIT_DIR -u GIT_WORK_TREE HOME="$whome" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git -c commit.gpgsign=false -c user.name=t -c user.email=t@t "$@"; }
mkrepo() { # <org> <repo>
	local d="$whome/go/src/github.com/$1/$2"
	mkdir -p "$d/.claude" "$d/agent/hooks/claude" "$d/src"
	printf '{}\n' >"$d/.claude/settings.json"; printf '{}\n' >"$d/.claude/settings.local.json"; printf 'o\n' >"$d/.claude/other.json"
	printf 'a\n' >"$d/a.txt"; printf 'd\n' >"$d/del.txt"; printf 'x\n' >"$d/agent/hooks/claude/x.sh"; printf 'm\n' >"$d/src/main.go"
	gitq -C "$d" init -q && gitq -C "$d" add -A && gitq -C "$d" commit -qm init
	printf '%s\n' "$d"
}
mkwt() { # <repo dir> <slug>: a worktree exactly as swarm_adapter.worktree_alloc lays it out
	env -u SWARM_WORKTREE_DIR HOME="$whome" PYTHONPATH="$here/swarm-adapter/src" python3 -c \
		'import asyncio, sys, swarm_adapter as s; r = asyncio.run(s.worktree_alloc(sys.argv[2], "mission", cwd=sys.argv[1])); print(r["path"] if r["exit_code"] == 0 else "ERR " + str(r))' "$1" "$2"
}
dot="$(mkrepo kpango dotfiles)"; vald="$(mkrepo vdaas vald)"; oth="$(mkrepo other proj)"
wdot="$(mkwt "$dot" m-1)"; wvald="$(mkwt "$vald" m-1)"; woth="$(mkwt "$oth" m-1)"
case "$wdot$wvald$woth" in *ERR*) bad "behaviour loop: worktree_alloc failed: $wdot $wvald $woth" ;; esac
case "$wdot" in "$whome/go/src/github.com/kpango/.worktrees/dotfiles/m-1-"*) ;; *) bad "behaviour loop: unexpected worktree layout $wdot" ;; esac
cases="$(python3 -I - "$dot" "$wdot" "$wvald" "$woth" <<'PY'
import json, sys
dot, wdot, wvald, woth = sys.argv[1:5]
print(json.dumps([
    ["main checkout settings.json", dot + "/.claude/settings.json", True],
    ["prime dotfiles worktree settings.json", wdot + "/.claude/settings.json", True],
    ["prime dotfiles worktree settings.local.json", wdot + "/.claude/settings.local.json", True],
    ["prime vald worktree settings.local.json", wvald + "/.claude/settings.local.json", True],
    ["prime dotfiles worktree hooks shim (suffix rule)", wdot + "/agent/hooks/claude/x.sh", True],
    ["prime dotfiles worktree ordinary source", wdot + "/src/main.go", False],
    ["prime dotfiles worktree other .claude file", wdot + "/.claude/other.json", False],
    ["unrelated repo worktree settings.json", woth + "/.claude/settings.json", False],
]))
PY
)"
run_ws() { (cd "$beh" && env -u SWARM_WORKTREE_DIR HOME="$whome" PYTHONPATH="$here/swarm-adapter/src" python3 "$beh/ws_driver.py" "$@"); }
n_bad=0
while read -r line; do
	case "$line" in ok*) ;; *) bad "behaviour loop: prime worktree Tier B: $line"; n_bad=1 ;; esac
done < <(run_ws "$wdefs" protected "$cases" 2>&1)
if [ "$n_bad" -eq 0 ]; then echo "ok   behaviour loop: protected() on prime worktree layout (8 cases, incl. ordinary-file and unrelated-repo negatives)"; fi
# repro/negative: the old bare-realpath match misses the prime worktree copy, and protected() without the twin line fails the same cases
old="$(cd "$beh" && HOME="$whome" PYTHONPATH="$here/swarm-adapter/src" python3 - "$wdefs" "$wdot/.claude/settings.json" <<'PY'
import sys
exec(open(sys.argv[1]).read())
p = os.path.realpath(sys.argv[2])
print(any(fnmatch.fnmatch(p, g) for g in r["suffix_patterns"]) or any(fnmatch.fnmatch(p, g.replace("${HOME}", h)) for g in r["fixed_absolute_path_patterns"]))
PY
)"
if [ "$old" = "False" ]; then echo "ok   behaviour loop: bare realpath match misses the prime worktree settings.json (repro)"; else bad "behaviour loop: repro failed ('$old'), test would pass vacuously"; fi
sed '/if top and common/d' "$wdefs" >"$beh/ws_defs_notwin.py"
if run_ws "$beh/ws_defs_notwin.py" protected "$cases" 2>&1 | grep -q '^FAIL'; then
	echo "ok   behaviour loop: protected() without the main-checkout twin is detected (negative)"
else
	bad "behaviour loop: removing the twin lookup went undetected"
fi
# changed(): what a commit would stage, and the Tier B subset of it
chk() { # <label> <expected json>; worktree in $wt
	local got; got="$(run_ws "$wdefs" changed "$wt" "$wbase" 2>&1)"
	if [ "$got" = "$2" ]; then echo "ok   behaviour loop: $1"; else bad "behaviour loop: $1: got $got, want $2"; fi
}
wt="$wdot"; wbase="$(gitq -C "$wt" rev-parse HEAD)"
chk "clean worktree: changed() empty (zero-diff PASS has nothing to commit)" '{"changed": [], "bad": []}'
printf 'new\n' >"$wt/src/new.go"; command rm -f "$wt/del.txt"; printf 'a2\n' >>"$wt/a.txt"
chk "untracked + deleted + modified, no Tier B: all listed, none protected" '{"changed": ["a.txt", "del.txt", "src/new.go"], "bad": []}'
printf '{"x":1}\n' >"$wt/.claude/settings.json"
chk "modified .claude/settings.json in a prime worktree is caught" '{"changed": [".claude/settings.json", "a.txt", "del.txt", "src/new.go"], "bad": [".claude/settings.json"]}'
gitq -C "$wt" checkout -q -- .claude/settings.json
gitq -C "$wt" mv .claude/settings.local.json .claude/renamed.json
chk "rename away from a protected path: the old path is listed and caught" '{"changed": [".claude/renamed.json", ".claude/settings.local.json", "a.txt", "del.txt", "src/new.go"], "bad": [".claude/settings.local.json"]}'
printf 'hook\n' >"$wt/agent/hooks/claude/new-hook.sh"
chk "untracked file under agent/hooks/claude is caught by the suffix rule" '{"changed": [".claude/renamed.json", ".claude/settings.local.json", "a.txt", "agent/hooks/claude/new-hook.sh", "del.txt", "src/new.go"], "bad": [".claude/settings.local.json", "agent/hooks/claude/new-hook.sh"]}'
# (T8 attempt 6) the maker may COMMIT: committed Tier B changes are in the union (prime layout, worktree_alloc)
wc="$(mkwt "$dot" committed)"; cbase="$(gitq -C "$wc" rev-parse HEAD | cut -c1-12)"
printf '{"x":2}\n' >"$wc/.claude/settings.json"; gitq -C "$wc" add .claude/settings.json; gitq -C "$wc" commit -qm "maker commit"
printf 'package main\n' >"$wc/src/a.go"
if [ "$(run_ws "$wdefs" changed "$wc" "$cbase" 2>&1)" = '{"changed": [".claude/settings.json", "src/a.go"], "bad": [".claude/settings.json"]}' ]; then
	echo "ok   behaviour loop: maker-committed .claude/settings.json is in changed() and caught (base = 12-hex init.base)"
else
	bad "behaviour loop: committed Tier B change not detected: $(run_ws "$wdefs" changed "$wc" "$cbase" 2>&1)"
fi
# (T8 attempt 7) maker commits a Tier B change, then restores index AND working tree to base: only base..HEAD still shows it
wr="$(mkwt "$dot" revert)"; rbase="$(gitq -C "$wr" rev-parse HEAD | cut -c1-12)"
printf 'evil\n' >"$wr/agent/hooks/claude/x.sh"; gitq -C "$wr" add agent/hooks/claude/x.sh; gitq -C "$wr" commit -qm "maker commit"
gitq -C "$wr" restore --source="$rbase" --staged --worktree agent/hooks/claude/x.sh
rwant='{"changed": ["agent/hooks/claude/x.sh"], "bad": ["agent/hooks/claude/x.sh"]}'
if [ -z "$(gitq -C "$wr" diff --name-only "$rbase" --)$(gitq -C "$wr" diff --cached --name-only "$rbase" --)" ] && [ "$(gitq -C "$wr" show HEAD:agent/hooks/claude/x.sh)" = evil ] && [ "$(run_ws "$wdefs" changed "$wr" "$rbase" 2>&1)" = "$rwant" ]; then
	echo "ok   behaviour loop: committed-then-reverted Tier B change (clean tree, HEAD holds it) is in changed() and caught"
else
	bad "behaviour loop: committed-then-reverted Tier B change hidden: $(run_ws "$wdefs" changed "$wr" "$rbase" 2>&1)"
fi
# staged only: index differs from base, HEAD and working tree equal base
ws_="$(mkwt "$dot" staged)"; sbase="$(gitq -C "$ws_" rev-parse HEAD | cut -c1-12)"
printf 'evil\n' >"$ws_/agent/hooks/claude/x.sh"; gitq -C "$ws_" add agent/hooks/claude/x.sh; printf 'x\n' >"$ws_/agent/hooks/claude/x.sh"
if [ "$(gitq -C "$ws_" diff --name-only "$sbase" --)" = "" ] && [ "$(run_ws "$wdefs" changed "$ws_" "$sbase" 2>&1)" = "$rwant" ]; then
	echo "ok   behaviour loop: staged-only Tier B change (working tree restored) is in changed() and caught"
else
	bad "behaviour loop: staged-only Tier B change hidden: $(run_ws "$wdefs" changed "$ws_" "$sbase" 2>&1)"
fi
# negatives: the old working-tree-only changed(), and each half of the new union alone, hides its case
sed 's/^\( *qs = \).*/\1(D + (base, "--"), ("ls-files", "--others", "--exclude-standard", "-z"))/' "$wdefs" >"$beh/ws_defs_wtonly.py"
sed 's/D + (base, "HEAD", "--"), //' "$wdefs" >"$beh/ws_defs_nohead.py"
sed 's/D + ("--cached", base, "--"), //' "$wdefs" >"$beh/ws_defs_nocached.py"
for m in wtonly nohead nocached; do cmp -s "$wdefs" "$beh/ws_defs_$m.py" && bad "behaviour loop: mutant $m identical to the skill"; done
if run_ws "$beh/ws_defs_wtonly.py" changed "$wr" "$rbase" 2>&1 | grep -q '"bad": \[\]' && run_ws "$beh/ws_defs_wtonly.py" changed "$ws_" "$sbase" 2>&1 | grep -q '"bad": \[\]'; then
	echo "ok   behaviour loop: working-tree-only changed() hides the committed and the staged Tier B change (negative)"
else
	bad "behaviour loop: working-tree-only mutant not detected"
fi
if run_ws "$beh/ws_defs_nohead.py" changed "$wr" "$rbase" 2>&1 | grep -q '"bad": \[\]'; then echo "ok   behaviour loop: without base..HEAD the committed-then-reverted change is hidden (negative)"; else bad "behaviour loop: no-base..HEAD mutant not detected"; fi
if run_ws "$beh/ws_defs_nocached.py" changed "$ws_" "$sbase" 2>&1 | grep -q '"bad": \[\]'; then echo "ok   behaviour loop: without the index diff the staged-only change is hidden (negative)"; else bad "behaviour loop: no-index mutant not detected"; fi
# graph pre-merge: incoming() lists what merging the task branch brings (mission worktree vs task branch)
wm="$(mkwt "$dot" mission2)"; tbr="$(gitq -C "$wr" rev-parse --abbrev-ref HEAD)"; cbr="$(gitq -C "$wt" rev-parse --abbrev-ref HEAD)"
if [ "$(run_ws "$wdefs" incoming "$wm" "$tbr" 2>&1)" = '["agent/hooks/claude/x.sh"]' ] && [ "$(run_ws "$wdefs" incoming "$wm" "$cbr" 2>&1)" = '[]' ] && [ "$(run_ws "$wdefs" incoming "$wm" "-x" 2>&1)" = raised ] && [ "$(run_ws "$wdefs" incoming "$wsb/no-such-worktree" "$tbr" 2>&1)" = raised ]; then
	echo "ok   behaviour graph: incoming() lists the task branch's committed Tier B path; clean branch empty; bad branch / missing worktree raise"
else
	bad "behaviour graph: incoming() wrong: $(run_ws "$wdefs" incoming "$wm" "$tbr" 2>&1) / $(run_ws "$wdefs" incoming "$wm" "$cbr" 2>&1)"
fi
# no write-scope-rules.json anywhere (adapter copied outside any agent/ dir, empty HOME): explicit stop, not json.load(None)
mkdir -p "$beh/noagent" "$beh/emptyhome/.prime/agent"
command cp -r "$here/swarm-adapter/src/swarm_adapter" "$beh/noagent/swarm_adapter"
run_norules() { (cd "$beh" && env -u SWARM_WORKTREE_DIR HOME="$beh/emptyhome" PYTHONPATH="$beh/noagent" python3 "$beh/ws_driver.py" "$@"); }
nr="$(run_norules "$wdefs" protected '[]' 2>&1 || true)"
case "$nr" in *'RuntimeError: no write-scope-rules.json: every edit is protected'*) nrok=1 ;; *) nrok=0 ;; esac
if [ "$nrok" = 1 ]; then
	echo "ok   behaviour loop: no write-scope-rules.json anywhere stops with an explicit message (ask the human)"
else
	bad "behaviour loop: missing rules did not stop explicitly: $(printf '%s' "$nr" | tail -n 1)"
fi
sed '/^ *if rules is None: raise/d' "$wdefs" >"$beh/ws_defs_norulescheck.py"
nr="$(run_norules "$beh/ws_defs_norulescheck.py" protected '[]' 2>&1 || true)"
if printf '%s' "$nr" | grep -q 'TypeError'; then echo "ok   behaviour loop: without the rules check, a missing file is a bare TypeError (negative)"; else bad "behaviour loop: no-rules-check mutant not detected"; fi
command cp "$repo/agent/write-scope-rules.json" "$beh/emptyhome/.prime/agent/write-scope-rules.json"
if [ "$(run_norules "$wdefs" protected '[["installed fallback rules","/x/agent/hooks/claude/gate.sh",true]]' 2>&1)" = "ok installed fallback rules -> True" ]; then echo "ok   behaviour loop: the installed ~/.prime/agent copy is used when the dotfiles copy is not found"; else bad "behaviour loop: fallback rules not used"; fi
if [ "$(run_ws "$wdefs" meta "$wc" "$cbase" 2>&1)" = '{"stageable": [".claude/settings.json", "src/a.go"], "commits": 1}' ]; then
	echo "ok   behaviour loop: commits() > 0 after a maker commit (not a zero-diff PASS)"
else
	bad "behaviour loop: commits()/stageable wrong: $(run_ws "$wdefs" meta "$wc" "$cbase" 2>&1)"
fi
# fail closed: a missing worktree raises; the old helper (exit code ignored) returned an empty list
if [ "$(run_ws "$wdefs" raises "$wsb/no-such-worktree" "$cbase" 2>&1)" = "raised" ]; then echo "ok   behaviour loop: changed() on a missing worktree raises (fail closed)"; else bad "behaviour loop: missing worktree did not raise"; fi
if [ "$(run_ws "$wdefs" raises "$wc" "-x" 2>&1)" = "raised" ]; then echo "ok   behaviour loop: changed() with a non-hex base raises"; else bad "behaviour loop: bad base did not raise"; fi
sed 's/if p.returncode: raise/if False: raise/' "$wdefs" >"$beh/ws_defs_open.py"
if [ "$(run_ws "$beh/ws_defs_open.py" raises "$wsb/no-such-worktree" "$cbase" 2>&1)" = "returned" ]; then
	echo "ok   behaviour loop: ignoring the git exit code fails open on a missing worktree (negative)"
else
	bad "behaviour loop: fail-open mutant not detected"
fi
# @fix_plan.md (mission-init.sh) is untracked: it is in changed() (Tier B still sees it) but never stageable, so zero-diff PASS holds
wf="$(mkwt "$dot" plan)"; fbase="$(gitq -C "$wf" rev-parse HEAD | cut -c1-12)"
printf '# plan\n' >"$wf/@fix_plan.md"
if [ "$(run_ws "$wdefs" changed "$wf" "$fbase" 2>&1)" = '{"changed": ["@fix_plan.md"], "bad": []}' ] && [ "$(run_ws "$wdefs" meta "$wf" "$fbase" 2>&1)" = '{"stageable": [], "commits": 0}' ]; then
	echo "ok   behaviour loop: untracked @fix_plan.md is not stageable, zero-diff PASS still holds"
else
	bad "behaviour loop: @fix_plan.md handling wrong: $(run_ws "$wdefs" meta "$wf" "$fbase" 2>&1)"
fi
sed 's/x != "@fix_plan.md"/True/' "$wdefs" >"$beh/ws_defs_plan.py"
if [ "$(run_ws "$beh/ws_defs_plan.py" meta "$wf" "$fbase" 2>&1)" = '{"stageable": ["@fix_plan.md"], "commits": 0}' ]; then
	echo "ok   behaviour loop: without the exclusion @fix_plan.md would be staged (negative)"
else
	bad "behaviour loop: @fix_plan.md mutant not detected"
fi
# the zero-diff facts the skills rely on: commit exits non-zero and a no-op merge creates no commit
zt="$(mkwt "$dot" zero)"
zb="$(gitq -C "$zt" rev-parse --abbrev-ref HEAD)"
if gitq -C "$zt" commit -q -m x >/dev/null 2>&1; then bad "behaviour zero-diff: commit unexpectedly succeeded"; else echo "ok   behaviour zero-diff: git commit with nothing staged exits non-zero"; fi
before="$(gitq -C "$dot" rev-parse HEAD)"
nm="$(gitq -C "$dot" merge --no-ff "$zb" 2>&1 || true)"
if [ "$(gitq -C "$dot" rev-parse HEAD)" = "$before" ] && printf '%s' "$nm" | grep -q 'Already up to date'; then
	echo "ok   behaviour zero-diff: no-op merge --no-ff creates no merge commit (Already up to date)"
else
	bad "behaviour zero-diff: merge facts changed: $nm"
fi
zbase="$(gitq -C "$zt" rev-parse HEAD | cut -c1-12)"
if [ "$(run_ws "$wdefs" meta "$zt" "$zbase" 2>&1)" = '{"stageable": [], "commits": 0}' ]; then echo "ok   behaviour zero-diff: untouched task worktree has empty stageable() and commits() 0"; else bad "behaviour zero-diff: meta not empty"; fi
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
