#!/usr/bin/env bash
# Install the Claude Code CLI on a tty node + a pull-before-launch wrapper, so every
# `claude` launch first refreshes credentials via credpipe. Idempotent.
# Run AFTER laptop-onboard.sh (which installs the key and pulls the creds).
#
#   CREDPIPE_DEST   where the repo lives (default /opt/credpipe)
#   NODE_MAJOR      Node major version to install if absent (default 22)
set -euo pipefail
DEST="${CREDPIPE_DEST:-/opt/credpipe}"
NODE_MAJOR="${NODE_MAJOR:-22}"
export DEBIAN_FRONTEND=noninteractive TZ="${TZ:-Etc/UTC}"

echo "=== node ==="
if ! command -v node >/dev/null 2>&1; then
  ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime           # preseed tz (avoids tzdata prompt)
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt-get install -y nodejs
fi
echo "node $(node --version)"

echo "=== claude code ==="
command -v claude >/dev/null 2>&1 || npm i -g @anthropic-ai/claude-code
REAL="$(command -v claude)"

echo "=== pull-before-launch wrapper ==="
WRAP=/usr/local/bin/claude
# Never overwrite the real binary with the wrapper. If npm put claude at the wrapper
# path, relocate the real one so the wrapper can shadow it without looping.
if [ "$REAL" = "$WRAP" ]; then
  REAL=/usr/local/lib/credpipe/real-claude
  mkdir -p "$(dirname "$REAL")"; cp "$WRAP" "$REAL"
fi
grep -q '^CREDPIPE_REAL_CLAUDE=' "$DEST/.env" 2>/dev/null \
  || printf 'CREDPIPE_REAL_CLAUDE=%s\n' "$REAL" >> "$DEST/.env"
printf '#!/usr/bin/env sh\nexec %s/credpipe wrap "$@"\n' "$DEST" > "$WRAP"
chmod +x "$WRAP"
hash -r 2>/dev/null || true
echo "wrapper: $WRAP -> credpipe wrap -> $REAL"

echo "=== verify ==="
claude --version
echo "INSTALL_CLAUDE_DONE"
