# Runbook: TTY node as a credpipe pulling loop

How to turn a headless / browser-less node (e.g. a naked Ubuntu container) into a
credpipe **puller** that keeps its Claude OAuth creds fresh on a timer.

> ⚠️ **Do not put your real relay IP, key fingerprint, or credentials in this file.**
> This runbook lives under `runbooks/` which **is tracked and pushed**. Per-run
> notes that contain real deployment specifics belong in `runbook/` (gitignored).
> Everything below uses placeholders: `<RELAY_IP>`, `<PULL_PORT>` (default `9000`).

## Prerequisites

- The node already has the shared key at `~/.config/credpipe/key`, distributed
  out-of-band (see `setup/laptop-onboard.sh` and `docs/key-distribution.md`).
  Its fingerprint **must** match every other machine.
- The credpipe checkout and its `.env` (with `CREDPIPE_HOST=<RELAY_IP>`) are in
  place — `laptop-onboard.sh` writes these to `/opt/credpipe`.
- The relay (`serve`) is running and reachable on `<PULL_PORT>`.

## 1. Dependencies

`pull` needs `openssl`, `socat`, `jq`. To run the loop in a session you also want
`tmux`.

```bash
for c in openssl socat jq; do command -v "$c" >/dev/null || echo "MISS $c"; done
```

### tmux without root

On a locked-down node with no `sudo`, install tmux into your home dir instead of
system-wide:

```bash
cd /tmp && apt-get download tmux libevent-core-2.1-7t64 libutempter0
for d in tmux*.deb libevent-core*.deb libutempter0*.deb; do
  dpkg-deb -x "$d" "$HOME/.local/tmuxroot"
done

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/tmux" <<'EOF'
#!/usr/bin/env bash
export LD_LIBRARY_PATH="$HOME/.local/tmuxroot/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$HOME/.local/tmuxroot/usr/bin/tmux" "$@"
EOF
chmod +x "$HOME/.local/bin/tmux"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
export PATH="$HOME/.local/bin:$PATH"
tmux -V
```

## 2. Verify health before looping

```bash
/opt/credpipe/credpipe doctor
```

Confirm: deps `ok`, `host` is your relay, key fingerprint matches all machines,
and `relay : reachable on :<PULL_PORT>`. If the relay is unreachable, fix the
firewall / `serve` before continuing — don't loop on a dead endpoint.

## 3. One test pull

```bash
/opt/credpipe/credpipe pull
jq -e . "$HOME/.claude/.credentials.json" >/dev/null && echo "creds valid json"
```

`pull` is safe to repeat: it fetches the encrypted blob, decrypts locally, and
**only** installs (`0600`) if the result is valid JSON — otherwise it keeps the
current creds.

## 4. Start the pulling loop in tmux

```bash
mkdir -p "$HOME/.credpipe"
tmux kill-session -t credpipe 2>/dev/null || true
tmux new-session -d -s credpipe \
  "while true; do /opt/credpipe/credpipe pull >> '$HOME/.credpipe/pull.log' 2>&1; sleep 300; done"
tmux ls
```

This refreshes creds every 300s. Tune the interval to be a bit shorter than your
OAuth token lifetime so a refreshed token on `main` propagates before expiry.

## 5. Operate

```bash
tmux attach -t credpipe        # watch live; Ctrl-b d to detach
tail -f ~/.credpipe/pull.log   # follow pulls
tmux kill-session -t credpipe  # stop syncing
```

## 6. Survive reboot (optional)

A home-dir tmux session does not survive reboot. To auto-start, add a user cron
entry (no root needed):

```bash
( crontab -l 2>/dev/null; \
  echo '@reboot tmux new-session -d -s credpipe "while true; do /opt/credpipe/credpipe pull >> $HOME/.credpipe/pull.log 2>&1; sleep 300; done"' \
) | crontab -
```

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `relay : NOT reachable` | relay `serve` running? firewall open on `<PULL_PORT>` to this node's IP? |
| `pull: fetch/decrypt failed` | key fingerprint matches `main`? relay actually has a blob (has `main` pushed)? |
| `pull: blob not valid json` | stale/corrupt blob on relay; re-`push` from `main` |
| claude still asks to log in | `hasCompletedOnboarding` not set — see `setup/laptop-onboard.sh` |
