#!/usr/bin/env bash
# PostToolUse:Write|Edit hook — Vald Law 3/4/5 static check on .go files
set -euo pipefail

INPUT=$(cat || true)

FILE_PATH=$(python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0
[[ "${FILE_PATH##*.}" != "go" ]] && exit 0
[[ ! -f "$FILE_PATH" ]] && exit 0

VIOLATIONS=()

# Law 3: panic! or log.Fatal
if grep -nE '\bpanic\(|log\.Fatal' "$FILE_PATH" 2>/dev/null | grep -qv '^\s*//'; then
    HITS=$(grep -nE '\bpanic\(|log\.Fatal' "$FILE_PATH" 2>/dev/null | grep -v '^\s*//' | head -3 | sed 's/^/  /')
    VIOLATIONS+=("Law 3 (no panic/log.Fatal):\n${HITS}")
fi

# Law 4: discarded errors
if grep -nE '^\s*_ = ' "$FILE_PATH" 2>/dev/null | grep -qv '^\s*//'; then
    HITS=$(grep -nE '^\s*_ = ' "$FILE_PATH" 2>/dev/null | grep -v '^\s*//' | head -3 | sed 's/^/  /')
    VIOLATIONS+=("Law 4 (no _ = err):\n${HITS}")
fi

# Law 5: stdlib log/errors/sync/strings imports
if grep -qE '"(log|errors|sync|strings)"' "$FILE_PATH" 2>/dev/null; then
    HITS=$(grep -nE '"(log|errors|sync|strings)"' "$FILE_PATH" 2>/dev/null | head -3 | sed 's/^/  /')
    VIOLATIONS+=("Law 5 (use internal/* not stdlib): ${HITS}")
fi

[[ ${#VIOLATIONS[@]} -eq 0 ]] && exit 0

MSG="Vald Law violation(s) in ${FILE_PATH##*/}:"
for v in "${VIOLATIONS[@]}"; do
    MSG="${MSG}\n${v}"
done
MSG="${MSG}\nFix before committing: use internal/errors, internal/sync, internal/strings, internal/log"

python3 -c "
import json, sys
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': sys.argv[1]
    }
}))
" "$(printf '%b' "$MSG")"

exit 0
