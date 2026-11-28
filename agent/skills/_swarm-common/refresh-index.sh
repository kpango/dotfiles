#!/usr/bin/env bash
# SWARM.md を編集したら実行する。CORE.md の「節インデックス」の行範囲を SWARM.md の実見出しから再生成する。
# 節の説明文(2列目)は CORE.md の既存行を保持する。SWARM.md に無い節番号の行は error。
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
swarm="$(cd "$here/../.." && pwd -P)/SWARM.md"
core="$here/CORE.md"
total="$(wc -l <"$swarm")"

# 「## N.」見出しの行番号を N ごとに収集 (行頭 ## のみ。### は含めない)
mapfile -t heads < <(grep -nE '^## [0-9]+\.' "$swarm" | sed -E 's/^([0-9]+):## ([0-9]+)\..*/\2 \1/')
declare -A start
order=()
for h in "${heads[@]}"; do set -- $h; start[$1]=$2; order+=("$1"); done

tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
matched=0
while IFS= read -r line; do
  # 列整形のため「§N」直後と行範囲後の空白は可変長。旧来の固定 1 空白 regex は
  # 整形済み CORE.md に一致せず、全行を素通ししたまま exit 0 で「refreshed」と
  # 表示する無言の no-op になっていた(2026-11-21 layer-integration で発覚)。
  if [[ "$line" =~ ^(\|\ §[0-9]+\ +\|.*\| )([0-9]+-[0-9]+)( +\|)$ ]]; then
    n="$(printf '%s' "$line" | sed -E 's/^\|\ §([0-9]+).*/\1/')"
    [ -n "${start[$n]:-}" ] || { echo "ERROR: §$n not found in SWARM.md" >&2; exit 1; }
    a="${start[$n]}"; b="$total"
    for m in "${order[@]}"; do
      if [ "${start[$m]}" -gt "$a" ]; then b=$(( ${start[$m]} - 1 )); break; fi
    done
    matched=$((matched + 1))
    printf '%s%-*s%s\n' "${BASH_REMATCH[1]}" "${#BASH_REMATCH[2]}" "$a-$b" "${BASH_REMATCH[3]}" >>"$tmp"
  else
    printf '%s\n' "$line" >>"$tmp"
  fi
done <"$core"
if [ "$matched" -eq 0 ]; then
  echo "ERROR: no '| §N | ... | start-end |' rows matched in CORE.md" >&2
  exit 1
fi
cat "$tmp" >"$core"
echo "CORE.md index refreshed (SWARM.md: $total lines, $matched rows)"
