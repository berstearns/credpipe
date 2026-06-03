# pane: `tty-node` (window 2) — the READER (naked Ubuntu container)

Role: a fresh `ubuntu:24.04` container that fetches its config + key + creds from the serve/relay
and stands up Claude Code. Session `credpipe-demo`, pane title `cp-tty`.

> Real per-deployment values are masked as `<…>`. Unmasked copy: git-ignored `runbook/`.

## 1. Start the container (in the window's host shell)

```sh
docker run -it --rm --name credpipe-tty-demo ubuntu:24.04 bash
```
For a real node add `--dns 1.1.1.1` (see the DNS gotcha below).

## 2. DNS fix (inside the container) — needed once

```sh
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf
```
Why: the container inherited the host's `systemd-resolved` stub (`127.0.0.53`), unreachable from
inside Docker → `Temporary failure resolving archive.ubuntu.com`. (The relay fetch is by IP, so
it never needed DNS.)

## 3. Onboard — one fully non-interactive command

```sh
apt-get update && apt-get install -y git curl ca-certificates \
  && git clone --depth 1 https://github.com/berstearns/credpipe /opt/credpipe
RELAY=<relay-ip> \
SERVE_PASSCODE=<passcode-from-serve-logs> \
CREDPIPE_KEY_PASSPHRASE='<passphrase>' \
EXPECTED_FP=<key-fp> \
INSTALL_CLAUDE=1 RUN_USER=claude \
bash /opt/credpipe/setup/laptop-onboard.sh
```

What `laptop-onboard.sh` does (no prompts — all env from the command):
1. installs deps, 2. updates the repo, 3. `curl`s `.env` from the serve (`/i.sh`) → `/opt/credpipe/.env`,
4. `curl`s + decrypts the key (`/r.conf`) and verifies fp `<key-fp>`,
5. symlinks `credpipe`, 6. `credpipe pull` → `~/.claude/.credentials.json`,
then sets `hasCompletedOnboarding`, installs Node + Claude Code + wrapper, and provisions the
non-root `claude` user. Ends: `Pong! 🏓 … LAPTOP_ONBOARD_DONE`.

You fill only **`SERVE_PASSCODE`** (from the serve logs); the passphrase matches the serve.

## 4. Use Claude Code (as the non-root user)

```sh
su - claude -c 'claude --dangerously-skip-permissions'
```

## Notes

- `--dangerously-skip-permissions` is refused as root → claude runs as the `claude` user.
- Verified live: subscription `max`, real authenticated `Pong! 🏓`.
