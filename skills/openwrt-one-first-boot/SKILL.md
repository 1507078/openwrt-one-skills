---
name: openwrt-one-first-boot
description: Bring up a new OpenWrt One - confirm what the board actually is, work out whether official packages will install on it, and back up the flash before anything is written. Use when the user has just received an OpenWrt One, is about to flash or reconfigure one, or asks why a package will not install.
---

# OpenWrt One: first boot

Goal: after this skill, the user knows exactly what their board is, whether the
official package feed works for them, and has a backup of the one thing on the
board that cannot be downloaded again.

Everything here is read-only except the backup. Nothing is written to flash.

## Ground rule

**Ask the board, do not quote the datasheet.** The spec sheet says what the SoC
*can* do. The board says what is actually wired up and what the firmware
enabled. They differ, and the second one is what the user has.

Write down what you looked for and did **not** find. "No cpufreq nodes" and
"did not check cpufreq" look identical in notes six months later.

## 1. Reach the board

Out of the box the One is already a working router. Stock OpenWrt listens on
`192.168.1.1`; if the board has been reconfigured, ask for the address rather
than guessing.

```sh
ssh root@192.168.1.1 'ubus call system board; uname -a'
```

### 🚨 That worked without asking for a password

**A stock OpenWrt One has no root password**, so every other device on that
network can log in too. Fix it before the board goes anywhere near the rest of
the house, and **say so out loud** — people assume a new router is closed by
default, and this one is not.

```sh
ssh root@<ip> passwd        # the security fix
ssh-copy-id root@<ip>       # so the scripts here never need to prompt
```

The password closes ssh and LuCI. **It does not close the serial console** —
that is a separate switch, and leaving it open is what keeps the board
recoverable.

### The console is the way back

Front USB-C (the rear port is power), 115200, no driver. It works when the
network does not, which is why every risky step later assumes you have it.

⭐ **Prove it on day one, while nothing is broken.** Which port, why a
charge-only cable looks exactly like a dead console, the password trade above,
and what only the boot log can tell you:
[`references/console.md`](references/console.md).

## 2. Which tier are you on?

Run this first. It answers the single question that determines everything else.

```sh
scripts/identify-tier.sh root@192.168.1.1
```

The dividing line is the **kernel config hash**, not the kernel version. Two
devices both running 6.12.87 can be unable to share a single kmod. OpenWrt
publishes kmods under a directory named after that hash, so the comparison is
exact.

- **TIER=0** — stock firmware. `apk add <pkg>` works. Over a thousand kmods are
  available with no compiler. Stop here; do not let the user compile anything.
- **TIER=3** — self-built kernel. No official kmod will install. Everything must
  come from the same tree that built the firmware. If this was not deliberate,
  flashing the official image restores the whole feed.

Note that OpenWrt 25.x uses `apk`, not `opkg`. Older releases use `opkg`.

### 🚨 It must be a release, not a snapshot

**These skills assume a numbered release** (`25.12.4`, `24.10.x`, …). If
`identify-tier.sh` reports SNAPSHOT, stop and flash a release before going any
further.

A snapshot may carry a fix the user wants, and that is a legitimate reason to
run one in general. It is the wrong trade for a box about to become the
household's router: the kernel hash changes daily so packages stop installing
within days, there is no LuCI at all, and the exact firmware on the board cannot
be downloaded again.

Why, with the numbers: [`references/releases-vs-snapshots.md`](references/releases-vs-snapshots.md).

## 3. Health check

A short pass over the things that cause confusing symptoms later. Full commands:
[`references/health-check.md`](references/health-check.md).

| Check | Why it matters |
|---|---|
| `date` is correct | 🚨 The RTC often ships **without a working battery**. Until something sets the clock, every log you collect is stamped wrong and cannot be correlated with anything afterwards. Fix this before relying on any log. |
| Ports report the speed you expect | A gigabit port that negotiated 100 Mbps is a cable or a socket. It presents later as "the internet is slow" with no other symptom. |
| Temperature is in the 50s–60s °C idle | 🚨 **No frequency scaling on this CPU** — there is no gradual slowdown when hot. The only trip that acts is critical, and it powers the board off. No warning stage. |
| Regulatory domain is right for where you live | Decides which channels and power levels are legal. Yours to set; the skills will not change it. |

📌 **Write down what was *not* there too.** "PCIe slot empty", "no SD card" —
absent and not-checked look identical in notes six months later.

> Bringing up a board rather than setting up a router? The full inventory — CPU
> identification, flash layout, IO sweep, the traps in reading them — is in
> [`advanced/BOARD_BRINGUP.md`](../../advanced/BOARD_BRINGUP.md).

## 4. Back up the one thing that cannot be re-downloaded

Firmware can be downloaded again. Settings can be recreated. **The Wi-Fi
calibration data and MAC addresses exist on this board and nowhere else** — lose
them and the radios never work properly again.

On the OpenWrt One that is the `factory` partition on NOR:

```sh
cat /proc/mtd                                                   # confirm which mtdN is 'factory'
ssh root@<ip> "dd if=/dev/mtd1 bs=64k 2>/dev/null" > factory.bin
ssh root@<ip> "sha256sum /dev/mtd1"                             # and compare with:
shasum -a 256 factory.bin
```

Two details decide whether this worked:

- Read `/dev/mtdN`, the **character** device — not `/dev/mtdblockN`.
- **Checksum on the device as well.** Hashing only your local copy proves a file
  exists, not that it was read correctly.

Do this once, before anything is ever written to flash, and keep it somewhere
that is not the router.

> Backing up the whole device — bootloader, recovery, UBI volumes, and how to
> identify the irreplaceable partition on a board that is not this one:
> [`advanced/FLASH_BACKUP.md`](../../advanced/FLASH_BACKUP.md).

## 5. The web interface, and a config backup

**LuCI is already installed** on an official release image — `luci`, `luci-ssl`
and `uhttpd` are all in the release build config. Browse to `https://<ip>/` and
it is there. Do not install it.

Two cases where it is missing, and both are worth recognising because the fix
differs:

| The board is running | LuCI | What to do |
|---|---|---|
| An official **release** (`25.12.4`, etc.) | ✅ present | Nothing |
| An official **snapshot** | ❌ absent | `apk add luci` — snapshots are built without it |
| **Self-built** firmware (TIER 3 from step 2) | depends on whoever built it | `apk add luci` works only if the kernel hash matches the feed. If it does not, LuCI has to be built into the image. |

Then take a configuration backup, which is a different thing from the flash
backup in step 4:

```sh
ssh root@<ip> "sysupgrade -l"                          # what would actually be preserved
ssh root@<ip> "sysupgrade -b /tmp/backup-$(date +%F).tar.gz"
scp -O root@<ip>:/tmp/backup-*.tar.gz .
```

🚨 **Run `sysupgrade -l` and read it.** Anything not on that list is destroyed
by the next upgrade with no warning — scripts you added, init files, data you
have been collecting in `/root/`. Details and the restore procedure:
[`references/config-backup.md`](references/config-backup.md).

## 6. Record the recovery path

Before the user needs it, confirm and write down how this specific board is
rescued. On the One:

- Rear button + USB stick rewrites NAND unattended — the easiest path.
- `fw_printenv` shows the boot order: production, then recovery fallback.
- The boot menu differs depending on which medium booted. Do not assume the
  menu the user sees is the one in the wiki.

## Done when

- [ ] Tier is known and the user has been told what it means
- [ ] Clock is correct, ports negotiated the expected speed, temperature sane
- [ ] `factory` partition backed up, checksummed on both ends
- [ ] Config backup taken and copied off the board, with `sysupgrade -l` reviewed
- [ ] Recovery path written down somewhere that survives losing the network
