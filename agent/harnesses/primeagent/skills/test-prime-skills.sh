#!/usr/bin/env bash
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
	done < <(grep -oE 'swarm_adapter\.[a-z_]+' "$f" | sed 's/^swarm_adapter\.//' | sort -u)

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

# negative self-test: a misspelled machine name must make the static checks FAIL
neg="$(mktemp -d "${TMPDIR:-/tmp}/prime-skills-neg.XXXXXX")"
command cp -r "$here"/prime-swarm-* "$neg"/
# shellcheck disable=SC2016
sed -i 's/`swarm-implement`/`swarm-implment`/' "$neg/prime-swarm-loop/SKILL.md"
neg_out="$("$here/test-prime-skills.sh" --static-only "$neg" 2>&1 || true)"
if printf '%s\n' "$neg_out" | grep -q "unknown machine/skill 'swarm-implment'"; then
	echo "ok   negative self-test (misspelled machine rejected)"
else
	bad "negative self-test: misspelled machine name was NOT detected"
fi
find "$neg" -delete

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
