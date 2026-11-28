#!/usr/bin/env bash
# precheck-cron.sh -- 0-token deterministic pre-check for Hermes gateway periodic tasks.
# Runs before any LLM is started; emits {"action_required": false} when nothing needs doing.
#
# Target: THIS dotfiles repository only. The script cd's to its own checkout root before calling
# gh, so the result never depends on the caller's cwd (a cron may start anywhere).
#
# usage: precheck-cron.sh [--task pr-review|ci-failure|catalog-drift|all] [--json] [--dry-run]
# exit: 0 = check completed (action_required true/false)
#       2 = usage error
#       3 = check could not be completed (gh/timeout missing, unauthenticated, network, hung call,
#           not inside a dotfiles checkout): action_required is reported as null, never as false.
#           Hits already confirmed by other tasks are still listed in "tasks".
# env:  PRECHECK_CATALOG_SCRIPT overrides agent/scripts/update-model-catalog.py (tests).
#       PRECHECK_TIMEOUT seconds per gh/python3 call (default 30).
set -euo pipefail

# gh must act on THIS repo with the caller-independent default host: drop the env overrides
# (GH_CONFIG_DIR is kept: gh needs it for authentication).
unset GH_REPO GH_HOST GIT_DIR GIT_WORK_TREE

task=all
json=0
dry=0
while [ $# -gt 0 ]; do
  case "$1" in
    --task)
      [ $# -ge 2 ] || { echo "precheck-cron: --task needs a value" >&2; exit 2; }
      task="$2"; shift 2 ;;
    --json) json=1; shift ;;
    --dry-run) dry=1; shift ;;
    *) echo "precheck-cron: unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$task" in
  pr-review | ci-failure | catalog-drift | all) ;;
  *) echo "precheck-cron: unknown task: $task" >&2; exit 2 ;;
esac

json_esc() { # json_esc <string>: escape for embedding in a JSON string (incl. U+0000-U+001F)
  local s="$1" out="" c h i
  local LC_ALL=C
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      '\') out+='\\' ;;
      '"') out+='\"' ;;
      $'\n') out+='\n' ;;
      $'\t') out+='\t' ;;
      $'\r') out+='\r' ;;
      *)
        if [[ "$c" < " " ]]; then
          printf -v h '\\u%04x' "'$c"
          out+="$h"
        else
          out+="$c"
        fi ;;
    esac
  done
  printf '%s' "$out"
}
json_list() { # json_list items...
  local sep="" i
  printf '['
  for i in "$@"; do printf '%s"%s"' "$sep" "$(json_esc "$i")"; sep=", "; done
  printf ']'
}
fail_null() { # fail_null <message>: report "could not check" and exit 3
  local msg="$1"
  if [ "$json" -eq 1 ]; then
    printf '{"action_required": null, "error": "%s"}\n' "$(json_esc "$msg")"
  fi
  echo "precheck-cron: $msg" >&2
  exit 3
}

src_dir=.
case "${BASH_SOURCE[0]}" in */*) src_dir="${BASH_SOURCE[0]%/*}" ;; esac
ROOT="$(CDPATH= cd -P -- "$src_dir/../../.." >/dev/null 2>&1 && pwd)" || ROOT=""
if [ -z "$ROOT" ] || [ ! -f "$ROOT/Makefile" ] || [ ! -d "$ROOT/agent/scripts" ]; then
  fail_null "cannot locate the dotfiles checkout root from ${BASH_SOURCE[0]}"
fi
cd "$ROOT" || fail_null "cannot cd to $ROOT"
CATALOG_SCRIPT="${PRECHECK_CATALOG_SCRIPT:-$ROOT/agent/scripts/update-model-catalog.py}"
TMO="${PRECHECK_TIMEOUT:-30}"
if ! [[ "$TMO" =~ ^[1-9][0-9]{0,5}$ ]]; then
  echo "precheck-cron: PRECHECK_TIMEOUT must be a positive integer (got '$TMO')" >&2
  exit 2
fi

if [ "$task" = all ]; then tasks=(pr-review ci-failure catalog-drift); else tasks=("$task"); fi

if [ "$dry" -eq 1 ]; then
  planned=()
  for t in "${tasks[@]}"; do
    case "$t" in
      pr-review) planned+=("gh pr list --search review-requested:@me --state open --json number --jq length") ;;
      ci-failure) planned+=("gh run list --branch <default> --status completed --limit 1 --json conclusion --jq .[0].conclusion") ;;
      catalog-drift) planned+=("python3 $CATALOG_SCRIPT --check") ;;
    esac
  done
  if [ "$json" -eq 1 ]; then
    printf '{"action_required": null, "dry_run": true, "planned": %s}\n' "$(json_list "${planned[@]}")"
  else
    printf 'dry-run: %s\n' "${planned[@]}"
  fi
  exit 0
fi

errors=()
hits=()

# gh_val <desc> <num|any> <args...>: sets $val; returns non-zero and records an error otherwise.
# (Not run in a subshell, so errors+= is kept.)
val=
gh_val() {
  local desc="$1" kind="$2" out rc
  shift 2
  if ! command -v timeout >/dev/null 2>&1; then
    errors+=("$desc: timeout not installed"); return 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    errors+=("$desc: gh not installed"); return 1
  fi
  rc=0
  timeout -k 5 "$TMO" gh auth status >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then errors+=("$desc: gh auth status timed out after ${TMO}s"); return 1; fi
  if [ "$rc" -ne 0 ]; then errors+=("$desc: gh not authenticated"); return 1; fi
  rc=0
  out="$(timeout -k 5 "$TMO" gh "$@" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then errors+=("$desc: gh timed out after ${TMO}s"); return 1; fi
  if [ "$rc" -ne 0 ]; then errors+=("$desc: gh command failed (network/API)"); return 1; fi
  if [ "$kind" = num ]; then
    case "$out" in
      '' | *[!0-9]*) errors+=("$desc: unexpected gh output"); return 1 ;;
    esac
    if [ "${#out}" -gt 15 ]; then errors+=("$desc: gh count unexpectedly large"); return 1; fi
  fi
  val="$out"
}

for t in "${tasks[@]}"; do
  case "$t" in
    pr-review)
      if gh_val pr-review num pr list --search "review-requested:@me" --state open --json number --jq length; then
        [ "$val" -gt 0 ] && hits+=("pr-review")
      fi ;;
    ci-failure)
      # Only the latest completed run on the default branch counts (older failures are history).
      if gh_val ci-failure any repo view --json defaultBranchRef --jq .defaultBranchRef.name; then
        branch="$val"
        if [ -z "${branch//[[:space:]]/}" ]; then
          errors+=("ci-failure: gh returned an empty default branch name")
        elif gh_val ci-failure any run list --branch "$branch" --status completed --limit 1 --json conclusion --jq '.[0].conclusion // ""'; then
          case "$val" in
            failure | timed_out | startup_failure) hits+=("ci-failure") ;;
          esac
        fi
      fi ;;
    catalog-drift)
      if ! command -v timeout >/dev/null 2>&1; then
        errors+=("catalog-drift: timeout not installed")
      else
        rc=0
        cout="$(timeout -k 5 "$TMO" python3 "$CATALOG_SCRIPT" --check 2>&1)" || rc=$?
        case "$rc" in
          0) ;;
          1)
            # update-model-catalog.py exits 1 for drift AND for other failures; only its
            # "FAIL: drift:" / "FAIL: missing:" lines mean the catalog is out of sync.
            if printf '%s\n' "$cout" | grep -Eq '^FAIL: (drift|missing): '; then
              hits+=("catalog-drift")
            else
              errors+=("catalog-drift: check exited 1 without a drift marker (validation error or script failure)")
            fi ;;
          124 | 137) errors+=("catalog-drift: check script timed out after ${TMO}s") ;;
          *) errors+=("catalog-drift: check script failed (exit $rc)") ;;
        esac
      fi ;;
  esac
done

if [ "${#errors[@]}" -gt 0 ]; then
  msg="$(printf '%s; ' "${errors[@]}")"
  msg="${msg%; }"
  if [ "$json" -eq 1 ]; then
    if [ "${#hits[@]}" -gt 0 ]; then
      printf '{"action_required": null, "tasks": %s, "error": "%s"}\n' "$(json_list "${hits[@]}")" "$(json_esc "$msg")"
    else
      printf '{"action_required": null, "error": "%s"}\n' "$(json_esc "$msg")"
    fi
  fi
  echo "precheck-cron: $msg" >&2
  exit 3
fi

if [ "${#hits[@]}" -gt 0 ]; then
  if [ "$json" -eq 1 ]; then
    printf '{"action_required": true, "tasks": %s}\n' "$(json_list "${hits[@]}")"
  else
    echo "action required: ${hits[*]}"
  fi
else
  if [ "$json" -eq 1 ]; then
    echo '{"action_required": false}'
  else
    echo "no action required"
  fi
fi
exit 0
