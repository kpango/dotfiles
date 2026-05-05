.PHONY: devbox/install devbox/shell devbox/setup devbox/update devbox/clean

devbox/install:
	@if ! command -v devbox >/dev/null 2>&1; then \
		echo "=> Installing Devbox..."; \
		curl --retry 3 --retry-all-errors --retry-delay 3 -fsSL https://get.jetpack.io/devbox | bash; \
	else \
		echo "=> Devbox is already installed."; \
	fi
	devbox run true

devbox/shell: devbox/install
	devbox shell

devbox/setup: devbox/install
	devbox run setup
	devbox run update_tools

devbox/update:
	devbox update

devbox/clean:
	rm -rf .devbox
	echo "=> Devbox state cleaned."
