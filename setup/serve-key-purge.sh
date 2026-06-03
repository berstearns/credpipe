#!/usr/bin/env bash
# Finish what do-serve-down couldn't: it runs `pkill -f "caddy run"`, which matches
# its OWN remote shell (the cmdline contains "caddy run") and self-kills before the
# rm -rf — so caddy may linger and /root/serve is left intact.
#
# This purges ONLY the artifacts our key-serve created (i.sh, r.conf=the encrypted
# key, serve.env, setup-serve.sh, Caddyfile, fail2ban jail). It does NOT remove
# unrelated files in /root/serve (e.g. smoke_train.dist.tar.zst — not ours).
# caddy is stopped via `pkill -x caddy` (exact process-name match — no self-kill).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'on_err $LINENO' ERR

say "Purge caddy + our serve artifacts on the relay"
dssh '
  pkill -x caddy 2>/dev/null || true
  rm -f /run/caddy.pid
  rm -f /root/serve/i.sh /root/serve/r.conf /root/serve/serve.env /root/setup-serve.sh
  rm -f /etc/caddy/Caddyfile /etc/fail2ban/jail.d/caddy-bootstrap.local /etc/fail2ban/filter.d/caddy-bootstrap.conf
  fail2ban-client reload 2>/dev/null || true
  echo PURGE_REMOTE_OK
'

say "Verify"
dssh '
  pgrep -x caddy >/dev/null && echo "caddy: STILL RUNNING" || echo "caddy: stopped"
  ss -ltn | grep -q ":47823" && echo "port 47823: STILL OPEN" || echo "port 47823: closed"
  if ls /root/serve/i.sh /root/serve/r.conf /root/serve/serve.env >/dev/null 2>&1; then
    echo "our serve files: STILL PRESENT"
  else
    echo "our serve files: gone"
  fi
  echo "--- /root/serve remaining (not ours) ---"; ls -la /root/serve 2>/dev/null || echo "(dir gone)"
'

say "Bootstrap firewall present?"
doctl compute firewall list --format Name --no-header 2>/dev/null | grep -q 'fw-serve-bootstrap' \
  && echo "bootstrap firewall: STILL PRESENT" || echo "bootstrap firewall: gone"

echo "SERVE_KEY_PURGE_DONE"
