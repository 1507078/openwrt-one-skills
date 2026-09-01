#!/bin/sh
# identify-tier.sh -- work out which "tier" an OpenWrt device is on.
#
# The dividing line between "official packages just work" and "you must build
# everything yourself" is the kernel CONFIG HASH, not the kernel version. Two
# devices can both run 6.12.87 and still be unable to share a single kmod.
#
# OpenWrt publishes kmods under a directory named after that hash:
#   .../targets/<target>/kmods/<kver>-<n>-<hash>/
# So we ask the device for its hash and compare it with the official one.
#
# Runs on your workstation, not on the router. Needs ssh and curl.
#
# Usage: identify-tier.sh [user@host]        (default: root@192.168.1.1)

set -eu

HOST="${1:-root@192.168.1.1}"
BASE="https://downloads.openwrt.org"

die() { echo "error: $*" >&2; exit 1; }

die_no_ssh() {
  cat >&2 <<EOF
error: cannot log in to $HOST over ssh.

A brand-new OpenWrt One has no key of yours installed, so the first thing to do
is put one there. Set a root password on the board first (LuCI, or 'passwd' on
the console), then from this machine:

    ssh-copy-id root@${HOST#*@}

After that everything here works without prompting. If the board is not
answering at all, check the address -- stock OpenWrt listens on 192.168.1.1.
EOF
  exit 1
}

command -v ssh   >/dev/null 2>&1 || die "ssh not found"
command -v curl  >/dev/null 2>&1 || die "curl not found"

# ---------------------------------------------------------------- device facts
# Emit plain KEY=VALUE so we never need a JSON parser on either side.
REMOTE='
. /etc/openwrt_release 2>/dev/null
echo "RELEASE=${DISTRIB_RELEASE:-}"
echo "TARGET=${DISTRIB_TARGET:-}"
echo "REVISION=${DISTRIB_REVISION:-}"
echo "BOARD=$(ubus call system board 2>/dev/null | sed -n "s/.*\"board_name\": *\"\([^\"]*\)\".*/\1/p")"
echo "KVER=$(uname -r)"
if command -v apk >/dev/null 2>&1; then
  echo "PKGMGR=apk"
  echo "KPKG=$(apk list -I 2>/dev/null | grep -m1 "^kernel-" | awk "{print \$1}")"
elif command -v opkg >/dev/null 2>&1; then
  echo "PKGMGR=opkg"
  echo "KPKG=$(opkg list-installed 2>/dev/null | grep -m1 "^kernel " | awk "{print \$3}")"
fi
'

# Try non-interactive first, so an agent is never left hanging on a password
# prompt it cannot answer. Fall back to an interactive attempt only when a human
# is actually at the terminal.
FACTS=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$HOST" "$REMOTE" 2>/dev/null) || {
  if [ -t 0 ]; then
    echo "No ssh key accepted by $HOST -- trying password authentication." >&2
    FACTS=$(ssh -o ConnectTimeout=20 "$HOST" "$REMOTE") || die_no_ssh
  else
    die_no_ssh
  fi
}

RELEASE=""; TARGET=""; REVISION=""; BOARD=""; KVER=""; KPKG=""; PKGMGR=""
eval "$FACTS"

[ -n "$RELEASE" ] || die "could not read /etc/openwrt_release -- is this OpenWrt?"
[ -n "$TARGET" ]  || die "could not determine target"

# A kernel config hash is 32 hex characters, in both the apk and opkg spellings.
LOCAL_HASH=$(printf '%s' "$KPKG" | grep -oE '[0-9a-f]{32}' | head -1 || true)

# -------------------------------------------------------------- official facts
if [ "$RELEASE" = "SNAPSHOT" ]; then
  KMODS_URL="$BASE/snapshots/targets/$TARGET/kmods/"
else
  KMODS_URL="$BASE/releases/$RELEASE/targets/$TARGET/kmods/"
fi

OFFICIAL_DIR=$(curl -sfL --max-time 20 "$KMODS_URL" 2>/dev/null \
  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-[0-9a-f]{32}' | head -1 || true)
OFFICIAL_HASH=$(printf '%s' "$OFFICIAL_DIR" | grep -oE '[0-9a-f]{32}' | head -1 || true)

# --------------------------------------------------------------------- report
echo "Device"
echo "  host       $HOST"
echo "  board      ${BOARD:-unknown}"
echo "  release    $RELEASE ($REVISION)"
echo "  target     $TARGET"
echo "  kernel     $KVER"
echo "  pkg mgr    ${PKGMGR:-unknown}"
echo "  kmod hash  ${LOCAL_HASH:-<none found>}"
echo
echo "Official ($RELEASE / $TARGET)"
echo "  kmod hash  ${OFFICIAL_HASH:-<not published>}"
echo

if [ "${BOARD:-}" != "openwrt,one" ]; then
  echo "!  This board is '${BOARD:-unknown}', not 'openwrt,one'."
  echo "!  These skills are only tested on the OpenWrt One. The recovery"
  echo "!  guarantees they rely on may not exist here. Proceed carefully."
  echo
fi

if [ -z "$LOCAL_HASH" ]; then
  echo "?  Could not read the kernel package from the device."
  echo "   Cannot tell whether official kmods will install. Treat as Tier 3."
  echo "TIER=unknown"
  exit 0
fi

if [ "$RELEASE" = "SNAPSHOT" ]; then
  cat <<EOF
!  This board is running a SNAPSHOT, and these skills assume a release.

   Snapshots are rebuilt from main every day. Three things follow, and none
   of them have a workaround:

     - The kernel hash changes roughly daily, so any kmod you install stops
       being installable within days, and the package feed drifts away from
       your machine.
     - There is no LuCI. Snapshot images are built without a web interface.
     - The exact firmware on this board cannot be downloaded again. Snapshot
       filenames carry no version and old builds are deleted -- so back up
       the kernel and rootfs, not just the calibration data.

   A snapshot may well carry a fix you want. For a box that is going to be
   the household router, that is not worth an environment that moves under
   you. Flash a numbered release.

   See references/releases-vs-snapshots.md.
EOF
  echo "TIER=3"
  exit 0
fi

if [ -z "$OFFICIAL_HASH" ]; then
  echo "?  No official kmod feed published for $RELEASE / $TARGET."
  echo "   Cannot tell whether official kmods will install. Treat as Tier 3."
  echo "TIER=3"
  exit 0
fi

if [ "$LOCAL_HASH" = "$OFFICIAL_HASH" ]; then
  cat <<EOF
=> TIER 0 -- you are on stock firmware.

   The official package feed matches your kernel. You almost certainly do
   not need to compile anything:

       ssh $HOST 'apk add <package>'

   All $(curl -sfL --max-time 20 "$KMODS_URL$OFFICIAL_DIR/" 2>/dev/null \
       | grep -coE '[a-z0-9._+-]+\.apk' || echo "official") kmods for this
   kernel install as-is. Reach for ImageBuilder (Tier 1) only if you need
   packages baked into the image itself.
EOF
  echo "TIER=0"
else
  cat <<EOF
=> TIER 3 -- you are running a self-built kernel.

   Your hash   $LOCAL_HASH
   Official    $OFFICIAL_HASH

   Same kernel version, different config hash. **No official kmod will
   install on this device.** Anything you need must be built from the same
   tree that produced this firmware.

   If that was not intentional, flashing the official
   $RELEASE image for $TARGET puts you back on Tier 0 and the whole
   package feed becomes available again.
EOF
  echo "TIER=3"
fi
