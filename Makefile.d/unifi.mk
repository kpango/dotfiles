## UDM Pro user-asset management
## -----------------------------------------------------------------------------
## SSoT: dotfiles/unifi/{data,root}/ for user-authored assets on the UDM Pro.
## UniFi controller state (networkconf/setting/wlanconf/...) is intentionally not
## tracked — UniFi Cloud owns that side (see unifi/CONTEXT.md §7 incident log).
##
## Variables (override on the command line):
##   UDM=udmpro           SSH host alias for the UDM Pro (~/.ssh/config)
##   DRY_RUN=1            unifi/install: preview tar+ssh without applying
##   LINES=50             unifi/logs: how many trailing lines per source

UNIFI_DIR     := $(ROOTDIR)/unifi
UNIFI_SCRIPTS := $(UNIFI_DIR)/scripts
UDM           ?= udmpro

.PHONY: unifi/help unifi/pull unifi/install unifi/dry-run unifi/diff unifi/status unifi/logs

## list only the unifi/ targets with their inline help text
unifi/help:
	@awk '/^## / { desc = (desc == "" ? substr($$0,4) : desc " " substr($$0,4)); next } \
	      /^unifi\/[A-Za-z_-]+:/ && desc != "" { \
	        name = $$1; sub(/:$$/, "", name); \
	        printf "  \033[36m%-18s\033[0m %s\n", name, desc; desc = "" } \
	      !/^## / { desc = "" }' $(ROOTDIR)/Makefile.d/unifi.mk

## snapshot /data (allowlist) and /root (denylist) from the UDM Pro into unifi/
unifi/pull:
	@UDM=$(UDM) $(UNIFI_SCRIPTS)/unifi-pull.sh

## tar+ssh push unifi/{data,root}/ to the UDM Pro and re-run install hooks
unifi/install:
	@UDM=$(UDM) $(UNIFI_SCRIPTS)/unifi-install.sh

## preview unifi/install (lists what would be pushed, no SSH write)
unifi/dry-run:
	@UDM=$(UDM) DRY_RUN=1 $(UNIFI_SCRIPTS)/unifi-install.sh

## md5sum-based drift report between unifi/{data,root}/ and the UDM Pro
unifi/diff:
	@UDM=$(UDM) $(UNIFI_SCRIPTS)/unifi-diff.sh

## read-only one-shot diagnostic: nextdns/tailscale/systemd/cron snapshot
unifi/status:
	@UDM=$(UDM) $(UNIFI_SCRIPTS)/unifi-status.sh

## tail the UDM Pro-side logs (nextdns.service, healthcheck.log, tailscaled, dmesg)
unifi/logs:
	@UDM=$(UDM) LINES=$(or $(LINES),50) $(UNIFI_SCRIPTS)/unifi-logs.sh
