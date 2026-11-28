---
title: Never run live ethtool -G/-C on UDM Pro al_eth interfaces
author: Kpango
date: 2026-11-25
branch: main
cost: { minutes: 667, tokens: 10318659 }
id: l-bdb7f9a5
scope: repo
status: active
src: agent
touches:
  - unifi/controller/firewall-policies.json
  - unifi/data/udm-mape-fallback/udm-mape-fallback.sh
  - ".gemini/settings.json"
  - ".github/actions/docker/action.yaml"
  - ".github/dependabot.yaml"
  - ".github/workflows/agent-sync-verify.yaml"
  - ".github/workflows/cprm-lint.yaml"
  - ".github/workflows/docker-matrix.yaml"
  - ".github/workflows/docker-reusable.yaml"
  - ".github/workflows/github-actions-workflow-linter.yaml"
---

## Decided

- Never execute live `ethtool -G`, `ethtool -C`, `ethtool -K`, or any NIC ring/queue/driver-resetting command on UDM Pro (`al_eth`) interfaces (`eth8`, `eth9`, `eth10`, `switch0`, `br*`).
- Require concrete live telemetry (`ethtool -S`, `ip -s link`, `/proc/net/softnet_stat`, `conntrack -S`) proving actual drops or bottlenecks before proposing low-layer kernel or NIC tuning.
- Keep permanent guards in `agent/agents/unifi-expert.md`, `agent/skills/unifi-api/SKILL.md`, and `unifi/CONTEXT.md` (Inv-10 + Incident Log).

## Tried and ruled out

- Running `ethtool -G eth9 tx 4096` after `ethtool -G eth10 tx 4096` on live UDM Pro (`4.19.152-ui-alpine`, `al_eth` driver) while `eth9` was bridge slave of `br0` and parent of `eth9.2`/`eth9.3`: caused an immediate hang, total network loss, and PostgreSQL/overlayfs corruption requiring a Factory Reset.

## Watch out

- Read-only queries (`ethtool -g`, `ethtool -c`, `ethtool -k`, `ethtool -S`) are safe.
- After Factory Reset, `make unifi/install` requires `/data/nextdns-client-names/api-key`, NextDNS CLI reinstall (after `guard.sh pins`), and restoring Tailscale IP in `~/.ssh/config`.
