.PHONY: workflow/lint \
	workflow/fix \
	actionlint/lint \
	ghalint/lint \
	pinact/fix \
	ghatm/fix \
	cprm/lint

ACTIONLINT_IGNORES =

## fail on a bare cp/rm where cpz/rmz must be preferred (zsh/Makefile/Nix/Docker)
cprm/lint:
	@bash $(ROOTDIR)/Makefile.d/scripts/check-cprm.sh $(ROOTDIR)

## run lint for workflow files
workflow/lint: actionlint/lint ghalint/lint

## fix workflow files (SHA-pin actions + set timeout-minutes)
workflow/fix: pinact/fix ghatm/fix

## run actionlint
actionlint/lint:
	@actionlint $(ACTIONLINT_IGNORES)

## run ghalint
ghalint/lint:
	@ghalint run .github/workflows

## run pinact (pin actions to SHA)
pinact/fix:
	@GITHUB_TOKEN=$${GITHUB_TOKEN:-$$(gh auth token 2>/dev/null || :)} pinact run

## run ghatm (set timeout-minutes on all jobs)
ghatm/fix:
	@ghatm set
