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
apt-get update && apt-get install -y curl ca-certificates    # just enough to fetch the script
curl -fsSL https://raw.githubusercontent.com/berstearns/credpipe/master/setup/laptop-onboard.sh -o /tmp/onboard.sh

CREDPIPE_HOST='<relay-ip>' \
KEY_URL='https://<relay-ip>:47823/r.conf' \
SERVE_PASSCODE='<passcode-from-serve-key.sh>' \
CREDPIPE_KEY_PASSPHRASE='pick-a-strong-passphrase' \
EXPECTED_FP='<fp-from-credpipe-doctor>' \
bash /tmp/onboard.sh
```

`laptop-onboard.sh` then:
1. installs deps (`openssl socat jq curl git ca-certificates`),
2. clones the public repo to `/opt/credpipe`,
3. writes `.env` (`CREDPIPE_HOST=…`),
4. fetches `key.enc`, decrypts it with the passphrase, installs `~/.config/credpipe/key`
   (mode 600), and **verifies the fingerprint matches main**,
5. symlinks `credpipe` onto PATH,
6. `credpipe doctor` + `credpipe pull` → installs `~/.claude/.credentials.json` and
   confirms it's valid JSON.

Add `INSTALL_CLAUDE=1` to also install the `claude` CLI and a pull-before-launch wrapper.

### Fully self-contained one-liner (clone + run from the repo)

```sh
apt-get update && apt-get install -y git curl ca-certificates
git clone --depth 1 https://github.com/berstearns/credpipe /opt/credpipe
CREDPIPE_HOST='<relay-ip>' KEY_URL='https://<relay-ip>:47823/r.conf' \
SERVE_PASSCODE='<passcode>' CREDPIPE_KEY_PASSPHRASE='<passphrase>' \
EXPECTED_FP='<fp>' bash /opt/credpipe/setup/laptop-onboard.sh
```

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
2. **Non-root user.** Claude Code refuses `--dangerously-skip-permissions` as root. Run it
   as a normal user (mirrors the `claude-runner` pattern):
   ```sh
   useradd -m -s /bin/bash claude
   install -d -o claude -g claude -m700 /home/claude/.config/credpipe /home/claude/.claude
   install -o claude -g claude -m600 ~/.config/credpipe/key        /home/claude/.config/credpipe/key
   install -o claude -g claude -m600 ~/.claude/.credentials.json   /home/claude/.claude/.credentials.json
   jq '.hasCompletedOnboarding=true' ~/.claude.json > /home/claude/.claude.json
   chown claude:claude /home/claude/.claude.json && chmod 600 /home/claude/.claude.json
   # then:
   su - claude -c 'claude --dangerously-skip-permissions'
   ```
   Verified: `su - claude -c 'claude --dangerously-skip-permissions -p ping'` → `Pong!` (RC 0).

## Alternatives to the serve channel (key delivery only)

- **scp**: `scp ~/.config/credpipe/key node:~/.config/credpipe/key` then `chmod 600`, then run
  `laptop-onboard.sh` (it detects the existing key and skips the fetch).
- **paste**: `cat ~/.config/credpipe/key` on main → paste into the node → `chmod 600`.

In every case the node MUST end with `sha256sum ~/.config/credpipe/key | cut -c1-16` equal to
main's fingerprint — that is the integrity check.
