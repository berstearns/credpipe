#!/usr/bin/env bash
# Onboard a tty node (e.g. a naked Ubuntu container) as a credpipe PULLER.
# Fetches the SOURCE OF TRUTH from main's serve channel — the .env (config) AND the
# passphrase-wrapped key — so nothing (not even CREDPIPE_HOST) is passed inline. Every
# script then reads config from the fetched .env. Idempotent.
#
# Required (only enough to REACH the serve channel — the relay address is the connection
# target, not a config value):
#   RELAY                    relay IP/DNS (serve + relay host)
#   SERVE_PASSCODE           basicauth passcode from serve-key.sh   (prompted if unset)
#   CREDPIPE_KEY_PASSPHRASE  passphrase to decrypt the key          (prompted if unset)
# Optional:
#   SERVE_PORT (default 47823), EXPECTED_FP, CREDPIPE_REPO, CREDPIPE_DEST,
#   INSTALL_CLAUDE=1, RUN_USER=<name>
set -euo pipefail
DEST="${CREDPIPE_DEST:-/opt/credpipe}"
SERVE_PORT="${SERVE_PORT:-47823}"
KEY="$HOME/.config/credpipe/key"
: "${RELAY:?set RELAY to the relay IP/DNS (the serve host)}"

echo "=== 1/6 deps ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openssl socat jq curl git ca-certificates >/dev/null
for c in openssl socat jq curl git; do command -v "$c" >/dev/null || { echo "MISS $c"; exit 1; }; done
echo "deps ok"

echo "=== 2/6 fetch credpipe repo ==="
REPO_URL="${CREDPIPE_REPO:-https://github.com/berstearns/credpipe}"
if [ -d "$DEST/.git" ]; then git -C "$DEST" pull --ff-only; else git clone --depth 1 "$REPO_URL" "$DEST"; fi

# Secrets: prompt if not supplied, so they never have to land in shell history.
if [ -z "${SERVE_PASSCODE:-}" ]; then read -rp "serve passcode: " SERVE_PASSCODE; fi
if [ -z "${CREDPIPE_KEY_PASSPHRASE:-}" ]; then read -rsp "key passphrase: " CREDPIPE_KEY_PASSPHRASE; echo; fi
BASE="https://$RELAY:$SERVE_PORT"
AUTH=(-u "bootstrap:$SERVE_PASSCODE" -k)

echo "=== 3/6 fetch .env (source of truth) from $BASE/i.sh ==="
mkdir -p "$DEST"
curl -fsSL "${AUTH[@]}" "$BASE/i.sh" -o "$DEST/.env"
echo "fetched .env:"; sed 's/^/  /' "$DEST/.env"

echo "=== 4/6 fetch + decrypt key from $BASE/r.conf ==="
mkdir -p "$(dirname "$KEY")"; chmod 700 "$(dirname "$KEY")"
enc="$(mktemp)"
curl -fsSL "${AUTH[@]}" "$BASE/r.conf" -o "$enc"
printf '%s' "$CREDPIPE_KEY_PASSPHRASE" | openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in "$enc" -out "$KEY"
rm -f "$enc"; chmod 600 "$KEY"
FP="$(sha256sum "$KEY" | cut -c1-16)"; echo "key fp: $FP"
if [ -n "${EXPECTED_FP:-}" ] && [ "$FP" != "$EXPECTED_FP" ]; then echo "FP MISMATCH (want $EXPECTED_FP)"; exit 1; fi

echo "=== 5/6 credpipe on PATH ==="
ln -sfn "$DEST/credpipe" /usr/local/bin/credpipe

echo "=== 6/6 doctor + pull (config read from $DEST/.env) ==="
credpipe doctor || true
credpipe pull
CREDS="$HOME/.claude/.credentials.json"
jq -e . "$CREDS" >/dev/null 2>&1 && echo "creds: valid JSON ($(jq -r 'keys|join(",")' "$CREDS"))" || { echo "creds NOT valid"; exit 1; }

echo "=== mark interactive onboarding complete (~/.claude.json) ==="
CJ="$HOME/.claude.json"
if [ -f "$CJ" ]; then jq '.hasCompletedOnboarding=true' "$CJ" > "$CJ.tmp" && mv "$CJ.tmp" "$CJ"
else echo '{"hasCompletedOnboarding":true}' > "$CJ"; fi
chmod 600 "$CJ"

if [ "${INSTALL_CLAUDE:-0}" = "1" ]; then
  echo "=== install claude + pull-before-launch wrapper ==="
  CREDPIPE_DEST="$DEST" bash "$DEST/setup/install-claude.sh"
fi
if [ -n "${RUN_USER:-}" ]; then
  echo "=== provision non-root run user: $RUN_USER ==="
  RUN_USER="$RUN_USER" SRC_HOME="$HOME" CREDPIPE_DEST="$DEST" bash "$DEST/setup/setup-claude-user.sh"
fi

echo "LAPTOP_ONBOARD_DONE"
