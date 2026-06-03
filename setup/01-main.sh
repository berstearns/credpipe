#!/usr/bin/env bash
# Configure THIS laptop as credpipe "main": write .env, generate the shared key,
# put credpipe on PATH, and run doctor. Idempotent — safe to re-run.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR
cd "$REPO_ROOT"

say "Write .env (CREDPIPE_HOST=$VPS_HOST)"
if [ -f .env ]; then
  echo ".env already exists — leaving it untouched:"
  grep -vE '^\s*(#|$)' .env
else
  {
    echo "# credpipe deployment — generated $(date '+%F %T'). .env is git-ignored."
    echo "CREDPIPE_HOST=$VPS_HOST"
  } > .env
  echo "wrote .env:"; cat .env
fi

say "Generate shared key (only if absent)"
KEY="$HOME/.config/credpipe/key"
if [ -s "$KEY" ]; then
  echo "key already present at $KEY  fp=$(sha256sum "$KEY" | cut -c1-16)"
else
  ./credpipe keygen
fi

say "Symlink credpipe onto PATH"
ln -sfn "$REPO_ROOT/credpipe" "$HOME/.local/bin/credpipe"
ls -l "$HOME/.local/bin/credpipe"

say "credpipe doctor (relay 'NOT reachable' is expected until the VPS serve is up)"
"$REPO_ROOT/credpipe" doctor || true

echo "MAIN_DONE"
