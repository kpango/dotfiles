#!/usr/bin/env bash
set -euo pipefail
cd -P "$(dirname "${BASH_SOURCE[0]}")/../.."

python3 -E - <<'PY'
import json
from pathlib import Path


def load(path):
    return json.loads(Path(path).read_text())


stdio = {'command': 'trail', 'args': ['mcp']}
assert load('agent/project/claude/trail-mcp.json') == {'type': 'stdio', **stdio}
assert load('.gemini/settings.json')['mcpServers']['trail'] == stdio
opencode_trail = load('opencode.json')['mcp']['trail']
assert opencode_trail['type'] == 'local'
assert opencode_trail['command'] == ['trail', 'mcp']
assert isinstance(opencode_trail['enabled'], bool), 'OpenCode Trail enabled must be a boolean'
agy = load('agent/harnesses/agy/mcp_config.json')['mcpServers']
assert agy.pop('trail') == stdio
assert load('agent/harnesses/agy/settings.json')['mcpServers'] == agy
pi_trail = load('agent/harnesses/pi/mcp.json')['mcpServers']['trail']
assert pi_trail['command'] == stdio['command'] and pi_trail['args'] == stdio['args']

manifest = load('agent/sync-manifest.json')['entries']
links = {(entry.get('canonical'), target['path']) for entry in manifest
         for target in entry['targets'].values() if target.get('mode') == 'live-symlink'}
assert {
    ('agent/harnesses/agy/settings.json', '$HOME/.agy/settings.json'),
    ('agent/harnesses/agy/settings.json', '$HOME/.gemini/settings.json'),
    ('agent/harnesses/agy/mcp_config.json', '$HOME/.agy/mcp_config.json'),
    ('agent/harnesses/agy/mcp_config.json', '$HOME/.gemini/config/mcp_config.json'),
    ('agent/harnesses/pi/mcp.json', '$HOME/.pi/agent/mcp.json'),
}.issubset(links), 'Agy/Pi sync manifest does not cover deployed settings and MCP links'
PY

python3 agent/scripts/gen-harness-parity.py --check

fixture=$(mktemp -d)
trap 'rm -rf -- "$fixture"' EXIT
for file in \
    agent/scripts/gen-harness-parity.py \
    agent/project/claude/settings.json agent/project/claude/trail-mcp.json \
    agent/harnesses/agy/{mcp_config,settings}.json \
    agent/harnesses/pi/mcp.json \
    .claude/settings.json .gemini/settings.json opencode.json; do
    mkdir -p "$fixture/$(dirname "$file")"
    cp -- "$file" "$fixture/$file"
done
(
    cd "$fixture"
    printf '%s\n' '{"disabledMcpjsonServers":["trail"]}' >.claude/settings.local.json
    printf '%s\n' '{"mcp":{"trail":{"type":"local","enabled":false}},"permission":{"bash":"deny"}}' >opencode.json
    printf '%s\n' '{"mcpServers":{"other":{"command":"fixture"}},"security":{"disableYoloMode":true}}' >.gemini/settings.json
    cp -- opencode.json before-opencode.json
    if python3 agent/scripts/gen-harness-parity.py --check; then
        echo "expected config drift to fail --check" >&2
        exit 1
    fi
    cmp before-opencode.json opencode.json
    python3 agent/scripts/gen-harness-parity.py --write
    python3 -E - <<'PY'
import json
from pathlib import Path

opencode = json.loads(Path('opencode.json').read_text())
assert opencode['permission'] == {'bash': 'deny'}
assert opencode['mcp']['trail'] == {
    'type': 'local', 'enabled': False, 'command': ['trail', 'mcp'],
}
gemini = json.loads(Path('.gemini/settings.json').read_text())
assert gemini['security'] == {'disableYoloMode': True}
assert gemini['mcpServers']['trail'] == {'command': 'trail', 'args': ['mcp']}
assert gemini['mcpServers']['other'] == {'command': 'fixture'}
assert Path('.claude/settings.local.json').read_text() == '{"disabledMcpjsonServers":["trail"]}\n'
PY
    python3 agent/scripts/gen-harness-parity.py --check
    cp -- opencode.json valid-opencode.json
    sed 's/"enabled": false/"enabled": "false"/' valid-opencode.json >opencode.json
    cp -- opencode.json invalid-opencode.json
    for mode in --check --write; do
        if python3 agent/scripts/gen-harness-parity.py "$mode" >validation.log 2>&1; then
            echo "string-valued OpenCode enabled must be rejected in $mode" >&2
            exit 1
        fi
        grep -F 'OpenCode Trail enabled must be a boolean' validation.log
        cmp invalid-opencode.json opencode.json
    done
    mv -- valid-opencode.json opencode.json
    ln -s missing-mcp.json .mcp.json
    if python3 agent/scripts/gen-harness-parity.py --check; then
        echo "dangling root MCP link must be rejected" >&2
        exit 1
    fi
    rm -- .mcp.json
    cp -- .claude/settings.json before-claude.json
    printf '%s\n' '[]' >agent/project/claude/settings.json
    if python3 agent/scripts/gen-harness-parity.py --write; then
        echo "invalid Claude project settings must not be projected" >&2
        exit 1
    fi
    cmp before-claude.json .claude/settings.json
    cp -- before-claude.json agent/project/claude/settings.json
    mv -- agent/harnesses/agy/settings.json before-agy.json
    if python3 agent/scripts/gen-harness-parity.py --write; then
        echo "missing Agy base settings must not be replaced with MCP-only settings" >&2
        exit 1
    fi
    test ! -e agent/harnesses/agy/settings.json
    mv -- before-agy.json agent/harnesses/agy/settings.json
    mv -- .claude/settings.json before-claude.json
    mv -- .gemini before-gemini
    if python3 agent/scripts/gen-harness-parity.py --write; then
        echo "missing native settings must fail before writing any output" >&2
        exit 1
    fi
    test ! -e .claude/settings.json
    mv -- before-gemini .gemini
    mv -- opencode.json before-opencode.json
    if python3 agent/scripts/gen-harness-parity.py --write; then
        echo "missing OpenCode settings must fail before writing any output" >&2
        exit 1
    fi
    test ! -e .claude/settings.json
    test ! -e opencode.json
    mv -- before-opencode.json opencode.json
    mv -- before-claude.json .claude/settings.json
    printf '%s\n' '{"mcp":{"trail":{"type":"remote","url":"https://example.invalid"}}}' >opencode.json
    cp -- opencode.json before-opencode.json
    if python3 agent/scripts/gen-harness-parity.py --write; then
        echo "conflicting Trail transport must not be overwritten" >&2
        exit 1
    fi
    cmp before-opencode.json opencode.json
    printf '%s\n' '{"mcp":{"trail":{"enabled":false}}}' >opencode.json
    python3 - <<'PY'
import json
from pathlib import Path

path = Path('agent/harnesses/agy/mcp_config.json')
config = json.loads(path.read_text())
config['mcpServers']['trail']['command'] = 'unexpected-command'
path.write_text(json.dumps(config))
PY
    if python3 agent/scripts/gen-harness-parity.py --write; then
        echo "unexpected Trail command must not be projected" >&2
        exit 1
    fi
)
printf '%s\n' 'test-harness-parity: all assertions passed'
