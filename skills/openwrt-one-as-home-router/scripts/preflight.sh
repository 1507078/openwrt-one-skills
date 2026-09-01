#!/bin/sh
# preflight.sh -- confirm the user is NOT depending on the router we are about
# to change.
#
# The agent guiding this change reaches its API over the user's internet
# connection. If that connection runs through the router being reconfigured,
# a mistake takes the agent offline along with everything else -- and there is
# then nobody left to talk the user through the recovery.
#
# Run this before any change to WAN, LAN addressing, or firmware.
# Do not take the user's word for it. Check.
#
# Usage: preflight.sh [router-ip]        (default: 192.168.1.1)

set -eu

ROUTER="${1:-192.168.1.1}"
FAIL=0

say()  { echo "  $*"; }
bad()  { echo "  FAIL  $*"; FAIL=1; }
ok()   { echo "  ok    $*"; }

echo "Preflight: is this machine independent of $ROUTER?"
echo

# ------------------------------------------------------- 1. default route
GW=""
IFACE=""
if command -v ip >/dev/null 2>&1; then
  GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
  IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
elif command -v route >/dev/null 2>&1; then
  GW=$(route -n get default 2>/dev/null | awk '/gateway:/ {print $2; exit}')
  IFACE=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2; exit}')
fi

if [ -z "$GW" ]; then
  bad "no default route found -- this machine has no internet at all"
else
  say "default route via $GW${IFACE:+ on $IFACE}"
  if [ "$GW" = "$ROUTER" ]; then
    bad "your gateway IS the router being changed"
  else
    ok "gateway is not the target router"
  fi
fi

# --------------------------------------- 2. does traffic still cross the router
# A different gateway is not sufficient: the router may still be upstream.
if command -v traceroute >/dev/null 2>&1; then
  HOPS=$(traceroute -n -m 4 -w 1 -q 1 1.1.1.1 2>/dev/null | awk '{print $2}' || true)
  if printf '%s\n' "$HOPS" | grep -qx "$ROUTER"; then
    bad "$ROUTER still appears in the path to the internet"
  else
    ok "$ROUTER is not in the first hops to the internet"
  fi
else
  say "traceroute unavailable -- could not confirm the router is out of the path"
fi

# ------------------------------------------------------- 3. internet reachable
if command -v curl >/dev/null 2>&1; then
  if curl -sf --max-time 8 -o /dev/null https://downloads.openwrt.org/ 2>/dev/null; then
    ok "internet reachable"
  else
    bad "cannot reach the internet -- the agent will lose its API too"
  fi
fi

# --------------------------------------------- 4. router still reachable at all
if ping -c1 -W2 "$ROUTER" >/dev/null 2>&1 || ping -c1 -t2 "$ROUTER" >/dev/null 2>&1; then
  ok "router still reachable at $ROUTER"
else
  say "router not answering ping at $ROUTER (may be firewalled, or not yet wired)"
fi

echo
if [ "$FAIL" -eq 0 ]; then
  echo "PREFLIGHT=pass"
  echo "Safe to proceed. Write the offline runbook before the first risky step."
  exit 0
fi

cat <<'EOF'
PREFLIGHT=fail

Do not proceed. Tether this machine to a phone hotspot, disconnect from the
router's network, and run this again.

If the change goes wrong while you are still on this connection, you lose the
network, the agent, and the ability to ask anyone what to do -- all at once.
EOF
exit 1
