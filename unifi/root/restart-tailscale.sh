#!/bin/bash
set -euo pipefail

tailscale up \
  --hostname=udm-pro \
  --advertise-routes=10.0.0.0/24,10.0.1.0/29,10.0.3.0/26 \
  --accept-dns=false \
  --accept-routes=false \
  --stateful-filtering=true \
  --advertise-exit-node \
  --ssh \
  --reset
tailscale set --auto-update
