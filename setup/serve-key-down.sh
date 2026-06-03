#!/usr/bin/env bash
# Tear down the temporary key-serve: stop Caddy + delete /root/serve on the
# droplet, and remove the dedicated bootstrap firewall. Idempotent.
# Does NOT touch credpipe.service or the relay's 9000/9001 firewall rules.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

SERVE_DIR="$DO_AUTO/serve"

say "Confirm the served ciphertext is about to be removed"
dssh "ls -l /root/serve 2>/dev/null || echo '/root/serve already gone'" || true

say "do-serve-down (deletes the bootstrap firewall; see note below)"
# NOTE: do-serve-down's remote cleanup runs `pkill -f "caddy run"`, which matches
# its OWN shell (cmdline contains that string) and self-kills before the rm -rf —
# so it reliably deletes the firewall but often leaves caddy + /root/serve files.
# We therefore always follow it with the robust purge below.
"$SERVE_DIR/do-serve-down" || true

say "Robust purge (stop caddy via pkill -x, remove our artifacts)"
bash "$(dirname "${BASH_SOURCE[0]}")/serve-key-purge.sh"

echo "SERVE_KEY_DOWN_DONE"
