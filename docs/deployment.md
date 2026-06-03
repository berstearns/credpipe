# credpipe — deployment (this fleet)

How a credpipe deployment is wired with the scripts in `setup/`. The public repo's
`README.md` explains the tool; this file is the deployment guide.

> Real values — relay IP, firewall id, key fingerprint — live only in the git-ignored
> `.env` (and on disk). Nothing deployment-specific or secret is committed here.

## Topology

```
   main (your laptop)            relay (DO droplet)              tty laptops ×N
   credpipe-main             $CREDPIPE_HOST                    (no browser)
        │                    credpipe.service                       │
        └── push :9001 ─────►  /srv/credpipe/creds.enc  ◄── pull :9000 ──┘
            encrypt                (ciphertext only)            decrypt+verify+install
```

| Role | Host | Identity |
|------|------|----------|
| main / writer | your laptop | `credpipe` on PATH (`~/.local/bin`); key fp from `credpipe doctor` |
| relay | `$CREDPIPE_HOST` (in `.env`) | systemd `credpipe.service`, ports 9000 (pull) / 9001 (push) |
| DO cloud firewall | `$CREDPIPE_DO_FW_ID` (in `.env`) | fronts the relay; opened additively |

The relay can be **co-located on an existing droplet**. credpipe uses its own ports and the
same cloud firewall; SSH (22) stays IP-allowlisted, credpipe ports are opened to `0.0.0.0/0`
additively (see Security).

## Setup scripts (`setup/`)

All command logic lives in committed scripts; nothing is run ad-hoc. Each is idempotent.

| Script | Runs on | Does |
|--------|---------|------|
| `lib.sh` | — | shared config (host, ports, firewall id, `dssh`/`dscp` transport helpers) |
| `00-preflight.sh` | main | discover relay: SSH reach, deps, host fw, DO cloud fw |
| `01-main.sh` | main | write `.env`, `keygen`, symlink onto PATH, `doctor` |
| `02-vps-deploy.sh` | main | scp binary + unit + bootstrap to relay, run bootstrap once |
| `credpipe-relay-bootstrap.sh` | relay | install deps, place binary, enable+restart systemd, verify listeners |
| `credpipe.service` | relay | the systemd unit |
| `03-open-ports.sh` | main | additively open 9000/9001 on the DO firewall (`0.0.0.0/0`+`::/0`) |
| `04-verify.sh` | main | doctor → push → confirm blob on relay → round-trip decrypt to valid JSON |
| `relay-logs.sh` | main | read-only relay diagnostics (status/journal/listeners) |
| `serve-key.sh` | main | temporarily serve the (passphrase-wrapped) key via `do-automation/serve` |
| `serve-key-selftest.sh` | main | prove the serve channel round-trips the key intact |
| `serve-key-down.sh` / `serve-key-purge.sh` | main | tear down the serve + robustly purge the relay (see `key-distribution.md`) |

Transport to the relay is password-auth via do-automation's `do-ssh-pass`/`do-scp-pass`
(`~/.do-pass`) — the droplet does not accept key auth.

## Reproduce from scratch

```sh
cd ~/p/credpipe-main
bash setup/00-preflight.sh     # sanity-check the relay is reachable
bash setup/01-main.sh          # configure this laptop (idempotent)
bash setup/02-vps-deploy.sh    # deploy + (re)start the relay
bash setup/03-open-ports.sh    # open the firewall
bash setup/04-verify.sh        # prove the full round-trip
```

## Operations

```sh
credpipe push                  # main: encrypt creds → relay (run on a timer)
credpipe doctor                # anywhere: deps / key fp / relay reachability
bash setup/relay-logs.sh       # relay status + journal + listeners (read-only)
```

Relay control (via `do-ssh-pass`, read-only unless noted):

```sh
do-ssh-pass 'systemctl status credpipe'        # state
do-ssh-pass 'journalctl -u credpipe -n 50'     # logs
do-ssh-pass 'systemctl restart credpipe'       # (mutating) restart
```

### Keep main fresh (optional cron)

```cron
*/2 * * * * ~/.local/bin/credpipe push >> ~/.cache/credpipe.log 2>&1
```

## The HOME-under-systemd fix (why the binary differs from upstream)

`credpipe serve` originally crash-looped on the relay: `line 19: HOME: unbound variable`.
systemd gives services no `$HOME`, and the script runs `set -u`, so the config block died
before opening a socket. Fixed locally with a `${HOME:-/root}` fallback on the key/creds
default paths (those paths are never used by `serve`, but `set -u` still forbids referencing
an unset var). This repairs the README's own systemd recipe; worth upstreaming.

## Onboarding a tty laptop

1. Get the key onto it **out-of-band** (see `key-distribution.md`) and verify
   `sha256sum ~/.config/credpipe/key | cut -c1-16` matches the fp from `credpipe doctor` on main.
2. Create `.env` with `CREDPIPE_HOST=<your relay IP>`, put `credpipe` on PATH.
3. `credpipe pull` → authenticated. Add a `*/2 * * * * credpipe pull` cron, and
   optionally the `wrap` shim so each `claude` launch pulls first.

## Security

- Ports 9000/9001 open to the world is credpipe's documented model: pull serves only
  ciphertext; push is neutralized by the reader's `jq` integrity gate; confidentiality
  rests entirely on the key, which never leaves main and never reaches the relay.
- Lock-down alternative (README): VPN/Tailscale or a firewall allowlist — impractical here
  because tty laptops sit behind NAT with rotating IPs.
- Rotate the key by re-running `credpipe keygen` + redistributing if you suspect a leak.
