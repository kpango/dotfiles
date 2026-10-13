.PHONY: git/status git/diff git/commit git/push git/pull git/sync git/check \
        git_status git_diff git_commit git_push git_pull git_sync github_check

MSG ?= "chore: update dotfiles"

## show git working tree status
git/status:
	git status

## show git diff (staged and unstaged)
git/diff:
	git diff

## stage tracked changes and commit with MSG (default: "chore: update dotfiles")
git/commit:
	git add -u
	git diff --staged --quiet || git commit -m "$(MSG)"
	@# `git add -u` failing (dirty index lock, permission issue, ...) is not
	@# masked here: each recipe line is its own shell invocation, and Make's
	@# default behavior aborts the target the moment any line exits non-zero
	@# (verified empirically) -- a failed `add` never reaches the `git diff`
	@# line at all, so no extra `|| exit 1` is needed to catch it. (Not the
	@# same situation as install.mk's `jq ... || { echo ...; exit 1; }`:
	@# there `exit 1` is load-bearing because it's the second half of a `||`
	@# inside a single recipe line -- without it, `echo`'s own success would
	@# reset that one line's exit status back to 0, which line-level
	@# fail-fast here has no equivalent of since there's nothing after
	@# the `||` to reset it.)

## run git/commit then push to origin
git/push: git/commit
	git push

## pull latest changes with --rebase
git/pull:
	git pull --rebase

## sync: git/pull then git/push
git/sync: git/pull git/push

# `-K -` (config from stdin) instead of `-H "Authorization: Bearer $$GH_TOKEN"`:
# the latter puts the token in curl's argv, visible to any other user on the
# same host via ps/procfs for the command's duration -- same class of leak
# _keygen's -P removal (ssh-gpg.zsh) closes for ssh-keygen. Piped stdin never
# shows up in argv.
## verify GitHub API access and rate limit using a `pass`-sourced GitHub token
git/check:
	GH_TOKEN="$${GITHUB_ACCESS_TOKEN:-$$(pass github.api.ro.token 2>/dev/null)}" && \
	printf 'header = "Authorization: Bearer %s"\n' "$$GH_TOKEN" | curl -K - --retry 3 --retry-all-errors --retry-delay 3 --request GET \
		--url https://api.github.com/octocat && \
	printf 'header = "Authorization: Bearer %s"\n' "$$GH_TOKEN" | curl -K - --retry 3 --retry-all-errors --retry-delay 3 --request GET \
		--url https://api.github.com/rate_limit

# ── Backward-compat aliases ───────────────────────────────────────────────────

git_status:   ; @$(MAKE) git/status
git_diff:     ; @$(MAKE) git/diff
git_commit:   ; @$(MAKE) git/commit
git_push:     ; @$(MAKE) git/push
git_pull:     ; @$(MAKE) git/pull
git_sync:     ; @$(MAKE) git/sync
github_check: ; @$(MAKE) git/check
