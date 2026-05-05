.PHONY: git_status git_diff git_commit git_push git_pull git_sync github_check

MSG ?= "chore: update dotfiles"

git_status:
	git status

git_diff:
	git diff

git_commit:
	git add -A
	git commit -m "$(MSG)" || true

git_push: git_commit
	git push

git_pull:
	git pull --rebase

git_sync: git_pull git_push

github_check:
	curl --retry 3 --retry-all-errors --retry-delay 3 --request GET \
		-H "Authorization: Bearer $(GITHUB_ACCESS_TOKEN)" \
		--url https://api.github.com/octocat
	curl --retry 3 --retry-all-errors --retry-delay 3 --request GET \
		-H "Authorization: Bearer $(GITHUB_ACCESS_TOKEN)" \
		--url https://api.github.com/rate_limit