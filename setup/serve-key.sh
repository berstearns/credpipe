#!/usr/bin/env bash
# Serve BOTH the credpipe config (.env) AND the secret key to a tty node, temporarily,
# via do-automation/serve (HTTPS + basicauth + IP-allowlist + fail2ban).
#
# main's .env + ~/.config/credpipe/key are the SOURCE OF TRUTH. The node fetches them and
# every script reads config from the fetched .env — nothing is passed inline. The key is
# passphrase-wrapped (only ciphertext leaves here); the .env is non-secret config (relay
# host) and rides the already-gated channel as-is.
#
# do-serve-up exposes two slots:  /i.sh  <- the .env (config)   /r.conf <- key.enc (secret)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

SERVE_DIR="$DO_AUTO/serve"
KEY="$HOME/.config/credpipe/key"
[ -s "$KEY" ]                 || { echo "no key at $KEY (run: credpipe keygen)"; exit 1; }
[ -x "$SERVE_DIR/do-serve-up" ] || { echo "missing $SERVE_DIR/do-serve-up"; exit 1; }

# Passphrase from a hidden prompt by default (keeps it out of shell history); env override.
PASS="${CREDPIPE_KEY_PASSPHRASE:-}"
if [ -z "$PASS" ]; then read -rsp "passphrase to wrap the key (type the SAME on the node): " PASS; echo; fi
[ -n "$PASS" ] || { echo "empty passphrase — aborting"; exit 1; }

say "Build the tty .env from main's source of truth ($REPO_ROOT/.env)"
ENVF="$(mktemp /tmp/credpipe-env.XXXXXX)"
ENC="$(mktemp /tmp/credpipe-key.XXXXXX.enc)"
trap 'shred -u "$ENVF" "$ENC" 2>/dev/null || rm -f "$ENVF" "$ENC"; on_err $LINENO' ERR
{
  echo "# credpipe tty config — fetched from main (source of truth: main's .env)"
  echo "CREDPIPE_HOST=$VPS_HOST"
  if [ "$PULL_PORT" != 9000 ]; then echo "CREDPIPE_PULL_PORT=$PULL_PORT"; fi
  if [ "$PUSH_PORT" != 9001 ]; then echo "CREDPIPE_PUSH_PORT=$PUSH_PORT"; fi
} > "$ENVF"
echo "served .env:"; sed 's/^/  /' "$ENVF"

say "Wrap the key (only ciphertext leaves this laptop)"
printf '%s' "$PASS" | openssl enc -aes-256-cbc -pbkdf2 -salt -pass stdin -in "$KEY" -out "$ENC"
echo "key fp $(sha256sum "$KEY" | cut -c1-16) -> $(wc -c < "$ENC") bytes ciphertext"

say "Serve  /i.sh = .env   /r.conf = key.enc  (firewall locks to THIS host's IP)"
"$SERVE_DIR/do-serve-up" "$ENVF" "$ENC"

shred -u "$ENVF" "$ENC" 2>/dev/null || rm -f "$ENVF" "$ENC"
cat <<'NOTE'

NEXT on the node (config + key both come from the serve — no CREDPIPE_HOST inline):
  RELAY=<relay-ip> SERVE_PASSCODE=<above> bash /opt/credpipe/setup/laptop-onboard.sh
  (it prompts for the passphrase; add INSTALL_CLAUDE=1 RUN_USER=claude for full setup)
If the node egresses from another IP:  ./do-serve-allow-ip <node-ip>
TEAR DOWN when done:  bash setup/serve-key-down.sh
NOTE
echo "SERVE_KEY_DONE"
