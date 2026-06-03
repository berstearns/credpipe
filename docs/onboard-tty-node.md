# Onboard a tty node (e.g. a naked Ubuntu container)

Make a fresh, browser-less machine a credpipe **puller**: it gets the shared key
out-of-band and pulls the live Claude credentials. Two sides: **main** serves the key
briefly; the **node** runs one script.

Prereqs: the relay is up (`bash setup/relay-status.sh`), and you know the relay IP and
the key fingerprint (`credpipe doctor` on main).

---

## Side A — on MAIN: serve the key temporarily

```sh
cd ~/p/credpipe-main
CREDPIPE_KEY_PASSPHRASE='pick-a-strong-passphrase' bash setup/serve-key.sh
```

This wraps the key with your passphrase (only ciphertext leaves main / touches the relay),
serves it over HTTPS+basicauth, and prints a **passcode** and the URL
`https://<relay>:47823/r.conf`. The bootstrap firewall is locked to *main's* public IP.

**If the node egresses from a different public IP than main** (a remote box, or a container
on another host), allow it:

```sh
~/p/all-my-tiny-projects/do-automation/serve/do-serve-allow-ip <node-public-ip>
```

> A Docker container on main's host egresses via main's public IP — already allowed, nothing
> to do. A container elsewhere uses that host's IP — allow it.

---

## Side B — on the NODE (the container): one script

The node needs four things, passed as env: the relay IP, the serve URL + passcode, and the
passphrase. Then:

```sh
apt-get update && apt-get install -y git curl ca-certificates
git clone --depth 1 https://github.com/berstearns/credpipe /opt/credpipe

RELAY='<relay-ip>' SERVE_PASSCODE='<passcode-from-serve-key.sh>' \
bash /opt/credpipe/setup/laptop-onboard.sh        # prompts (hidden) for the key passphrase
```

You pass **only** `RELAY` (the address to reach the serve — the connection target, not a
config value) and the passcode. **No `CREDPIPE_HOST` inline** — that comes from the served
`.env`. `laptop-onboard.sh` then:
1. installs deps (`openssl socat jq curl git ca-certificates`),
2. updates the repo at `/opt/credpipe`,
3. **fetches `.env` from the serve** (`/i.sh`) → the source of truth every script reads,
4. **fetches the key** from the serve (`/r.conf`), decrypts it with the passphrase, installs
   `~/.config/credpipe/key` (mode 600), and verifies the fingerprint (if `EXPECTED_FP` set),
5. symlinks `credpipe` onto PATH,
6. `credpipe doctor` + `credpipe pull` (reading the fetched `.env`) → installs
   `~/.claude/.credentials.json` and confirms it's valid JSON.

Secrets (`SERVE_PASSCODE`, passphrase) are prompted if omitted, so they needn't touch
shell history. Add `EXPECTED_FP=<fp>` to assert the key fingerprint.

### Fully self-contained one-liner (clone + run from the repo)

```sh
apt-get update && apt-get install -y git curl ca-certificates
git clone --depth 1 https://github.com/berstearns/credpipe /opt/credpipe
RELAY='<relay-ip>' SERVE_PASSCODE='<passcode>' EXPECTED_FP='<fp>' \
INSTALL_CLAUDE=1 RUN_USER=claude \
bash /opt/credpipe/setup/laptop-onboard.sh        # prompts (hidden) for the passphrase
```

With `INSTALL_CLAUDE=1 RUN_USER=claude`, that single command does **everything**: deps →
clone → `.env` → key fetch+verify → pull creds → onboarding flag → install Node + Claude
Code + pull-before-launch wrapper → provision the non-root `claude` user (key + creds +
flag) and verify `claude -p ping` runs as them. Then: `su - claude -c 'claude --dangerously-skip-permissions'`.

---

## Side A — on MAIN: tear the serve down (the moment the node has the key)

```sh
cd ~/p/credpipe-main
bash setup/serve-key-down.sh
```

---

## Keep the node current (optional)

```cron
# pull more often than the access-token lifetime so the node rarely refreshes on its own
*/2 * * * * /usr/local/bin/credpipe pull >> ~/.cache/credpipe.log 2>&1
```

With `INSTALL_CLAUDE=1`, every `claude` launch also pulls first (the `wrap` shim).

## Running Claude Code interactively (subscription)

credpipe syncs only the OAuth token (`~/.claude/.credentials.json`). Two extra things are
needed for the **interactive** TUI with a Claude subscription (non-interactive `claude -p`
works with just the token):

1. **Onboarding flag.** Interactive claude gates on `hasCompletedOnboarding` in
   `~/.claude.json`; if unset it shows the first-run *"Select login method"* screen and
   tries a browser login (impossible headless). `laptop-onboard.sh` now sets it
   automatically. To set it by hand for any user:
   ```sh
   CJ=~/.claude.json
   [ -f "$CJ" ] && jq '.hasCompletedOnboarding=true' "$CJ" > "$CJ.t" && mv "$CJ.t" "$CJ" \
     || echo '{"hasCompletedOnboarding":true}' > "$CJ"
   ```
2. **Non-root user.** Claude Code refuses `--dangerously-skip-permissions` as root, so run it
   as a normal user (mirrors the `claude-runner` pattern). This is fully scripted —
   `setup/setup-claude-user.sh` creates the user and provisions the key, creds, and
   onboarding flag, then verifies:
   ```sh
   RUN_USER=claude bash /opt/credpipe/setup/setup-claude-user.sh
   su - claude -c 'claude --dangerously-skip-permissions'
   ```
   The script's own check runs `claude -p ping` as the user → `Pong!` (verified in a container).

## Alternatives to the serve channel (key delivery only)

- **scp**: `scp ~/.config/credpipe/key node:~/.config/credpipe/key` then `chmod 600`, then run
  `laptop-onboard.sh` (it detects the existing key and skips the fetch).
- **paste**: `cat ~/.config/credpipe/key` on main → paste into the node → `chmod 600`.

In every case the node MUST end with `sha256sum ~/.config/credpipe/key | cut -c1-16` equal to
main's fingerprint — that is the integrity check.
