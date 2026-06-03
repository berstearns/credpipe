#!/usr/bin/env bash
# Serve the credpipe key to a new tty laptop TEMPORARILY and SAFELY via
# do-automation/serve (HTTPS + basicauth + IP-allowlist + fail2ban).
#
# The key is NEVER served raw: it is wrapped with a passphrase first, so only
# CIPHERTEXT reaches the relay droplet or the wire. The passphrase travels
# out-of-band (you type it on the laptop). Tear down with serve-key-down.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

SERVE_DIR="$DO_AUTO/serve"
KEY="$HOME/.config/credpipe/key"
[ -s "$KEY" ] || { echo "no key at $KEY (run: credpipe keygen)"; exit 1; }
[ -x "$SERVE_DIR/do-serve-up" ] || { echo "missing $SERVE_DIR/do-serve-up"; exit 1; }

# Passphrase: from env (non-interactive) or prompt.
PASS="${CREDPIPE_KEY_PASSPHRASE:-}"
if [ -z "$PASS" ]; then
  read -rsp "passphrase to wrap the key (type the SAME one on the laptop): " PASS; echo
fi
[ -n "$PASS" ] || { echo "empty passphrase — aborting"; exit 1; }

say "Wrap key with passphrase (only ciphertext leaves this laptop)"
ENC="$(mktemp /tmp/credpipe-key.XXXXXX.enc)"
PH="$(mktemp /tmp/credpipe-noop.XXXXXX.sh)"
trap 'shred -u "$ENC" "$PH" 2>/dev/null || rm -f "$ENC" "$PH"; on_err $LINENO' ERR
printf '#!/bin/sh\necho "credpipe key relay placeholder — fetch /r.conf, do not pipe to bash"\n' > "$PH"
printf '%s' "$PASS" | openssl enc -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$KEY" -out "$ENC"
echo "wrapped: $(wc -c < "$ENC") bytes ciphertext  (key fp $(sha256sum "$KEY" | cut -c1-16))"

say "Bring up the temporary HTTPS serve (key.enc occupies the /r.conf slot)"
# do-serve-up <i.sh-slot> <r.conf-slot>; we serve the placeholder + the encrypted key.
"$SERVE_DIR/do-serve-up" "$PH" "$ENC"

say "Local cleanup (served copy is the ciphertext on the droplet)"
shred -u "$ENC" "$PH" 2>/dev/null || rm -f "$ENC" "$PH"

cat <<'NOTE'

NEXT:
  - If the fetching laptop is NOT this machine, allow its IP:
      ~/p/all-my-tiny-projects/do-automation/serve/do-serve-allow-ip <laptop-public-ip>
  - Fetch/decrypt/verify on the laptop: see docs/key-distribution.md
  - TEAR DOWN as soon as the laptop has the key:
      bash setup/serve-key-down.sh
NOTE
echo "SERVE_KEY_DONE"
