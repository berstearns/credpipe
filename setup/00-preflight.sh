#!/usr/bin/env bash
# Discover the VPS state before deploying: SSH reachability, remote deps,
# host firewall (ufw), any existing credpipe install, and the DO cloud firewall.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

say "SSH reachability ($VPS_SSH)"
if ssh "${SSH_OPTS[@]}" "$VPS_SSH" 'echo SSH_OK; uname -sr; id -un'; then
  echo "ssh: key-auth OK"
else
  echo "ssh: key-auth FAILED — deploy will need DO_SSH_PASS / do-ssh-pass"
fi

say "Remote deps (socat openssl jq)"
ssh "${SSH_OPTS[@]}" "$VPS_SSH" 'for c in socat openssl jq; do command -v $c >/dev/null && echo "ok   $c" || echo "MISS $c"; done' || true

say "Host firewall (ufw) + any existing credpipe install"
ssh "${SSH_OPTS[@]}" "$VPS_SSH" 'command -v ufw >/dev/null && ufw status 2>/dev/null | head -20 || echo "ufw: not installed/inactive"; echo "---"; ls -l /usr/local/bin/credpipe /etc/systemd/system/credpipe.service 2>/dev/null || echo "no existing credpipe install"' || true

say "DO cloud firewalls (id / name / droplet membership)"
doctl compute firewall list --format ID,Name,DropletIDs 2>&1 | head -20 || echo "doctl firewall list failed"

echo "PREFLIGHT_DONE"
