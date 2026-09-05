if (($+commands[git])); then
	# Auto-inject --author on every `git commit` made from this shell.
	# GIT_COMMITTER_NAME/EMAIL are exported once, machine-wide, from
	# $ZCACHE_DIR/env.zsh (baked by zfunc/_gen_env from `git config --global
	# user.*`, sourced by both the non-interactive `zsh -c` fast path and
	# interactive zshrc -- see zfunc/_gen_env for the full rationale) with a
	# hardcoded ultimate fallback, so they are normally non-empty by the
	# time this function runs; re-deriving them here (e.g. via `git config`)
	# would just be a second, usually-unreachable fallback strategy.
	# --author is the only
	# flag among git's commit-creating subcommands that sets this
	# explicitly (verified via `git <sub> -h` for commit/commit-tree/merge/
	# cherry-pick/revert -- only `commit` has it) and always wins over
	# GIT_AUTHOR_NAME/EMAIL (verified: `--author` beats the env vars even
	# when both are given), so only `git commit` is intercepted, and only
	# to add --author -- GIT_AUTHOR_NAME/EMAIL are never set here, since an
	# explicit or auto-injected --author is always present and would make
	# them dead weight regardless. Every other subcommand (status/diff/
	# log/push/...) falls straight through to `command git` untouched --
	# this must stay cheap, since prompt integrations (Powerlevel10k etc.)
	# shell out to `git status` on every prompt render. An explicit
	# --author passed by the caller is never overridden.
	git() {
		if [ "$1" != "commit" ]; then
			command git "$@"
			return $?
		fi
		shift

		if [ -z "$GIT_COMMITTER_NAME" ] || [ -z "$GIT_COMMITTER_EMAIL" ]; then
			echo "git commit: GIT_COMMITTER_NAME/EMAIL not set (\$ZCACHE_DIR/env.zsh not loaded?) -- committing without a forced author" >&2
			command git commit "$@"
			return $?
		fi

		local has_author=0
		local a
		for a in "$@"; do
			case "$a" in
			--author | --author=*) has_author=1 ;;
			esac
		done

		if [ "$has_author" -eq 1 ]; then
			command git commit "$@"
		else
			command git commit --author="$GIT_COMMITTER_NAME <$GIT_COMMITTER_EMAIL>" "$@"
		fi
	}

	# General Git aliases
	alias gco="git checkout"
	alias gsta="git status"
	alias gcom="git commit -m"
	alias gdiff="git diff"
	alias gbra="git branch"

	# Get current repository branch name
	gitthisrepo() {
		git branch --show-current
	}
	alias tb=gitthisrepo

	# Get default branch name
	gitdefaultbranch() {
		git remote show origin | rg 'HEAD' | cut -d':' -f2 | sed -e 's/^ *//g' -e 's/ *$//g'
	}
	alias gitdb=gitdefaultbranch

	# Check for merged branches that can be removed
	gitremovalcheck() {
		local db
		db=$(gitdb)
		git branch -r --merged "$db" | rg -v -e "$db" -e develop -e release | sed -E 's% *origin/%%'
		git branch --merged "$db" | rg -v '^\*|master$|develop$|main$'
	}
	alias grc=gitremovalcheck

	_git_fetch_reset() {
		local branch=$1
		git fetch --prune
		git reset --hard origin/$branch || {
			echo "Failed to reset to $branch"
			return 1
		}
	}

	# Common function for fetch, reset, and cleanup.
	# Deletion failures are reported (not swallowed) so a bad --merged match
	# is never silently destructive; each branch is still best-effort (one
	# failure doesn't abort the rest of the cleanup).
	gfr() {
		local tb
		tb=$(tb)
		local db
		db=$(gitdb)
		_git_fetch_reset "$tb" || return 1

		local remote_merged
		remote_merged=$(git branch -r --merged "$db" | rg -v -e "$db" -e develop -e release | sed -E 's% *origin/%%')
		if [ -n "$remote_merged" ]; then
			echo "$remote_merged" | while IFS= read -r b; do
				[ -n "$b" ] || continue
				echo "Deleting remote branch $b (merged into $db)"
				git push --delete origin "$b" || echo "Failed to delete remote branch $b"
			done
		fi

		_git_fetch_reset $tb || return 1

		local local_merged=$(git branch --merged "$db" --format='%(refname:short)' | rg -v '^(master|develop|main)$|^release/')
		if [ -n "$local_merged" ]; then
			echo "$local_merged" | while IFS= read -r b; do
				[ -n "$b" ] || continue
				git branch -d "$b" || echo "Failed to delete local branch $b"
			done
		fi
	}

	# Fetch, reset, and update submodules
	gfrs() {
		gfr && git submodule foreach git pull origin "$(gitdb)" || {
			echo "Failed to update submodules"
			return 1
		}
	}

	# Pull with rebase
	gitpull() {
		git pull --rebase origin "$(tb)" || {
			echo "Failed to pull with rebase"
			return 1
		}
	}
	alias gpull=gitpull

	# Push to current branch
	gpush() {
		git push -u origin "$(tb)" || {
			echo "Failed to push to origin"
			return 1
		}
	}

	# Fails (printing why) unless the working tree is fully clean. Used by
	# operations that can't safely proceed with uncommitted changes mixed
	# in and don't want to reach for stash: a stash that itself conflicts
	# on restore would just be a second failure mode needing the same
	# treatment as below, so "commit or stash yourself first" is the
	# simplest rule that's still safe.
	_git_require_clean_tree() {
		if ! git diff --quiet || ! git diff --cached --quiet; then
			echo "Uncommitted changes present -- commit or stash before running $1"
			return 1
		fi
	}

	# Rolls a branch-mutating operation back to a known-good state.
	#   _git_restore_all <anchor> <final-branch> <message> <name> <sha> [<name> <sha> ...]
	# Prints <message> (if non-empty), detaches to <anchor> (a plain
	# commit, not a branch about to be moved/deleted -- must stay valid
	# throughout), force-restores each <name> to its <sha>, or deletes
	# <name> entirely when <sha> is empty (meaning it didn't exist before
	# the operation began), then checks out <final-branch>.
	# The upfront detach is what makes every restore below it safe
	# regardless of current repo state: a plain `git checkout -f` clears a
	# conflicted index/worktree unconditionally (unlike `merge --abort`,
	# which needs MERGE_HEAD -- something `merge --squash` never sets),
	# and once detached, none of the <name>s being restored can be "the
	# branch currently checked out", a state `git branch -f` refuses.
	# Shared by grs/grsp/gsqh below; reuse it for any future alias here
	# that deletes/renames/force-moves a branch as part of a multi-step
	# recipe, instead of re-deriving this by hand.
	_git_restore_all() {
		local anchor=$1 final=$2 msg=$3
		shift 3
		[ -n "$msg" ] && echo "$msg"
		git checkout -f "$anchor" 2>/dev/null
		while [ $# -ge 2 ]; do
			if [ -n "$2" ]; then
				git branch -f "$1" "$2" 2>/dev/null
			else
				git branch -D "$1" 2>/dev/null
			fi
			shift 2
		done
		git checkout "$final" 2>/dev/null
	}

	_git_commit_push() {
		local msg=$1
		shift
		git add -A || {
			echo "Failed to stage changes"
			return 1
		}
		git commit --signoff -m "$msg" || {
			echo "Failed to commit"
			return 1
		}
		git push "$@" || {
			echo "Failed to push"
			return 1
		}
	}

	# Commit, signoff, and push
	gitcompush() {
		_git_commit_push "$1" -u origin "$2"
	}

	# Commit, signoff, and push to current branch
	gcp() {
		gitcompush "$1" "$(tb)"
	}
	alias gfix="gcp fix"

	# Commit, signoff, and force push with lease
	gitcompushf() {
		_git_commit_push "$1" --force-with-lease --set-upstream origin "$2"
	}

	# Commit, signoff, and force push to current branch
	gcpf() {
		gitcompushf "$1" "$(tb)"
	}

	# Amend last commit and force push. Reverts the amend if the push
	# fails, so a rejected/failed push never leaves HEAD silently rewritten
	# with no easy way back short of the reflog.
	gfp() {
		local orig_head
		orig_head="$(git rev-parse HEAD)" || return 1
		git add -A || {
			echo "Failed to stage changes"
			return 1
		}
		git commit --signoff --amend || {
			echo "Failed to amend commit"
			return 1
		}
		git push --force-with-lease || {
			echo "Failed to force push -- reverting the amend"
			git reset --hard "$orig_head" 2>/dev/null
			return 1
		}
	}

	# Rebase and squash changes onto a fresh branch of the same name.
	# On ANY failure this restores exactly the state before grs was called
	# (via _git_restore_all): $branch and $target (if $target already
	# existed locally) go back to their original tips, tmp is removed, and
	# $branch is re-checked-out. $branch is only ever deleted for real once
	# the squashed commit demonstrably exists on tmp.
	# Also intentionally uses a manual fetch+merge-base check instead of
	# _git_fetch_reset/gfr/gfrs: gfr's merged-branch cleanup operates on
	# the whole repo and has no business running as a side effect of
	# squashing one branch, and _git_fetch_reset's plain `reset --hard`
	# would silently discard any local-only commits on $target as part of
	# a *successful* run (not a failure grs's own abort guards would ever
	# see) -- so that case gets its own explicit refusal below instead.
	# grs [--force] <target> [<path>]
	# --force: if the squash-merge conflicts, commit it anyway with the
	# conflict markers left in place instead of aborting/restoring. An
	# explicit "save my work, I'll resolve by hand" escape hatch -- any
	# other failure, or a conflict without --force, still aborts and
	# restores the pre-command state exactly as before. --force may appear
	# anywhere among the arguments.
	grs() {
		local -a args
		local force=0
		local a
		for a in "$@"; do
			if [ "$a" = "--force" ]; then
				force=1
			else
				args+=("$a")
			fi
		done

		if [ ${#args[@]} -eq 1 ] || [ ${#args[@]} -eq 2 ]; then
			_git_require_clean_tree grs || return 1
			local target="${args[1]}"
			local branch="$(tb)"
			if [ "$branch" = "$target" ]; then
				echo "Refusing to squash '$target' onto itself"
				return 1
			fi
			local branch_orig_head
			branch_orig_head="$(git rev-parse "$branch")" || return 1
			local target_orig_head=""
			git show-ref --verify --quiet "refs/heads/$target" && target_orig_head="$(git rev-parse "$target")"
			local message
			message="$(git log "remotes/origin/$target..$branch" --reverse --pretty=%s)"
			# PID-suffixed, not a bare "tmp": a concurrent grs() invocation (or a
			# leftover from one that crashed) would otherwise collide on `git
			# checkout -b tmp` -- same rationale as the `orphan-$$` branch further
			# down in this file.
			local tmp_branch="grs-tmp-$$"

			_grs_abort() {
				_git_restore_all "$branch_orig_head" "$branch" "$1 -- reverting to pre-command state" \
					"$tmp_branch" "" "$branch" "$branch_orig_head" "$target" "$target_orig_head"
			}

			git checkout "$target" || {
				_grs_abort "Failed to checkout branch $target"
				return 1
			}
			git fetch --prune || {
				_grs_abort "Failed to fetch"
				return 1
			}
			if ! git merge-base --is-ancestor "$target" "origin/$target" 2>/dev/null; then
				_grs_abort "Local '$target' has commits not on origin/$target -- refusing to discard them"
				return 1
			fi
			git reset --hard "origin/$target" || {
				_grs_abort "Failed to reset $target to origin/$target"
				return 1
			}
			git checkout -b "$tmp_branch" || {
				_grs_abort "Failed to create $tmp_branch branch"
				return 1
			}
			local force_committed_conflicts=0
			git merge --squash "$branch" || {
				# Stage only the actually-conflicted paths (not `git add -A`):
				# `git merge --squash` already auto-staged everything that
				# merged cleanly, so a blanket -A here would also sweep in
				# any unrelated untracked files sitting in the working tree
				# -- something `_git_require_clean_tree` doesn't catch, since
				# it only checks tracked-file diffs.
				local -a conflicted
				conflicted=(${(f)"$(git diff --name-only --diff-filter=U)"})
				if [ "$force" -eq 1 ] && [ ${#conflicted[@]} -gt 0 ]; then
					echo "grs --force: squash-merge of $branch conflicted -- committing anyway with unresolved conflict markers left in the files"
					git add -- "${conflicted[@]}" || {
						_grs_abort "Failed to stage conflicted files under --force"
						return 1
					}
					force_committed_conflicts=1
				else
					_grs_abort "Failed to squash-merge $branch"
					return 1
				fi
			}
			if [ ${#args[@]} -eq 2 ]; then
				git checkout "${args[2]}" . || {
					_grs_abort "Failed to checkout files from ${args[2]}"
					return 1
				}
			fi
			if git diff --cached --quiet; then
				_grs_abort "Nothing to squash ($target already matches $branch)"
				return 1
			fi
			if [ "$force_committed_conflicts" -eq 1 ]; then
				message="${message:-squash $branch}

grs --force: committed with unresolved merge conflicts -- search for conflict markers before merging further"
			else
				message="${message:-squash $branch}"
			fi
			git commit --signoff -m "$message" || {
				_grs_abort "Failed to commit squashed changes"
				return 1
			}

			# Only reachable once the squashed commit safely exists on tmp.
			git branch -D "$branch" || {
				_grs_abort "Failed to delete branch $branch"
				return 1
			}
			git branch -m "$branch" || {
				_grs_abort "Failed to rename branch"
				return 1
			}
			unfunction _grs_abort 2>/dev/null
		else
			echo "invalid argument, rebase branch name required"
			return 1
		fi
	}
	alias grsf="grs --force"

	# grsp [--force] <target> [<path>]
	# Rebase, squash, and push changes. If grs fails it has already restored
	# the pre-command state itself; if grs succeeds but the push fails
	# (rejected, network error, etc.) grsp reverts the local squash too, so
	# a failed grsp -- for any reason -- never leaves the branch half-done
	# (locally squashed but not pushed, diverging from origin with no easy
	# way back short of the reflog). --force is passed straight through to
	# grs (see grs for what it does); grsp does no argument validation of
	# its own -- grs is the single source of truth for that and already
	# echoes its own error and returns 1 on anything invalid.
	grsp() {
		local branch="$(tb)"
		local orig_head
		orig_head="$(git rev-parse HEAD)" || return 1

		grs "$@" || return 1

		git push --force-with-lease --set-upstream origin "$(tb)" || {
			_git_restore_all "$orig_head" "$branch" \
				"Failed to force push $(tb) -- reverting the local squash (grs succeeded but the push did not)" \
				"$branch" "$orig_head"
			return 1
		}
	}
	alias grspf="grsp --force"

	# Squash all history into a single commit using an orphan branch.
	# Usage: gsqh <commit message>
	git-squash-history() {
		if [ $# -eq 0 ]; then
			echo "usage: gsqh <commit message>"
			return 1
		fi
		_git_require_clean_tree gsqh || return 1
		local branch
		branch=$(git branch --show-current) || return 1
		if [ -z "$branch" ]; then
			echo "Not on a named branch (detached HEAD?)"
			return 1
		fi
		local branch_orig_head
		branch_orig_head="$(git rev-parse "$branch")" || return 1
		local msg=$*
		local tmp="orphan-$$"

		# Same restore-on-any-failure discipline as grs: $branch is only
		# ever deleted once the orphan commit exists, and any failure --
		# including the final push -- reverts $branch to branch_orig_head.
		_gsqh_abort() {
			_git_restore_all "$branch_orig_head" "$branch" "$1 -- reverting to pre-command state" \
				"$tmp" "" "$branch" "$branch_orig_head"
		}

		git checkout --orphan "$tmp" || {
			_gsqh_abort "Failed to create orphan branch"
			return 1
		}
		git add -A || {
			_gsqh_abort "Failed to stage files"
			return 1
		}
		git commit --signoff -m "$msg" || {
			_gsqh_abort "Failed to commit"
			return 1
		}
		git branch -D "$branch" || {
			_gsqh_abort "Failed to delete branch $branch"
			return 1
		}
		git branch -m "$branch" || {
			_gsqh_abort "Failed to rename branch"
			return 1
		}
		echo "Done: branch '$branch' now has a single root commit."
		git push --force-with-lease || {
			_gsqh_abort "Failed to push"
			return 1
		}
		unfunction _gsqh_abort 2>/dev/null
	}
	alias gsqh=git-squash-history

	# Edit Git config
	alias gedit="$EDITOR $HOME/.gitconfig"

	# Fetch and merge from upstream
	git-remote-merge() {
		git fetch upstream || {
			echo "Failed to fetch from upstream"
			return 1
		}
		git merge upstream/$(gitdb) || {
			echo "Failed to merge upstream branch"
			return 1
		}
	}
	alias grf=git-remote-merge
	# Add and merge remote repository
	git-remote-add-merge() {
		git remote add upstream "$1" || {
			echo "Failed to add remote upstream"
			return 1
		}
		grf
	}
	alias grfa=git-remote-add-merge
fi

export GIT_USER=${GIT_USER:-kpango}
if (($+commands[fzf])) && (($+commands[rg])); then
	fbr() {
		git branch --all | rg -v HEAD | fzf --tmux +m | \sed -E "s/.* //" -e "s#remotes/[^/]*/##" | xargs git checkout
	}
fi

update_git_repo() {
	local repo_dir=$1
	if [ -d "$repo_dir" ]; then
		pushd "$repo_dir" >/dev/null || return
		if git diff-index --quiet HEAD -- && [ -z "$(git diff --ignore-space-change --ignore-blank-lines --diff-filter=MARC)" ]; then
			echo "No local changes in $repo_dir, pulling latest changes from origin..."
			gfrs
		else
			echo "Local changes detected in $repo_dir, not pulling from origin. Here are the changes:"
			git --no-pager status
			git --no-pager diff --name-only
			echo "Detailed changes:"
			git --no-pager diff
		fi
		popd >/dev/null || return
	else
		echo "Directory $repo_dir does not exist." >&2
	fi
}

update_multiple_git_repos() {
	for repo; do
		update_git_repo "$repo"
	done
}

kpangoup() {
	update_multiple_git_repos \
		"$GOPATH/src/github.com/kpango/dotfiles" \
		"$GOPATH/src/github.com/kpango/pass" \
		"$GOPATH/src/github.com/vdaas/vald" \
		"$GOPATH/src/github.com/vdaas/vald-client-go"
}
