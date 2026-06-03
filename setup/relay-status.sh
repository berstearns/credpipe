#!/usr/bin/env bash
# Read-only: is the relay actually serving right now? Service state + listeners
# + reachability from main. Safe to run anytime.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

say "Relay $VPS_SSH — service"
dssh 'echo "active:  $(systemctl is-active credpipe)"; echo "enabled: $(systemctl is-enabled credpipe)"; echo "since:   $(systemctl show credpipe -p ActiveEnterTimestamp --value)"; echo "listeners:"; ss -ltn | grep -E ":(9000|9001)" || echo "  NONE"'

say "Reachability from main (doctor, last line)"
"$REPO_ROOT/credpipe" doctor | tail -1

echo "RELAY_STATUS_DONE"
