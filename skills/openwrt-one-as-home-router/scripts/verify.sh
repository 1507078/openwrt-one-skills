#!/bin/sh
# verify.sh -- check that the router is in the state you think it is.
#
# Every check here looks at BEHAVIOUR or at running state. None of them read a
# config file and call it done, because that is precisely the failure this
# exists to catch: `uci commit` succeeds, `uci get` reads the value back
# correctly, and the daemon was never restarted, so nothing actually changed.
#
# Read-only. Safe to run at any time. Run it after every change.
#
# Usage: verify.sh [user@host]        (default: root@192.168.1.1)
# Exit:  0 all checks passed, 1 at least one FAIL, 2 could not connect.

set -eu
HOST="${1:-root@192.168.1.1}"

die_no_ssh() {
  cat >&2 <<EOF
error: cannot log in to $HOST over ssh.

Install a key on the board first -- set a root password on it, then:

    ssh-copy-id root@${HOST#*@}

Stock OpenWrt listens on 192.168.1.1.
EOF
  exit 2
}

# Staged in a file rather than piped straight in, so the interactive retry
# below still has something to send.
REMOTE_SCRIPT=$(mktemp)
trap 'rm -f "$REMOTE_SCRIPT"' EXIT INT TERM
cat > "$REMOTE_SCRIPT" <<'REMOTE'
FAIL=0
pass() { echo "PASS  $*"; }
warn() { echo "WARN  $*"; }
fail() { echo "FAIL  $*"; FAIL=1; }

# --------------------------------------------------- 1. uncommitted changes
CHANGES=$(uci changes 2>/dev/null || true)
if [ -n "$CHANGES" ]; then
  fail "uncommitted uci changes are pending -- they are not live:"
  echo "$CHANGES" | sed 's/^/        /'
else
  pass "no uncommitted uci changes"
fi

# ------------------------------- 2. committed, but the daemon never restarted
# /proc/<pid> carries the process start time. If a config file is newer than
# the process that reads it, the change was saved and never applied.
check_stale() {  # <config file> <process name> <service name>
  cfg="/etc/config/$1"; proc="$2"; svc="$3"
  [ -f "$cfg" ] || return 0
  pid=$(pgrep "$proc" 2>/dev/null | head -1)
  if [ -z "$pid" ]; then
    fail "$svc is not running at all (config $1 exists)"
    return 0
  fi
  if [ -n "$(find "$cfg" -newer "/proc/$pid" 2>/dev/null)" ]; then
    fail "$1 was changed after $svc started -- committed but NOT in effect"
    echo "        fix: /etc/init.d/$svc restart   (then re-run this check)"
  else
    pass "$svc is running with the current $1"
  fi
}
check_stale dhcp     dnsmasq  dnsmasq
check_stale wireless hostapd  network
check_stale network  netifd   network

# ------------------------------------------------ 3. dnsmasq health
if logread -e dnsmasq 2>/dev/null | tail -40 | grep -qi "crash loop\|FAILED to start"; then
  fail "dnsmasq is failing to start -- DHCP *and* DNS are down network-wide"
  logread -e dnsmasq | tail -3 | sed 's/^/        /'
else
  pass "dnsmasq shows no startup failures in recent log"
fi

# ------------------------------------------------ 4. DNS actually resolves
if nslookup openwrt.org >/dev/null 2>&1; then
  pass "DNS resolves from the router"
else
  fail "DNS does not resolve from the router"
fi

# ------------------------------------------------ 5. WAN
GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
if [ -z "$GW" ]; then
  fail "no default route -- the router itself has no way out"
else
  pass "default route via $GW"
  ping -c1 -W2 "$GW" >/dev/null 2>&1 \
    && pass "upstream gateway $GW responds" \
    || warn "upstream gateway $GW does not answer ping (may be filtered)"
  ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 \
    && pass "the internet is reachable" \
    || fail "cannot reach 1.1.1.1 -- routing or upstream is broken"
fi

# ------------------------------------- 6. static leases that cannot be honoured
# A reservation only works if its address belongs to the subnet the request
# arrives on. dnsmasq does not warn about this; it silently serves from the pool.
BAD=0
for sec in $(uci show dhcp 2>/dev/null | sed -n "s/^dhcp\.\(@host\[[0-9]*\]\)\.ip=.*/\1/p"); do
  ip=$(uci -q get "dhcp.$sec.ip") || continue
  name=$(uci -q get "dhcp.$sec.name" || echo "$sec")
  [ -n "$ip" ] || continue
  case "$name" in *" "*)
    fail "static lease name '$name' contains a space -- dnsmasq will reject the whole config"
    ;;
  esac
  if ip route get "$ip" 2>/dev/null | grep -q " via "; then
    fail "reservation $name -> $ip is not on any local subnet; it will never be handed out"
    BAD=1
  fi
done
[ "$BAD" -eq 0 ] && pass "every static reservation is on a locally attached subnet"

# ------------------------------------------------ 7. wireless is actually up
WIFI_DOWN=""
for sec in $(uci show wireless 2>/dev/null | sed -n "s/^wireless\.\(@wifi-iface\[[0-9]*\]\)=.*/\1/p"); do
  [ "$(uci -q get "wireless.$sec.disabled" || echo 0)" = "1" ] && continue
  ssid=$(uci -q get "wireless.$sec.ssid" || echo "$sec")
  iwinfo 2>/dev/null | grep -q "ESSID: \"$ssid\"" || WIFI_DOWN="$WIFI_DOWN $ssid"
done
if [ -n "$WIFI_DOWN" ]; then
  fail "configured but not on air:$WIFI_DOWN"
else
  pass "every enabled SSID is on air"
fi

# ------------------------------- 8. files the next upgrade would silently eat
# OpenWrt runs an overlay filesystem: anything also present under /rom came
# from the firmware image and will be reprovided by the next one. Only files
# that exist solely in the overlay were added by a human, and only those can
# be lost.
KEPT=$(sysupgrade -l 2>/dev/null || true)
LOST=""; N=0
for f in /root/* /usr/sbin/* /etc/init.d/*; do
  [ -f "$f" ] || continue
  [ -e "/rom$f" ] && continue                      # shipped in the image
  echo "$KEPT" | grep -qx "$f" && continue         # already preserved
  N=$((N + 1))
  [ "$N" -le 12 ] && LOST="$LOST $f"
done
if [ "$N" -gt 0 ]; then
  warn "$N file(s) you added would be destroyed by the next upgrade."
  echo "        Add anything worth keeping to /etc/sysupgrade.conf, then re-run"
  echo "        'sysupgrade -l' to confirm it appears -- editing is not the check."
  for f in $LOST; do echo "          $f"; done
  [ "$N" -gt 12 ] && echo "          ... and $((N - 12)) more"
else
  pass "everything you added is covered by sysupgrade.conf"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "VERIFY=pass"
else
  echo "VERIFY=fail  -- do not treat the change as done"
  exit 1
fi
REMOTE

# Non-interactive first, so an agent is never left hanging on a password prompt
# it cannot answer. Retry interactively only when a human is at the terminal.
rc=0
ssh -o ConnectTimeout=10 -o BatchMode=yes "$HOST" 'sh -s' < "$REMOTE_SCRIPT" || rc=$?
if [ "$rc" -eq 255 ]; then
  if [ -t 0 ]; then
    echo "No ssh key accepted by $HOST -- trying password authentication." >&2
    rc=0
    ssh -o ConnectTimeout=20 "$HOST" 'sh -s' < "$REMOTE_SCRIPT" || rc=$?
    [ "$rc" -eq 255 ] && die_no_ssh
  else
    die_no_ssh
  fi
fi
exit "$rc"
