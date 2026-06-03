#!/usr/bin/env bash
# main-side writer loop: push the local Claude creds to the relay on an interval so the
# encrypted blob stays fresh (covers silent token refresh AND heals an emptied mailbox if
# an internet scan zeroed the open push port). Run this in the "main" window.
#   INTERVAL   seconds between pushes (default 120)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
INTERVAL="${INTERVAL:-120}"
echo "credpipe push loop — every ${INTERVAL}s, Ctrl-C to stop"
while true; do
  ./credpipe push || echo "push failed $(date '+%H:%M:%S') — will retry"
  sleep "$INTERVAL"
done
