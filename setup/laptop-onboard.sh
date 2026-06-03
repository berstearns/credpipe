#!/usr/bin/env bash
# Run this ON a fresh tty node (e.g. a naked Ubuntu container) to make it a
# credpipe PULLER: install deps, fetch the public repo, install the shared key
# out-of-band, and pull the live Claude credentials. Idempotent.
#
# Required env:
#   CREDPIPE_HOST            relay IP/DNS (e.g. 203.0.113.10)
#
# Key acquisition — choose ONE:
#   (A) fetch from a running `serve-key.sh` channel on main:
#         KEY_URL=https://<relay>:47823/r.conf
#         SERVE_PASSCODE=XXXX-XXXX-XXXX-XXXX     (printed by serve-key.sh)
#         CREDPIPE_KEY_PASSPHRASE=...            (the SAME one you typed on main)
#   (B) the key is already at ~/.config/credpipe/key  (copied by scp/USB/paste)
#
# Optional:
#   EXPECTED_FP=<16 hex>     verify the key fp matches main (from `credpipe doctor`)
#   CREDPIPE_REPO=<url>      default https://github.com/berstearns/credpipe
#   CREDPIPE_DEST=<dir>      default /opt/credpipe
#   INSTALL_CLAUDE=1         also install the claude CLI + a pull-before-launch wrapper
set -euo pipefail

: "${CREDPIPE_HOST:?set CREDPIPE_HOST to the relay IP/DNS}"
REPO_URL="${CREDPIPE_REPO:-https://github.com/berstearns/credpipe}"
DEST="${CREDPIPE_DEST:-/opt/credpipe}"
KEY="$HOME/.config/credpipe/key"

echo "=== 1/6 deps ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssl socat jq curl git ca-certificates >/dev/null
for c in openssl socat jq curl git; do command -v "$c" >/dev/null && echo "ok   $c" || { echo "MISS $c"; exit 1; }; done

echo "=== 2/6 fetch credpipe ($REPO_URL) ==="
if [ -d "$DEST/.git" ]; then git -C "$DEST" pull --ff-only; else git clone --depth 1 "$REPO_URL" "$DEST"; fi

echo "=== 3/6 .env (CREDPIPE_HOST=$CREDPIPE_HOST) ==="
printf 'CREDPIPE_HOST=%s\n' "$CREDPIPE_HOST" > "$DEST/.env"
cat "$DEST/.env"

echo "=== 4/6 shared key ==="
mkdir -p "$(dirname "$KEY")"; chmod 700 "$(dirname "$KEY")"
if [ -s "$KEY" ]; then
  echo "key already present at $KEY"
elif [ -n "${KEY_URL:-}" ]; then
  : "${SERVE_PASSCODE:?set SERVE_PASSCODE}"; : "${CREDPIPE_KEY_PASSPHRASE:?set CREDPIPE_KEY_PASSPHRASE}"
  enc="$(mktemp)"
  curl -fsSL -u "bootstrap:$SERVE_PASSCODE" -k "$KEY_URL" -o "$enc"
  printf '%s' "$CREDPIPE_KEY_PASSPHRASE" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in "$enc" -out "$KEY"
  rm -f "$enc"; chmod 600 "$KEY"
  echo "key fetched + decrypted -> $KEY"
else
  echo "no key at $KEY and no KEY_URL set — provide one (see header)" >&2; exit 1
fi
FP="$(sha256sum "$KEY" | cut -c1-16)"
echo "key fp: $FP"
if [ -n "${EXPECTED_FP:-}" ] && [ "$FP" != "$EXPECTED_FP" ]; then
  echo "FP MISMATCH (want $EXPECTED_FP) — wrong passphrase or corrupt key; not using it" >&2
  exit 1
fi

echo "=== 5/6 credpipe on PATH ==="
ln -sfn "$DEST/credpipe" /usr/local/bin/credpipe
ls -l /usr/local/bin/credpipe

echo "=== 6/6 doctor + pull ==="
credpipe doctor || true
credpipe pull
CREDS="$HOME/.claude/.credentials.json"
if jq -e . "$CREDS" >/dev/null 2>&1; then
  echo "creds installed: valid JSON ($(wc -c < "$CREDS") bytes), keys: $(jq -r 'keys|join(",")' "$CREDS")"
else
  echo "creds NOT valid JSON at $CREDS" >&2; exit 1
fi

echo "=== mark interactive onboarding complete (~/.claude.json) ==="
# credpipe syncs only the token (.credentials.json). Interactive claude ALSO gates on
# hasCompletedOnboarding in ~/.claude.json — if unset it shows the first-run "Select
# login method" screen and tries a browser login (impossible headless). Set it so the
# TUI uses the synced token directly. (-p / print mode already works without this.)
CJ="$HOME/.claude.json"
if [ -f "$CJ" ]; then jq '.hasCompletedOnboarding=true' "$CJ" > "$CJ.tmp" && mv "$CJ.tmp" "$CJ"
else echo '{"hasCompletedOnboarding":true}' > "$CJ"; fi
chmod 600 "$CJ"; echo "set hasCompletedOnboarding=true in $CJ"

if [ "${INSTALL_CLAUDE:-0}" = "1" ]; then
  echo "=== optional: claude CLI + pull-before-launch wrapper ==="
  CREDPIPE_DEST="$DEST" bash "$DEST/setup/install-claude.sh"
fi

# Interactive Claude Code refuses --dangerously-skip-permissions as root. Set RUN_USER to
# provision a non-root user (key + creds + onboarding flag) that can run claude.
if [ -n "${RUN_USER:-}" ]; then
  echo "=== provision non-root run user: $RUN_USER ==="
  RUN_USER="$RUN_USER" SRC_HOME="$HOME" CREDPIPE_DEST="$DEST" bash "$DEST/setup/setup-claude-user.sh"
fi

echo "LAPTOP_ONBOARD_DONE"
