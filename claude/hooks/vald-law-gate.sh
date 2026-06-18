#!/usr/bin/env bash
# PreToolUse:Write|Edit hook — Vald Law 1: no direct edits to generated files
set -euo pipefail

INPUT=$(cat || true)

FILE_PATH=$(python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" <<< "$INPUT" 2>/dev/null || true)

[[ -z "$FILE_PATH" ]] && exit 0

if echo "$FILE_PATH" | grep -qE '\.(pb|vtproto\.pb)\.go$|_grpc\.pb\.go$'; then
    python3 -c "
import json
msg = {
    'decision': 'block',
    'reason': 'Vald Law 1: Direct edit of generated file is forbidden. Edit .proto in apis/proto/v1/ and run: make proto/all'
}
print(json.dumps(msg))
"
    exit 2
fi

exit 0
