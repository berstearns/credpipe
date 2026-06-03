#!/usr/bin/env bash
# Foreground serve "session": bring the .env + key serve up, then BLOCK. Cancelling this
# (Ctrl-C) — or any exit — automatically tears the serve down. So the serve's lifetime ==
# this pane's process: no serve left running on the relay, no separate teardown step.
#
# Run this in the "serve" window instead of serve-key.sh when you want cancel = teardown.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
HERE_SETUP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_torn=0
cleanup(){
  [ "$_torn" = 1 ] && return 0
  _torn=1
  echo; echo ">>> tearing down the serve (caddy off, key purged, bootstrap firewall deleted)..."
  bash "$HERE_SETUP/serve-key-down.sh" || true
  exit 0
}
trap cleanup INT TERM EXIT     # Ctrl-C / kill / any exit -> teardown

bash "$HERE_SETUP/serve-key.sh"   # prompts (hidden) for the passphrase, brings serve up, prints passcode

echo
echo "=================================================================="
echo "  serve is UP — onboard your node now (use the passcode above)."
echo "  Press Ctrl-C here to TEAR DOWN."
echo "=================================================================="
while :; do sleep 3600; done
