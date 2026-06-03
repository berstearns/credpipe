# credpipe — key distribution strategy

The shared key (`~/.config/credpipe/key`, fingerprint shown by `credpipe doctor`) is the
**whole** security model. Every machine that pulls needs the *same bytes*; the relay must
**never** get them.
This doc describes how to move the key to a new tty laptop using the `do-automation/serve`
HTTPS channel — **temporarily**, then torn down.

## The cardinal rule, and how this strategy respects it

> The key must never travel in cleartext over an untrusted channel, and must never reach
> the relay droplet.

The `serve` channel uploads files to `/root/serve/` **on the relay droplet** and serves them
over HTTPS. If we served the *raw* key, the relay would hold plaintext and could decrypt every
blob — game over. So we **never serve the raw key**. We serve a **passphrase-encrypted wrapper**:

```
key  --openssl enc (passphrase)-->  key.enc  --serve-->  laptop  --openssl -d (passphrase)-->  key
                                    (ciphertext on droplet + on the wire)
```

- The **passphrase** is chosen by you and travels **out-of-band** (your head, a tty paste) —
  it never touches the droplet or the network.
- A laptop therefore needs **three** independent things to obtain the key: the URL, the Caddy
  **basicauth passcode**, and the **decryption passphrase**. The droplet only ever sees
  ciphertext + a passcode *hash*.

## Channel hardening (provided by `do-automation/serve`)

`do-serve-up` gives, for free:

- **HTTPS** (Caddy, self-signed → clients use `curl -k`).
- **basicauth** with a fresh random 16-char passcode; only its hash is stored on the droplet.
- **Dual IP gate**: a *dedicated* bootstrap DO firewall **and** Caddy `@allowed remote_ip`,
  both locked to specific `/32`s — separate from the relay's own firewall.
- **fail2ban**: one wrong passcode → 24h ban.

This is a *separate* port (47823) and a *separate* firewall from the relay's 9000/9001 —
serving the key does not touch `credpipe.service`.

## Procedure

### On main — bring it up (temporary)

```sh
cd ~/p/credpipe-main
CREDPIPE_KEY_PASSPHRASE='choose-a-strong-one' bash setup/serve-key.sh
# (omit the env var to be prompted interactively)
```

`serve-key.sh`:
1. wraps `~/.config/credpipe/key` → `key.enc` with your passphrase (openssl AES-256, PBKDF2),
2. calls `do-serve-up` (firewall locked to **main's** current public IP),
3. prints the laptop fetch snippet + the teardown command,
4. shreds the local `key.enc` (the only remaining copy is the ciphertext on the droplet).

> `do-serve-up` locks the firewall to the IP that ran it. To let a *different* laptop fetch,
> add its public IP first:
> ```sh
> ~/p/all-my-tiny-projects/do-automation/serve/do-serve-allow-ip <laptop-public-ip>
> ```

### On the tty laptop — fetch, decrypt, verify

The served path is `/r.conf` (that's the `do-serve-up` slot `key.enc` occupies):

```sh
export U=bootstrap P='<passcode-from-serve-key.sh>'
mkdir -p ~/.config/credpipe
curl -fsSL -u "$U:$P" -k https://<RELAY_IP>:47823/r.conf -o /tmp/key.enc
openssl enc -d -aes-256-cbc -pbkdf2 -pass stdin -in /tmp/key.enc -out ~/.config/credpipe/key
# ^ type the SAME passphrase you chose on main
chmod 600 ~/.config/credpipe/key
shred -u /tmp/key.enc
sha256sum ~/.config/credpipe/key | cut -c1-16     # MUST match the fp from `credpipe doctor` on main
```

A matching fingerprint proves the key is intact; a mismatch means wrong passphrase or a
corrupt fetch — do **not** use it.

### On main — tear it down (do this the moment the laptop has the key)

```sh
bash setup/serve-key-down.sh
```

This deletes the bootstrap firewall, stops Caddy, and removes the served ciphertext +
configs. It verifies the result (caddy stopped, port 47823 closed, our files gone).

> **Gotcha baked into the teardown:** the underlying `do-serve-down` runs
> `pkill -f "caddy run"`, which matches its *own* remote shell (the cmdline contains that
> string) and self-kills before its `rm -rf`. So on its own it deletes the firewall but
> often leaves Caddy running and `/root/serve` intact. `serve-key-down.sh` therefore always
> follows it with `serve-key-purge.sh`, which stops Caddy via `pkill -x caddy` (exact
> process-name match — no self-kill) and removes **only our** artifacts (it leaves unrelated
> files like `smoke_train.dist.tar.zst` in `/root/serve` alone). Run `serve-key-purge.sh`
> directly if you ever need to clean up after a bare `do-serve-down`.

## Alternatives (when `serve` is overkill)

- **scp** (if the laptop is reachable): `scp ~/.config/credpipe/key laptop:~/.config/credpipe/key`
- **tty paste**: `cat ~/.config/credpipe/key` on main, paste into the laptop, `chmod 600`.
- **USB**: copy the file, verify the fingerprint on arrival.

The `serve` route exists for the headless-but-not-directly-reachable laptop — the same gap
the relay itself solves, applied to the one bootstrap secret the relay can't carry.
