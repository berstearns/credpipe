#!/usr/bin/env bash
# Provision a NON-ROOT user to run interactive Claude Code on a tty node.
# Claude Code refuses --dangerously-skip-permissions as root, so a real tty node runs
# claude as a normal user. This script creates that user (idempotent) and gives them the
# credpipe key, the pulled credentials, and the onboarding flag — everything needed to run
# `claude` (interactive or -p) as that user. Encapsulates what used to be done by hand.
#
# Run as ROOT, AFTER laptop-onboard.sh has installed the key + pulled creds for SRC_HOME.
#
#   RUN_USER       user to create/provision      (default: claude)
#   SRC_HOME       where key+creds currently live (default: /root)
#   CREDPIPE_DEST  repo location                 (default: /opt/credpipe)
#   VERIFY         1 = prove it with `claude -p ping` as the user (default: 1)
set -euo pipefail
RUN_USER="${RUN_USER:-claude}"
SRC_HOME="${SRC_HOME:-/root}"
DEST="${CREDPIPE_DEST:-/opt/credpipe}"
VERIFY="${VERIFY:-1}"

[ "$(id -u)" = "0" ] || { echo "run as root (creates a user, reads $SRC_HOME secrets)" >&2; exit 1; }
[ -s "$SRC_HOME/.config/credpipe/key" ]      || { echo "no key at $SRC_HOME/.config/credpipe/key — run laptop-onboard.sh first" >&2; exit 1; }
[ -s "$SRC_HOME/.claude/.credentials.json" ] || { echo "no creds at $SRC_HOME/.claude/.credentials.json — run laptop-onboard.sh first" >&2; exit 1; }

echo "=== user $RUN_USER ==="
id "$RUN_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$RUN_USER"
HOME_DIR="$(getent passwd "$RUN_USER" | cut -d: -f6)"
echo "home: $HOME_DIR"

echo "=== provision key + creds (mode 600, owned by $RUN_USER) ==="
install -d -o "$RUN_USER" -g "$RUN_USER" -m 700 "$HOME_DIR/.config/credpipe" "$HOME_DIR/.claude"
install -o "$RUN_USER" -g "$RUN_USER" -m 600 "$SRC_HOME/.config/credpipe/key"      "$HOME_DIR/.config/credpipe/key"
install -o "$RUN_USER" -g "$RUN_USER" -m 600 "$SRC_HOME/.claude/.credentials.json" "$HOME_DIR/.claude/.credentials.json"

echo "=== onboarding flag in $HOME_DIR/.claude.json ==="
# interactive claude gates on hasCompletedOnboarding; without it the TUI tries a browser login
if [ -f "$SRC_HOME/.claude.json" ]; then jq '.hasCompletedOnboarding=true' "$SRC_HOME/.claude.json" > "$HOME_DIR/.claude.json"
else echo '{"hasCompletedOnboarding":true}' > "$HOME_DIR/.claude.json"; fi
chown "$RUN_USER:$RUN_USER" "$HOME_DIR/.claude.json"; chmod 600 "$HOME_DIR/.claude.json"
echo "fp $(sha256sum "$HOME_DIR/.config/credpipe/key" | cut -c1-16) | creds $(jq -r '.claudeAiOauth.subscriptionType // "?"' "$HOME_DIR/.claude/.credentials.json")"

# credpipe reads .env next to its binary (/opt/credpipe/.env via the PATH symlink), and the
# user's own key under $HOME — so `credpipe pull` works as $RUN_USER with no extra config.

if [ "$VERIFY" = "1" ] && command -v claude >/dev/null 2>&1; then
  echo "=== verify: claude as $RUN_USER (non-root + --dangerously-skip-permissions) ==="
  if su - "$RUN_USER" -c 'claude --dangerously-skip-permissions -p ping'; then
    echo "OK: interactive-capable claude runs as $RUN_USER"
  else
    echo "WARN: claude test failed as $RUN_USER" >&2
  fi
fi

echo "Run claude as this user with:  su - $RUN_USER -c 'claude --dangerously-skip-permissions'"
echo "SETUP_CLAUDE_USER_DONE"
