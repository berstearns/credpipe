#!/usr/bin/env bash
# credpipe setup — shared config + helpers. Sourced by the numbered setup scripts.
#
# Per the project command rules, ALL command logic lives in these committed
# repo scripts; they are dispatched to a titled tmux pane, never run ad-hoc.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Load the git-ignored deployment config. This keeps real IPs / firewall IDs out
# of the public repo — they live only in .env (see .env.example for the keys).
# shellcheck disable=SC1091
[ -f "$REPO_ROOT/.env" ] && { set -a; . "$REPO_ROOT/.env"; set +a; }

# Relay (DigitalOcean droplet) coordinates — from .env (CREDPIPE_HOST), never hardcoded.
VPS_HOST="${VPS_HOST:-${CREDPIPE_HOST:-}}"
VPS_USER="${VPS_USER:-${CREDPIPE_VPS_USER:-root}}"
[ -n "$VPS_HOST" ] || { echo "lib.sh: CREDPIPE_HOST is unset — set it in $REPO_ROOT/.env" >&2; exit 1; }
VPS_SSH="$VPS_USER@$VPS_HOST"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes)

PULL_PORT="${CREDPIPE_PULL_PORT:-9000}"
PUSH_PORT="${CREDPIPE_PUSH_PORT:-9001}"
RELAY_BIN="/usr/local/bin/credpipe"
RELAY_BLOB="/srv/credpipe/creds.enc"

# DigitalOcean tooling (password-auth transport + cloud firewall) — paths/IDs from env/.env.
DO_AUTO="${DO_AUTO:-$HOME/p/all-my-tiny-projects/do-automation}"
DO_FW_ID="${DO_FW_ID:-${CREDPIPE_DO_FW_ID:-}}"               # set CREDPIPE_DO_FW_ID in .env for 03-open-ports
dssh(){ DO_HOST="$VPS_HOST" "$DO_AUTO/do-ssh-pass" "$@"; }   # sshpass-based ssh (see do-automation)
dscp(){ DO_HOST="$VPS_HOST" "$DO_AUTO/do-scp-pass" "$@"; }   # sshpass-based scp (see do-automation)

say(){ printf '\n=== %s ===\n' "$*"; }
on_err(){ echo "CREDPIPE_STEP_ERR (line $1)"; }
