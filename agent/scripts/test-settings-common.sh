#!/usr/bin/env bash
# agent/settings-common.json に登録した「claude/pi/agyのsettings.jsonで値まで一致するキー」および
# 現在選択中のmodel_profileが、各ツールの実settings.jsonと一致しているかを検証する(drift検出)。
# settings.json自体は各ツールの実ファイルが正典であり、本スクリプトは書き換えを一切行わない
# (自動修正が必要な場合は agent/scripts/apply-settings-common.sh を明示的に実行する)。
#
# usage: agent/scripts/test-settings-common.sh
# exit: 0 = 全entry一致, 1 = 1件以上drift
set -uo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMMON="$ROOT/agent/settings-common.json"
fail=0

if [ ! -f "$COMMON" ]; then
    echo "FAIL: $COMMON not found" >&2
    exit 1
fi

check_pointer() {
    local label="$1" file="$2" pointer="$3" expected_json="$4"
    local actual_json
    actual_json=$(python3 -c "
import json, sys
try:
    d = json.load(open('$file'))
except Exception as e:
    print('__PARSE_ERROR__:' + str(e))
    sys.exit(0)
parts = [p for p in '$pointer'.split('/') if p]
cur = d
try:
    for p in parts:
        cur = cur[p]
except (KeyError, TypeError, IndexError):
    print('__MISSING__')
    sys.exit(0)
print(json.dumps(cur, sort_keys=True))
" 2>&1)
    if [[ "$actual_json" == "__PARSE_ERROR__:"* ]]; then
        echo "FAIL: $label: $file の読み込みに失敗($actual_json)" >&2
        fail=$((fail + 1))
        return
    fi
    if [[ "$actual_json" == "__MISSING__" ]]; then
        echo "FAIL: $label: $file に $pointer が存在しない" >&2
        fail=$((fail + 1))
        return
    fi
    local expected_normalized
    expected_normalized=$(python3 -c "import json; print(json.dumps(json.loads('''$expected_json'''), sort_keys=True))" 2>&1)
    if [[ "$actual_json" != "$expected_normalized" ]]; then
        echo "FAIL: $label: $file の $pointer が agent/settings-common.json と乖離している" >&2
        echo "  expected: $expected_normalized" >&2
        echo "  actual:   $actual_json" >&2
        fail=$((fail + 1))
        return
    fi
    echo "PASS: $label ($file$pointer)"
}

# --- shared_values ---
manifest_extract="$(python3 -c "
import json
d = json.load(open('$COMMON'))
for key, entry in d['shared_values'].items():
    value_json = json.dumps(entry['value'])
    for target in entry['targets']:
        print(f\"{key}|{target}|{entry['json_pointer']}|{value_json}\")
" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    echo "FAIL: settings-common.json のパースに失敗(shared_values)" >&2
    echo "$manifest_extract" >&2
    exit 1
fi
mapfile -t shared_lines <<<"$manifest_extract"

for line in "${shared_lines[@]}"; do
    IFS='|' read -r key target pointer value_json <<<"$line"
    target_file="$ROOT/agent/harnesses/$target/settings.json"
    check_pointer "$key/$target" "$target_file" "$pointer" "$value_json"
done

# --- model_profiles.current ---
current_profile_extract="$(python3 -c "
import json
d = json.load(open('$COMMON'))
current = d['model_profiles']['current']
profile = d['model_profiles']['profiles'][current]
for tool in ('claude', 'pi', 'agy'):
    entry = profile.get(tool)
    if not entry:
        continue
    print(f\"{tool}|{entry['json_pointer']}|{json.dumps(entry['value'])}\")
" 2>&1)"
status=$?
if [ "$status" -ne 0 ]; then
    echo "FAIL: settings-common.json のパースに失敗(model_profiles)" >&2
    echo "$current_profile_extract" >&2
    exit 1
fi
mapfile -t profile_lines <<<"$current_profile_extract"

for line in "${profile_lines[@]}"; do
    IFS='|' read -r tool pointer value_json <<<"$line"
    target_file="$ROOT/agent/harnesses/$tool/settings.json"
    check_pointer "model_profile/$tool" "$target_file" "$pointer" "$value_json"
done

echo "---"
if [ "$fail" -gt 0 ]; then
    echo "test-settings-common: $fail 件のdriftあり(agent/settings-common.jsonとの不一致)" >&2
    exit 1
fi
echo "test-settings-common: 全entry一致"
exit 0
