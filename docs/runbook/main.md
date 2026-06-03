# pane: `main` (window 1) — the WRITER

Role: keep the relay's encrypted blob fresh by pushing this laptop's Claude creds on a loop.
Session `credpipe-demo`, pane title `cp-main`, cwd `<repo>` (this credpipe clone).

> Real per-deployment values are masked as `<…>`. The unmasked copy lives in the
> git-ignored `runbook/`.

## Command run

```sh
while true; do sleep 12; ./credpipe push; done
```

Output each cycle: `pushed <YYYY-MM-DD HH:MM:SS>`. Leave running; Ctrl-C to stop.

## Gotcha hit

- First attempt used `while 1; do …; done` → `__zoxide_cd:cd:2: no such entry in dir stack`.
  In zsh, `1` isn't a command; with `auto_cd` on, the bare `1` is treated as a directory and
  zoxide's `cd` wrapper errors. Fix: `while true` (or `:`), not `while 1`.

## Equivalent repo script

```sh
INTERVAL=12 bash setup/push-watch.sh
```

## Notes

- Pushing on a loop also heals the mailbox if a scan zeroes the open push port (`:9001`).
- Permanent equivalent: `*/2 * * * * ~/.local/bin/credpipe push`.
