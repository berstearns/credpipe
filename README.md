# credpipe

Sync one OAuth credential file across all your machines through a dumb public relay.
Built for the headless-laptop problem: log into Claude **once**, in **one** browser, and every
tty box you own stays authenticated automatically.

One ~110-line bash script. No daemon framework, no HTTP, no SSH round-trips. Raw TCP, symmetric
encryption, single writer / many readers.

```
   main laptop                 relay (VPS)                 tty laptops ×N
  (has a browser)            [ creds.enc ]               (tmux, no browser)
        │                     ▲        │
        └── push :9001 ──────►│        └────── pull :9000 ──────►  install
            (encrypt)         │  dumb mailbox,                    (decrypt,
                              │  never holds the key)              verify, drop in)
```

- **Confidentiality** comes from `openssl` — the blob on the wire and at rest is ciphertext.
- **Integrity** comes from the readers — a laptop installs the file **only if it decrypts to valid
  JSON**, so a corrupt or poisoned blob is a silent no-op, not a breakage.
- **The relay never has the key.** It physically holds your tokens but cannot read them.

> ⚠️ This moves real account credentials. The security rests entirely on **the key file never
> touching the relay or the network.** Read [Security](#security) before deploying.

---

## Why

Three roles, one secret, two directions of flow:

| Role | Machine | Browser? | Does |
|------|---------|----------|------|
| **main** | your laptop with a screen | yes | logs in, owns real creds, **pushes** |
| **relay** | a cheap always-on VPS | — | holds the encrypted blob, hands it out |
| **laptop** | your tty/tmux boxes | no | **pulls**, decrypts, installs |

The relay exists only because main and the laptops are usually behind NAT and can't reach each
other directly. It's the public meeting point both sides *can* reach.

---

## Requirements

- `bash`, `openssl` — everywhere
- `socat` — everywhere (the TCP transport)
- `jq` — on the laptops (the integrity gate)

```sh
# debian/ubuntu
sudo apt install socat jq openssl
# arch
sudo pacman -S socat jq openssl
# macos
brew install socat jq openssl
```

---

## Install

```sh
git clone https://github.com/berstearns/credpipe ~/credpipe
cd ~/credpipe
cp .env.example .env
$EDITOR .env                 # set CREDPIPE_HOST=your.vps.ip — that's the only required line
ln -s "$PWD/credpipe" ~/bin/credpipe   # or: sudo ln -s "$PWD/credpipe" /usr/local/bin/credpipe
credpipe doctor              # sanity-check deps, key, relay
```

`.env` is git-ignored. The repo is public; **your deployment is not.**

---

## Setup (do this once, in order)

### 1. Make the key — on main only

```sh
credpipe keygen
```

Prints a path and a fingerprint. This file is your whole security model.

### 2. Copy the key to every machine — out-of-band

Same bytes everywhere, by a channel **you** trust. Never through the relay.

```sh
# if you can ssh to the box:
scp ~/.config/credpipe/key laptop1:~/.config/credpipe/key
ssh laptop1 'chmod 600 ~/.config/credpipe/key'

# tty-only (paste into the tmux pane): print it on main with `cat ~/.config/credpipe/key`,
# then on the laptop:
mkdir -p ~/.config/credpipe
echo 'PASTE_THE_LINE_HERE' > ~/.config/credpipe/key && chmod 600 ~/.config/credpipe/key
```

Verify they match — every machine must print the same hash:

```sh
sha256sum ~/.config/credpipe/key
```

### 3. Start the relay — on the VPS

```sh
credpipe serve         # foreground; see "Run it forever" to daemonize
```

Open the two ports in the firewall (`9000` pull, `9001` push by default).

### 4. First push — on main

Log into Claude normally so `~/.claude/.credentials.json` exists, then:

```sh
credpipe push
```

### 5. First pull — on a laptop

```sh
credpipe pull          # should print "pulled …"; now claude is authenticated here
```

---

## Run it on a timer

The point is to never think about it. Push from main, pull on laptops, on a clock.

**cron** (`crontab -e`):

```cron
# main — keep the relay fresh (incl. after silent token refresh)
*/2 * * * * /home/you/bin/credpipe push   >> ~/.cache/credpipe.log 2>&1

# laptop — stay current
*/2 * * * * /home/you/bin/credpipe pull   >> ~/.cache/credpipe.log 2>&1
```

**Pull-before-launch** (the reliability trick) — shadow `claude` on PATH so every session starts
from the freshest token. Set `CREDPIPE_REAL_CLAUDE` in `.env`, then:

```sh
printf '#!/usr/bin/env sh\nexec %s wrap "$@"\n' "$HOME/bin/credpipe" > ~/bin/claude
chmod +x ~/bin/claude         # ensure ~/bin precedes the real claude in PATH
```

Pull **more often than the access-token lifetime** so a laptop rarely refreshes on its own — see
[the rotation gotcha](#the-one-real-gotcha-token-rotation).

### Run the relay forever (systemd, on the VPS)

```ini
# /etc/systemd/system/credpipe.service
[Unit]
Description=credpipe relay
After=network.target
[Service]
ExecStart=/usr/local/bin/credpipe serve
Restart=always
[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl enable --now credpipe
```

---

## Commands

| Command | Where | Does |
|---------|-------|------|
| `credpipe keygen` | main, once | generate the shared key |
| `credpipe serve`  | relay | run the two TCP listeners |
| `credpipe push`   | main | encrypt local creds → relay |
| `credpipe pull`   | laptops | relay → decrypt → install (if valid JSON) |
| `credpipe wrap …` | laptops | `pull` then `exec` the real claude |
| `credpipe doctor` | anywhere | check deps, key fingerprint, relay reachability |

All config is environment variables, loaded from `.env`. Only `CREDPIPE_HOST` is required; see
`.env.example` for the rest.

---

## How the crypto works

Symmetric AES-256-CBC, key derived from your shared key file via PBKDF2 with a random per-blob salt.

- **push:** `openssl enc -aes-256-cbc -pbkdf2 -salt -pass file:KEY` → emits `[salt][ciphertext]`.
  The salt is public and rides at the front of the blob.
- **pull:** `openssl enc -d …` reads that salt, runs the *same* key through PBKDF2 to derive the
  *same* AES key, and reverses the scramble.

Round-trips because both sides hold the same key; safe because the relay holds neither the key nor
any way to derive it.

---

## The one real gotcha: token rotation

OAuth refresh tokens commonly **rotate on use** — when one machine refreshes, the previous refresh
token can be invalidated, breaking everyone else's copy. Mitigations, in order:

1. **Single writer.** Only `main` ever pushes. Laptops only pull.
2. **Pull-before-launch** + **frequent pull** so a laptop almost never refreshes on its own.
3. Accept that occasionally "whoever refreshed last wins" and the others re-pull on their next tick.

For a handful of personal machines this is fine. It is not a fleet auth system.

---

## Security

- The key file must **never** reach the relay or travel over any untrusted channel. Distribute it
  out-of-band (USB, scp, paste-into-tmux), once.
- The relay's push port accepts writes from anyone who can reach it. That's deliberately tolerated:
  a poisoned blob fails the reader's `jq` check and is ignored. If you want to lock it down anyway,
  put the relay behind a VPN/Tailscale/WireGuard or a firewall allowlist, or front it with mTLS.
- `*.enc`, `*.key`, `key`, and `.env` are git-ignored. Run `credpipe doctor` and `git status`
  before your first push to confirm nothing secret is staged.
- Rotate the key by re-running `keygen` and redistributing — do this if you think it leaked.

---

## License

MIT — see [LICENSE](LICENSE).
