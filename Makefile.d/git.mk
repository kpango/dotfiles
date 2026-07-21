.PHONY: git/status git/diff git/commit git/push git/pull git/sync git/check \
        git_status git_diff git_commit git_push git_pull git_sync github_check

MSG ?= "chore: update dotfiles"

## show git working tree status
git/status:
	git status

## show git diff (staged and unstaged)
git/diff:
	git diff

## stage all changes and commit with MSG (default: "chore: update dotfiles")
git/commit:
	git add -A
	git commit -m "$(MSG)" || true

## run git/commit then push to origin
git/push: git/commit
	git push

## pull latest changes with --rebase
git/pull:
	git pull --rebase

## sync: git/pull then git/push
git/sync: git/pull git/push

## verify GitHub API access and rate limit using GITHUB_ACCESS_TOKEN
git/check:
	curl --retry 3 --retry-all-errors --retry-delay 3 --request GET \
		-H "Authorization: Bearer $(GITHUB_ACCESS_TOKEN)" \
		--url https://api.github.com/octocat
	curl --retry 3 --retry-all-errors --retry-delay 3 --request GET \
		-H "Authorization: Bearer $(GITHUB_ACCESS_TOKEN)" \
		--url https://api.github.com/rate_limit

# ── Backward-compat aliases ───────────────────────────────────────────────────

git_status:   ; @$(MAKE) git/status
git_diff:     ; @$(MAKE) git/diff
git_commit:   ; @$(MAKE) git/commit
git_push:     ; @$(MAKE) git/push
git_pull:     ; @$(MAKE) git/pull
git_sync:     ; @$(MAKE) git/sync
github_check: ; @$(MAKE) git/check
