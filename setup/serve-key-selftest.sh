#!/usr/bin/env bash
# Prove the temporary key-serve channel end-to-end from THIS machine (whose IP
# do-serve-up already allowlisted): fetch the served ciphertext, decrypt it with
# the passphrase, and confirm the fingerprint matches the real key. Installs
# nothing — decrypts to a temp file and checks the hash.
#
# Required env: SERVE_PASSCODE, CREDPIPE_KEY_PASSPHRASE
#   optional:   SERVE_PORT (default 47823)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

PORT="${SERVE_PORT:-47823}"
: "${SERVE_PASSCODE:?set SERVE_PASSCODE (from serve-key.sh output)}"
: "${CREDPIPE_KEY_PASSPHRASE:?set CREDPIPE_KEY_PASSPHRASE (the one used to wrap)}"

URL="https://$VPS_HOST:$PORT/r.conf"
WANT="$(sha256sum "$HOME/.config/credpipe/key" | cut -c1-16)"

say "Fetch ciphertext from $URL"
enc="$(mktemp)"; out="$(mktemp)"
trap 'rm -f "$enc" "$out"; on_err $LINENO' ERR
curl -fsSL -u "bootstrap:$SERVE_PASSCODE" -k "$URL" -o "$enc"
echo "fetched: $(wc -c < "$enc") bytes"

say "Decrypt with passphrase + compare fingerprint"
printf '%s' "$CREDPIPE_KEY_PASSPHRASE" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in "$enc" -out "$out"
GOT="$(sha256sum "$out" | cut -c1-16)"
echo "want fp: $WANT"
echo "got  fp: $GOT"
rm -f "$enc" "$out"
[ "$WANT" = "$GOT" ] && echo "SELFTEST OK — channel round-trips the key intact" \
                      || { echo "SELFTEST FAILED — fingerprint mismatch"; exit 1; }

echo "SERVE_KEY_SELFTEST_DONE"
