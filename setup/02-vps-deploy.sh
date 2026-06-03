#!/usr/bin/env bash
# Deploy the credpipe relay to the VPS: transfer binary + unit + bootstrap via the
# do-automation password-auth scripts, then run the bootstrap once (single
# orchestrated remote execution). The relay NEVER receives the key.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR
cd "$REPO_ROOT"

say "Transfer binary + unit + bootstrap -> $VPS_SSH"
dscp ./credpipe                       "$VPS_SSH:$RELAY_BIN"
dscp ./setup/credpipe.service         "$VPS_SSH:/etc/systemd/system/credpipe.service"
dscp ./setup/credpipe-relay-bootstrap.sh "$VPS_SSH:/root/credpipe-relay-bootstrap.sh"

say "Run relay bootstrap (install deps, enable systemd, verify listeners)"
dssh 'bash /root/credpipe-relay-bootstrap.sh'

echo "VPS_DEPLOY_DONE"
