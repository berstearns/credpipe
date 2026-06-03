#!/usr/bin/env bash
# Read-only relay diagnostics: service state + recent journal + listener check.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

say "systemctl status (read-only)"
dssh "systemctl --no-pager --full status credpipe | head -16" || true

say "journal (last 30 lines)"
dssh "journalctl -u credpipe -n 30 --no-pager" || true

say "listeners"
dssh "ss -ltnp | grep -E ':(${PULL_PORT}|${PUSH_PORT})\b' || echo 'none'" || true

echo "RELAY_LOGS_DONE"
