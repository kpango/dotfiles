#!/usr/bin/env bash
# check-cprm.sh — fail on a bare cp/rm in zsh/Makefile/Nix/Docker config.
#
# These files must prefer cpz/rmz (see CONTEXT.md "cpz-rmz-preference"):
#   Makefile.d/*.mk  -> $(CP) / $(RM)            (Makefile.d/fuc.mk)
#   zsh/*.zsh        -> "${_cp[@]}" / "${_rm[@]}" (zsh/04-aliases.zsh)
#   nix, Dockerfiles -> an inline `command -v rmz` / `$cargoBin/cpz` check
# A line is accepted when it is a comment, is not a file cp/rm (docker rm,
# --rm, cargo-rm), mentions cpz/rmz itself (a guarded fallback), or matches
# one of the deliberate exceptions in ALLOW below.
#
# Usage: Makefile.d/scripts/check-cprm.sh [repo-root]
set -euo pipefail

root="${1:-$(git -C "$(dirname "$0")" rev-parse --show-toplevel)}"
cd "$root"

# file<TAB>ERE matched against the line text. Keep each entry narrow.
ALLOW=$(
	cat <<'EOF'
zsh/04-aliases.zsh	typeset -ga _cp=\(cp -rf\)
zsh/04-aliases.zsh	typeset -ga _rm=\(rm -rf\)
zsh/04-aliases.zsh	alias cp='cp -r'
zsh/04-aliases.zsh	alias rm='rm -rf'
Makefile.d/install.mk	cp -Rpn "\$\(2\)/\." "\$\(1\)/"
EOF
)

mapfile -t files < <(
	git ls-files -- \
		Makefile 'Makefile.d/*.mk' 'zsh/*.zsh' zshrc zshenv \
		'nix/*.nix' 'dockers/*Dockerfile' | sort -u
)

# cp/rm as a command word: not part of a longer name, a path, $(RM)/$(CP), or -rm.
# shellcheck disable=SC2016  # literal `$(` inside the bracket expression
re='(^|[^[:alnum:]_./$(-])(cp|rm)( |$)'

bad=0
for f in "${files[@]}"; do
	[[ -f $f ]] || continue
	while IFS=: read -r n line; do
		[[ $line =~ ^[[:space:]]*# ]] && continue
		[[ $line =~ [Cc][Pp][Zz]|[Rr][Mm][Zz] ]] && continue
		stripped=$(sed -E 's/docker( (container|image|buildx|volume|network))? rm\b//g; s/--rm\b//g; s/cargo-rm\b//g' <<<"$line")
		grep -qE "$re" <<<"$stripped" || continue
		allowed=0
		while IFS=$'\t' read -r af are; do
			[[ $af == "$f" ]] && grep -qE -- "$are" <<<"$line" && {
				allowed=1
				break
			}
		done <<<"$ALLOW"
		((allowed)) && continue
		printf '%s:%s: bare cp/rm (use cpz/rmz with a fallback, see CONTEXT.md cpz-rmz-preference):\n    %s\n' "$f" "$n" "${line#"${line%%[![:space:]]*}"}" >&2
		bad=$((bad + 1))
	done < <(grep -nE "$re" -- "$f" || true)
done

if ((bad)); then
	printf 'check-cprm: %d bare cp/rm use(s) found\n' "$bad" >&2
	exit 1
fi
printf 'check-cprm: ok (%d files)\n' "${#files[@]}"
