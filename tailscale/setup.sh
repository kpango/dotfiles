#!/usr/bin/env bash
# Tailscale node preferences — idempotent, run after auth
set -euo pipefail

# Allow the current user to run tailscale set without sudo
sudo tailscale set --operator="$(id -un)"

tailscale set \
  --ssh=true \
  --accept-routes=true \
  --accept-dns=true \
  --shields-up=false \
  --advertise-routes=10.0.0.0/24

# Write ListenAddress into a separate gitignored drop-in (keeps the IP out of the public repo)
_ts_ip="$(tailscale ip -4)"
printf 'ListenAddress %s\n' "$_ts_ip" | sudo tee /etc/ssh/sshd_config.d/11-tailscale-addr.conf > /dev/null
sudo systemctl reload-or-restart sshd
echo "tailscale: sshd ListenAddress set to ${_ts_ip}"

echo "tailscale: preferences applied"
echo "tailscale: $(tailscale ip -4)"
echo "tailscale: advertised routes: $(tailscale status --json | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d["Self"].get("AdvertisedRoutes"))')"
echo ""
echo "NOTE: ACL policy (hosts aliases, noexpiry, SSH accept) must be applied"
echo "  via the Tailscale admin console: https://login.tailscale.com/admin/acls"
echo "  Full policy (with IPs): pass/tailscale-acl.hujson"
echo "  Structure template (public): dotfiles/tailscale/acl.hujson.tmpl"
