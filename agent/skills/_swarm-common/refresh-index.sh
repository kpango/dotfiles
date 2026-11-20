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
while IFS= read -r line; do
  if [[ "$line" =~ ^\|\ §([0-9]+)\ \|\ (.*)\ \|\ [0-9]+-[0-9]+\ \|$ ]]; then
    n="${BASH_REMATCH[1]}"; desc="${BASH_REMATCH[2]}"
    [ -n "${start[$n]:-}" ] || { echo "ERROR: §$n not found in SWARM.md" >&2; exit 1; }
    a="${start[$n]}"; b="$total"
    for m in "${order[@]}"; do
      if [ "${start[$m]}" -gt "$a" ]; then b=$(( ${start[$m]} - 1 )); break; fi
    done
    printf '| §%s | %s | %s-%s |\n' "$n" "$desc" "$a" "$b" >>"$tmp"
  else
    printf '%s\n' "$line" >>"$tmp"
  fi
done <"$core"
cat "$tmp" >"$core"
echo "CORE.md index refreshed (SWARM.md: $total lines)"
