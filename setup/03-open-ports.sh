#!/usr/bin/env bash
# Additively open the relay ports (9000 pull / 9001 push) on the DO cloud firewall
# to 0.0.0.0/0 + ::/0 — credpipe's documented model (pull serves only ciphertext;
# push is gated by the reader's jq check). Does NOT touch the existing SSH rule.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

[ -n "$DO_FW_ID" ] || { echo "set CREDPIPE_DO_FW_ID in .env (your DO cloud firewall id: doctl compute firewall list)" >&2; exit 1; }

say "Firewall BEFORE"
doctl compute firewall get "$DO_FW_ID" --format InboundRules --no-header 2>&1 || true

for port in "$PULL_PORT" "$PUSH_PORT"; do
  say "Open tcp:$port (idempotent add-rules)"
  doctl compute firewall add-rules "$DO_FW_ID" \
    --inbound-rules "protocol:tcp,ports:$port,address:0.0.0.0/0,address:::/0" \
    && echo "added tcp:$port" || echo "add-rules tcp:$port returned non-zero (may already exist)"
done

say "Firewall AFTER"
doctl compute firewall get "$DO_FW_ID" --format InboundRules --no-header 2>&1 || true

echo "OPEN_PORTS_DONE"
