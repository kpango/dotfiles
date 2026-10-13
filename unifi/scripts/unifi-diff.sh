#!/usr/bin/env bash
# unifi-diff — compare dotfiles/unifi/{data,root}/ against the live UDM Pro using md5sum.
# Exit 0 when fully in sync; 1 on drift. Remote-only files are intentionally ignored
# (the UDM Pro has runtime state that dotfiles never shadows).
set -euo pipefail

# shellcheck source=_lib.sh
. "$(dirname "$0")/_lib.sh"

rc=0

# compare_side LOCAL REMOTE LABEL — print per-file DRIFT/MISSING for every tracked
# local file whose md5 does not match the remote, and bump $rc on any mismatch.
# REMOTE must be one of the fixed UDM Pro mount points ("/data" or "/root") —
# it is embedded verbatim into the remote shell command, so we restrict it to
# whitelisted paths rather than quoting it (anything else is a bug not an input).
compare_side() {
  local local_dir=$1 remote_dir=$2 label=$3
  local local_sums remote_sums drifts
  case "$remote_dir" in
    /data|/root) ;;
    *) die "compare_side: unexpected remote_dir '$remote_dir' (must be /data or /root)";;
  esac
  local_sums=$(cd "$local_dir" && find . -type f -print0 | sort -z \
               | xargs -0 md5sum | sed 's| \./| |')
  remote_sums=$(ssh "$UDM" "cd $remote_dir && find . -type f -print0 2>/dev/null \
                            | sort -z | xargs -0 md5sum 2>/dev/null | sed 's| ./| |'")
  drifts=$(
    # Compare only files present locally; join by filename.
    join -a1 -1 2 -2 2 -o '1.1 1.2 2.1' \
      <(printf '%s\n' "$local_sums"  | sort -k2) \
      <(printf '%s\n' "$remote_sums" | sort -k2) \
    | awk '{
        if ($3 == "")       { print "MISSING " $2 }
        else if ($1 != $3)  { print "DRIFT   " $2 }
      }'
  )
  if [ -n "$drifts" ]; then
    printf '=== %s drifts ===\n%s\n' "$label" "$drifts"
    rc=1
  else
    printf '=== %s in sync (%d files) ===\n' "$label" "$(printf '%s\n' "$local_sums" | wc -l)"
  fi
}

compare_side "$UNIFI_DATA" /data /data
compare_side "$UNIFI_ROOT" /root /root

if [ $rc -eq 0 ]; then log diff "all in sync"
else                   log diff "drift detected"
fi
exit $rc
