#!/usr/bin/env bash
# PostToolUse:Write|Edit hook — async post-write lint trigger
set -euo pipefail

INPUT=$(cat)

if ! command -v jq &>/dev/null; then
    exit 0
fi

FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)
[[ -z "$FILE_PATH" ]] && exit 0

EXT="${FILE_PATH##*.}"

# Log the write for audit trail
LOG_DIR="$HOME/.claude/session-data"
mkdir -p "$LOG_DIR"
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
echo "[$(date '+%H:%M:%S')] write: $FILE_PATH" >> "$LOG_DIR/${SESSION_ID:0:8}-writes.log" 2>/dev/null || true

# Async validation for config and script files
case "$EXT" in
    json)
        if command -v python3 &>/dev/null; then
            python3 -m json.tool "$FILE_PATH" > /dev/null 2>&1 || \
                echo "WARNING: $FILE_PATH may have invalid JSON" >&2
        fi
        ;;
    yaml|yml)
        if command -v python3 &>/dev/null; then
            python3 -c "
import sys
try:
    import yaml
    yaml.safe_load(open(sys.argv[1]))
except ImportError:
    pass
except Exception as e:
    print(f'WARNING: {sys.argv[1]} may have invalid YAML: {e}', file=sys.stderr)
" "$FILE_PATH" 2>&1 || true
        fi
        ;;
    toml)
        if python3 -c "import tomllib" 2>/dev/null; then
            python3 -c "
import sys, tomllib
try:
    tomllib.load(open(sys.argv[1], 'rb'))
except Exception as e:
    print(f'WARNING: {sys.argv[1]} may have invalid TOML: {e}', file=sys.stderr)
" "$FILE_PATH" 2>&1 || true
        fi
        ;;
    sh|bash)
        bash -n -- "$FILE_PATH" 2>&1 || \
            echo "WARNING: $FILE_PATH has shell syntax errors" >&2
        ;;
    go)
        # agy/hooks/post-edit-lint.sh 同様 gofmt を使うが、claude側は読み取り専用方針
        # (agyは -w で自動整形するが、claudeは書き込みを警告表示に留める既存の意図的な差異)
        # のため -l (要整形ファイル一覧、パース不能なら stderr にエラー) に留める。
        if command -v gofmt &>/dev/null; then
            ERR=$(gofmt -l -- "$FILE_PATH" 2>&1 >/dev/null) || true
            [[ -n "$ERR" ]] && echo "WARNING: $FILE_PATH has Go syntax errors: $ERR" >&2
        fi
        ;;
    py)
        if command -v python3 &>/dev/null; then
            PYERR=$(python3 -m py_compile -- "$FILE_PATH" 2>&1 >/dev/null) || true
            [[ -n "$PYERR" ]] && echo "WARNING: $FILE_PATH may have invalid Python: $PYERR" >&2
        fi
        ;;
esac

exit 0
