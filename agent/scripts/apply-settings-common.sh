#!/usr/bin/env bash
# agent/settings-common.json の shared_values・現在選択中の model_profiles を、claude/pi/agy の
# 実settings.jsonへ明示的に反映する。test-settings-common.sh は検証のみ(書き込みなし)だが、
# 本スクリプトは実際にファイルを書き換える唯一の箇所であり、自動実行はされない
# (swarm-*系フックからも呼ばれない、常にユーザー/エージェントが明示的に実行する設計)。
#
# 全キーの上書きではなく、agent/settings-common.jsonに登録された特定のjson_pointerだけを
# jq(unicodeをエスケープせず、当該フィールド以外の整形を変えない)で書き換える。
# Python json.load+dumpは非ASCII文字(em-dash等)を\uXXXXへエスケープし全体を再整形して
# しまうため使わない(検証中に実際に発生させて確認した副作用、コミット直前にgit checkoutで
# 復旧した実例がある)。
#
# usage:
#   agent/scripts/apply-settings-common.sh --dry-run   # 何が変わるかを表示するだけ(既定)
#   agent/scripts/apply-settings-common.sh --apply      # 実際に書き込む
set -euo pipefail

ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMMON="$ROOT/agent/settings-common.json"

MODE="dry-run"
case "${1:-}" in
    --apply) MODE="apply" ;;
    --dry-run|"") MODE="dry-run" ;;
    *) echo "usage: $0 [--dry-run|--apply]" >&2; exit 2 ;;
esac

[ -f "$COMMON" ] || { echo "FAIL: $COMMON not found" >&2; exit 1; }

# json_pointer("/a/b/c") -> jq path式(".a.b.c") へ変換する。全キーがドット/ブラケット不要な
# 単純な識別子であることを前提とする(現状のshared_values/model_profilesのpointerは全てそう)。
pointer_to_jq_path() {
    local pointer="$1" jq_path=""
    IFS='/' read -ra parts <<<"$pointer"
    for p in "${parts[@]}"; do
        [ -z "$p" ] && continue
        jq_path="${jq_path}.\"${p}\""
    done
    printf '%s' "$jq_path"
}

apply_one() {
    local label="$1" target_file="$2" pointer="$3" value_json="$4"
    local jq_path
    jq_path="$(pointer_to_jq_path "$pointer")"

    local current_json
    current_json=$(jq -c "$jq_path // \"__MISSING__\"" "$target_file" 2>/dev/null || echo '"__READ_ERROR__"')
    local expected_json
    expected_json=$(jq -c . <<<"$value_json")

    if [ "$current_json" == "$expected_json" ]; then
        echo "  = $label: 既に一致 ($target_file$pointer)"
        return
    fi

    echo "  * $label: $target_file$pointer"
    echo "      現在値: $current_json"
    echo "      反映値: $expected_json"

    if [ "$MODE" == "apply" ]; then
        local tmp
        tmp=$(mktemp)
        jq --argjson v "$expected_json" "$jq_path = \$v" "$target_file" > "$tmp"
        mv "$tmp" "$target_file"
        echo "      -> 反映しました"
    fi
}

echo "=== apply-settings-common.sh ($MODE) ==="
echo

echo "[ shared_values ]"
manifest_extract="$(python3 -c "
import json
d = json.load(open('$COMMON'))
for key, entry in d['shared_values'].items():
    value_json = json.dumps(entry['value'])
    for target in entry['targets']:
        print(f\"{key}|{target}|{entry['json_pointer']}|{value_json}\")
")"
mapfile -t shared_lines <<<"$manifest_extract"
for line in "${shared_lines[@]}"; do
    IFS='|' read -r key target pointer value_json <<<"$line"
    apply_one "$key/$target" "$ROOT/agent/harnesses/$target/settings.json" "$pointer" "$value_json"
done

echo
echo "[ model_profiles.current ]"
profile_extract="$(python3 -c "
import json
d = json.load(open('$COMMON'))
current = d['model_profiles']['current']
profile = d['model_profiles']['profiles'][current]
for tool in ('claude', 'pi', 'agy'):
    entry = profile.get(tool)
    if not entry:
        continue
    print(f\"{tool}|{entry['json_pointer']}|{json.dumps(entry['value'])}\")
")"
mapfile -t profile_lines <<<"$profile_extract"
for line in "${profile_lines[@]}"; do
    IFS='|' read -r tool pointer value_json <<<"$line"
    apply_one "model_profile/$tool" "$ROOT/agent/harnesses/$tool/settings.json" "$pointer" "$value_json"
done

echo
if [ "$MODE" == "dry-run" ]; then
    echo "dry-run完了。実際に反映するには --apply を付けて再実行してください。"
else
    echo "apply完了。agent/scripts/test-settings-common.sh で反映結果を確認してください。"
fi
