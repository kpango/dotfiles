if (($+commands[git])); then
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
		git remote show origin | grep 'HEAD' | cut -d':' -f2 | sed -e 's/^ *//g' -e 's/ *$//g'
	}
	alias gitdb=gitdefaultbranch

	# Check for merged branches that can be removed
	gitremovalcheck() {
		local db=$(gitdb)
		git branch -r --merged "$db" | grep -v -e "$db" -e develop -e release | sed -E 's% *origin/%%'
		git branch --merged "$db" | grep -vE '^\*|master$|develop$|main$'
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

	# Common function for fetch, reset, and cleanup
	gfr() {
		local tb=$(tb)
		local db=$(gitdb)
		_git_fetch_reset $tb || return 1

		git branch -r --merged $db | grep -v -e $db -e develop -e release | sed -E 's% *origin/%%' | xargs -I% -P ${CPUCORES:-4} git push --delete origin % || {
			echo "Failed to delete merged branches"
			return 1
		}

		_git_fetch_reset $tb || return 1

		git branch --merged "$db" --format='%(refname:short)' |
			grep -vE '^(master|develop|main)$|^release/' |
			xargs -I % -P ${CPUCORES:-4} git branch -d % ||
			{
				echo "Failed to delete local branches"
				return 1
			}

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

	_git_commit_push() {
		local msg=$1
		shift
		git add -A
		git commit --signoff -m "$msg"
		git push "$@"
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

	# Amend last commit and force push
	gfp() {
		git add -A || {
			echo "Failed to stage changes"
			return 1
		}
		git commit --signoff --amend || {
			echo "Failed to amend commit"
			return 1
		}
		git push --force-with-lease || {
			echo "Failed to force push"
			return 1
		}
	}

	# Rebase and squash changes
	grs() {
		if [ $# -eq 1 ] || [ $# -eq 2 ]; then
			local branch="$(tb)"
			git checkout "$1" || {
				echo "Failed to checkout branch $1"
				return 1
			}
			gfrs
			git checkout -b tmp || {
				echo "Failed to create tmp branch"
				return 1
			}
			git merge --squash "$branch"
			if [ $# -eq 2 ]; then
				git checkout "$2" . || {
					echo "Failed to checkout files from $2"
					return 1
				}
			fi

			git branch -D "$branch" || {
				echo "Failed to delete branch $branch"
				return 1
			}
			git branch -m "$branch" || {
				echo "Failed to rename branch"
				return 1
			}
		else
			echo "invalid argument, rebase branch name required"
			return 1
		fi
	}

	# Rebase, squash, and push changes
	grsp() {
		if [ $# -eq 1 ] || [ $# -eq 2 ]; then
			local message="$(git log remotes/origin/$1..$branch --reverse --pretty=%s)"
			grs "$@"
			gcpf $message
		else
			echo "invalid argument, rebase branch name required"
			return 1
		fi
	}

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
if (($+commands[fzf])); then
	if (($+commands[fzf-tmux])); then
		if (($+commands[rg])); then
			fbr() {
				git branch --all | rg -v HEAD | fzf-tmux +m | \sed -E "s/.* //" -e "s#remotes/[^/]*/##" | xargs git checkout
			}
		fi
	fi
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
			git status
			git diff --name-only
			echo "Detailed changes:"
			git diff
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
