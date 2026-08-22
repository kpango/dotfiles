.PHONY: devbox/install devbox/shell devbox/setup devbox/update devbox/clean

## install Devbox if not present and verify it can run
devbox/install:
	@if ! command -v devbox >/dev/null 2>&1; then \
		echo "=> Installing Devbox..."; \
		curl --retry 3 --retry-all-errors --retry-delay 3 -fsSL https://get.jetpack.io/devbox | bash; \
	else \
		echo "=> Devbox is already installed."; \
	fi
	devbox run true

## drop into a Devbox shell (installs Devbox first if needed)
devbox/shell: devbox/install
	devbox shell

## run devbox setup and update_tools scripts inside the Devbox environment
devbox/setup: devbox/install
	devbox run setup
	devbox run update_tools

## update all Devbox packages to their latest versions
devbox/update:
	devbox update

## remove the .devbox state directory
devbox/clean:
	rm -rf .devbox
	echo "=> Devbox state cleaned."
