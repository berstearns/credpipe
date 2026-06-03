#!/usr/bin/env bash
# RUNS ON THE RELAY (DigitalOcean droplet). All relay-side mutations live here so
# the deploy is a single orchestrated execution, not scattered raw `ssh "mutate"`
# calls. Transferred + invoked by setup/02-vps-deploy.sh.
#
# Assumes the binary + unit file were already scp'd to:
#   /usr/local/bin/credpipe              (the credpipe script)
#   /etc/systemd/system/credpipe.service (the unit)
set -euo pipefail

PULL_PORT="${CREDPIPE_PULL_PORT:-9000}"
PUSH_PORT="${CREDPIPE_PUSH_PORT:-9001}"

echo "=== deps (socat openssl) ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq socat openssl >/dev/null
for c in socat openssl; do command -v "$c" >/dev/null && echo "ok   $c" || echo "MISS $c"; done

echo "=== binary + blob dir ==="
chmod +x /usr/local/bin/credpipe
mkdir -p /srv/credpipe
ls -l /usr/local/bin/credpipe

echo "=== systemd (re)start to pick up current binary ==="
systemctl daemon-reload
systemctl enable credpipe >/dev/null 2>&1 || true
systemctl restart credpipe
sleep 2
systemctl is-active credpipe && echo "active: yes" || echo "active: NO"

echo "=== listeners ==="
ss -ltnp 2>/dev/null | grep -E ":(${PULL_PORT}|${PUSH_PORT})\b" || echo "no listeners on :${PULL_PORT}/:${PUSH_PORT}"

echo "RELAY_BOOTSTRAP_DONE"
