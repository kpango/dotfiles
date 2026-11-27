#!/usr/bin/env bash
# trail-guard — transparent `trail` wrapper that keeps `trail init` away from
# dotfiles-authored skill files.
#
# Why this exists: `trail init` rewrites `~/.claude/skills/trail/SKILL.md` (and
# `~/.gemini/skills/trail/SKILL.md`) with upstream's own description, which is
# far longer than the repo-wide 160-character catalog limit. On this machine
# both paths are symlinks into `agent/skills/` of the dotfiles checkout, so an
# upstream rewrite silently corrupts a tracked, protected file and fails
# `agent/scripts/test-catalog-health.sh`.
#
# The wrapper snapshots `agent/skills/trail/SKILL.md` in the init target repo
# (if it is tracked there), runs the real CLI unchanged, and restores the
# snapshot only when `trail init` changed it. Every other subcommand is exec'd
# as-is. There is no way to make the file unwritable for a checkout owned by
# the same user; this is the restore guard, not a filesystem lock.
#
# env:
#   TRAIL_REAL_BIN   absolute path to the real trail binary (default: first
#                    `trail` on PATH that is not this wrapper)
#
# usage: installed as ~/.local/bin/trail (Makefile.d/install.mk DOTFILES_MAP).
set -euo pipefail

protected_rel="agent/skills/trail/SKILL.md"

self="$0"
self_dir="$(cd -P -- "$(dirname -- "$0")" && pwd)"

real="${TRAIL_REAL_BIN:-}"
if [ -z "$real" ]; then
  IFS=: read -r -a path_dirs <<<"${PATH}"
  for d in "${path_dirs[@]}"; do
    d="${d:-.}"
    cand="${d%/}/trail"
    [ -x "$cand" ] || continue
    if [ "$cand" -ef "$self" ]; then
      continue
    fi
    real="$cand"
    break
  done
fi

if [ -z "$real" ]; then
  echo "trail-guard: no real trail binary found on PATH (set TRAIL_REAL_BIN)" >&2
  exit 127
fi

is_init=0
for a in "$@"; do
  case "$a" in
    init) is_init=1; break ;;
    -*) ;;
    *) break ;;
  esac
done

if [ "$is_init" -eq 0 ]; then
  exec "$real" "$@"
fi

# Pick the init target: the last non-option argument that is a directory.
# Options with values (--agents a b, --server url) can look like arguments;
# the tracked-file check below makes a wrong guess a no-op.
target="."
seen_init=0
for a in "$@"; do
  if [ "$seen_init" -eq 0 ]; then
    [ "$a" = "init" ] && seen_init=1
    continue
  fi
  case "$a" in
    -*) ;;
    *) [ -d "$a" ] && target="$a" ;;
  esac
done

snapshot_dir=""
snapshot_file=""
target_file="${target%/}/$protected_rel"
if [ -f "$target_file" ] \
  && git -C "$target" ls-files --error-unmatch "$protected_rel" >/dev/null 2>&1; then
  snapshot_dir="$(mktemp -d)"
  snapshot_file="$snapshot_dir/SKILL.md"
  cp -p "$target_file" "$snapshot_file"
fi

cleanup() {
  [ -n "$snapshot_dir" ] && rm -rf "$snapshot_dir"
}
trap cleanup EXIT

rc=0
"$real" "$@" || rc=$?

if [ -n "$snapshot_file" ] && [ -e "$snapshot_file" ]; then
  if ! cmp -s "$snapshot_file" "$target_file"; then
    rm -f "$target_file"
    cp -p "$snapshot_file" "$target_file"
    echo "trail-guard: kept $protected_rel unchanged (trail init rewrote it)" >&2
  fi
fi

exit "$rc"
