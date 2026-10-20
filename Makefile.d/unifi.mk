## UDM Pro user-asset management
## -----------------------------------------------------------------------------
## SSoT: dotfiles/unifi/{data,root}/ for user-authored assets on the UDM Pro.
## UniFi controller state (networkconf/setting/wlanconf/...) is intentionally not
## dumped — UniFi Cloud owns that side (see unifi/CONTEXT.md §7 incident log).
## The exception is unifi/controller/: hand-written, secret-free declarations of
## firewall policies, traffic matching lists and the mDNS mode, applied by
## unifi/unifictl (CONTEXT.md Q25–Q31).
##
## Variables (override on the command line):
##   UDM=udmpro           SSH host alias for the UDM Pro (~/.ssh/config)
##   DRY_RUN=1            unifi/install: preview tar+ssh without applying
##   LINES=50             unifi/logs: how many trailing lines per source
##   YES=1                unifi/controller-apply: skip the interactive confirmation

UNIFI_DIR     := $(ROOTDIR)/unifi
UNIFI_SCRIPTS := $(UNIFI_DIR)/scripts
UDM           ?= udmpro

.PHONY: unifi/help unifi/pull unifi/install unifi/dry-run unifi/diff unifi/status unifi/logs \
        unifi/controller-plan unifi/controller-apply unifi/controller-test \
        unifi/f2886q-plan unifi/f2886q-apply

## list only the unifi/ targets with their inline help text
unifi/help:
	@awk '/^## / { desc = (desc == "" ? substr($$0,4) : desc " " substr($$0,4)); next } \
	      /^unifi\/[A-Za-z0-9_-]+:/ && desc != "" { \
	        name = $$1; sub(/:$$/, "", name); \
	        printf "  \033[36m%-24s\033[0m %s\n", name, desc; desc = "" } \
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

## read-only: diff unifi/controller/ declarations against the live controller
unifi/controller-plan:
	@UNIFI_API_KEY="$$(pass show unifi-api)" go run -C $(UNIFI_DIR)/unifictl . -dir $(UNIFI_DIR)/controller plan

## apply unifi/controller/ to the controller (shows the plan, asks for "yes")
unifi/controller-apply:
	@UNIFI_API_KEY="$$(pass show unifi-api)" go run -C $(UNIFI_DIR)/unifictl . -dir $(UNIFI_DIR)/controller $(if $(YES),-yes) apply

## unit tests for unifictl (synthetic fixtures, no controller access)
unifi/controller-test:
	@cd $(UNIFI_DIR)/unifictl && go vet ./... && go test ./...

## read-only: diff F2886Q ONU IPv6 PD state (static prefix / manual mode / delegation)
unifi/f2886q-plan:
	@$(UNIFI_SCRIPTS)/f2886q-apply.sh plan

## enforce F2886Q IPv6 PD state (Static Prefix UDM_PD + DHCPv6/RA PrefixMode=Manual)
unifi/f2886q-apply:
	@$(UNIFI_SCRIPTS)/f2886q-apply.sh apply
