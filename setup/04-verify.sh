#!/usr/bin/env bash
# End-to-end verification of the main -> relay path:
#   1. doctor (relay reachable on :pull)
#   2. push from main
#   3. read-only check that the encrypted blob landed on the relay
#   4. round-trip: fetch the blob, decrypt with OUR key, confirm valid JSON
#      WITHOUT overwriting the live credentials (the reader path, proven safely).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR
cd "$REPO_ROOT"

say "1) credpipe doctor"
"$REPO_ROOT/credpipe" doctor || true

say "2) push (main -> relay)"
"$REPO_ROOT/credpipe" push

say "3) blob on relay (read-only)"
dssh "ls -l $RELAY_BLOB; echo -n 'sha256 '; sha256sum $RELAY_BLOB | cut -c1-16"

say "4) round-trip decrypt (no install) — proves the reader path"
tmp="$(mktemp)"; trap 'rm -f "$tmp"; on_err $LINENO' ERR
if socat - TCP:"$VPS_HOST":"$PULL_PORT" | openssl enc -d -aes-256-cbc -pbkdf2 \
      -pass file:"$HOME/.config/credpipe/key" > "$tmp" 2>/dev/null \
   && jq -e . "$tmp" >/dev/null 2>&1; then
  echo "round-trip OK: blob decrypts to valid JSON ($(wc -c < "$tmp") bytes)"
  echo "top-level keys: $(jq -r 'keys | join(", ")' "$tmp")"
else
  echo "round-trip FAILED: blob did not decrypt to valid JSON"; rm -f "$tmp"; exit 1
fi
rm -f "$tmp"

echo "VERIFY_DONE"
