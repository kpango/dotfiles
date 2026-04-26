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

	# Common function for fetch, reset, and cleanup
	gfr() {
		local tb=$(tb)
		local db=$(gitdb)
		git fetch --prune
		git reset --hard origin/$tb || {
			echo "Failed to reset"
			return 1
		}
		git branch -r --merged $db | grep -v -e $db -e develop -e release | sed -E 's% *origin/%%' | xargs -I% git push --delete origin % || {
			echo "Failed to delete merged branches"
			return 1
		}
		git fetch --prune
		git reset --hard origin/$tb || {
			echo "Failed to reset"
			return 1
		}
		git branch --merged "$db" --format='%(refname:short)' |
			grep -vE '^(master|develop|main)$|^release/' |
			xargs -I % git branch -d % ||
			{
				echo "Failed to delete local branches"
				return 1
			}

	}
	alias gfr=gfr

	# Fetch, reset, and update submodules
	gfrs() {
		gfr && git submodule foreach git pull origin "$(gitdb)" || {
			echo "Failed to update submodules"
			return 1
		}
	}
	alias gfrs=gfrs

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
	alias gpush=gpush

	# Commit, signoff, and push
	gitcompush() {
		git add -A
		git commit --signoff -m "$1"
		git push -u origin "$2"
	}
	alias gitcompush=gitcompush

	# Commit, signoff, and push to current branch
	gcp() {
		gitcompush "$1" "$(tb)"
	}
	alias gcp=gcp
	alias gfix="gcp fix"

	# Commit, signoff, and force push with lease
	gitcompushf() {
		git add -A
		git commit --signoff -m "$1"
		git push --force-with-lease --set-upstream origin "$2"
	}
	alias gitcompushf=gitcompushf

	# Commit, signoff, and force push to current branch
	gcpf() {
		gitcompushf "$1" "$(tb)"
	}
	alias gcpf=gcpf

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
	alias gfp=gfp

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
	alias grs=grs

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
	alias grsp=grsp

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
	if (($+commands["fzf-tmux"])); then
		if (($+commands[rg])); then
			fbr() {
				git branch --all | rg -v HEAD | fzf-tmux +m | \sed -E "s/.* //" -e "s#remotes/[^/]*/##" | xargs git checkout
			}
			alias fbr=fbr
		fi
	fi
fi
