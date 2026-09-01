# Flash backup: the full procedure

> Engineering depth, kept out of the main skills on purpose. Locating the
> calibration partition from three independent clues, reading UBI volumes, and
> deciding between `dd` and `nanddump` are bring-up concerns.
>
> The short version the skills actually use is in
> [`../skills/openwrt-one-first-boot/SKILL.md`](../skills/openwrt-one-first-boot/SKILL.md).

Do this **before anything is ever written to flash.**

Firmware is downloadable. Configuration can be recreated. There is exactly one
thing on the board that exists nowhere else, and if you lose it the board is
permanently degraded: the **factory calibration data and MAC addresses**.

Everything below exists to get that one thing safely off the board, and to
prove afterwards that what you saved is actually readable.

---

## 1. Save the raw output as files

```sh
D=<backup-dir>/raw ; mkdir -p $D
ssh root@<ip> 'cat /proc/mtd'                                   > $D/proc-mtd.txt
ssh root@<ip> 'ubinfo -a'                                       > $D/ubinfo-a.txt   # NAND: mandatory, see §2
ssh root@<ip> 'cat /proc/partitions; mount; df -h'              > $D/mount-df-partitions.txt
ssh root@<ip> 'dmesg'                                           > $D/dmesg.txt
ssh root@<ip> 'ubus call system board; cat /etc/openwrt_release'> $D/board-release.txt
ssh root@<ip> 'for d in /sys/class/mtd/mtd[0-9]*; do [ -e "$d/name" ] || continue;
  printf "%-6s %-12s size=%-12s erase=%-8s type=%s\n" "$(basename $d)" "$(cat $d/name)" \
         "$(cat $d/size)" "$(cat $d/erasesize)" "$(cat $d/type)"; done' > $D/mtd-sysfs.txt
```

`/proc/mtd` carries **neither the type (nor/nand) nor which SPI controller the
device hangs off**, so the sysfs loop is not redundant.

**Note the release string.** If it says `SNAPSHOT`, that matters in §5: snapshot
builds rotate daily on the download servers and old ones are deleted, so the
firmware currently on the board may be unobtainable later.

## 2. 🚨 On NAND, `/proc/mtd` is not the partition table

This is the step most often skipped. A NAND chip frequently appears as a single
mtd partition called `ubi`, and **the real layout lives inside UBI volumes**:

```
mtd5: 0ff00000 "ubi"        <- all /proc/mtd tells you
  |_ ubinfo -a
       vol 0 ubootenv     1.0 MiB  dynamic   <- the u-boot environment is really here
       vol 1 ubootenv2    1.0 MiB  dynamic
       vol 2 fip          938 KiB  static    <- BL31 + U-Boot
       vol 3 recovery     8.4 MiB  dynamic
       vol 4 fit         10.2 MiB  dynamic   <- kernel + DTB + squashfs rootfs
       vol 5 rootfs_data 219.7 MiB dynamic   <- ubifs, the overlay upper layer
```

Dumping `/dev/mtd5` whole is acceptable, but restoring it means rewriting the
entire chip. Dumping per volume (`/dev/ubi0_N`) lets you replace one piece. Do
at least one of the two — and **always save the `ubinfo -a` output**, because
without it that 255 MB blob is an undocumented lump.

`ubinfo -a` also reports **bad block count**, which decides §4.

## 3. Find the part that cannot be recreated

Cross-check three clues. Do not rely on one.

| Clue | How |
|---|---|
| **Name** | Partitions called `factory`, `art`, `caldata`, `bdata`, `radiocfg` are prime suspects |
| **Devicetree** | `find /sys/firmware/devicetree/base -path '*nvmem-layout*'` → an `eeprom@0` or `macaddr@N` node confirms it. **The offsets are fixed in the DTS and the driver reads them by address.** |
| **Content** | `dd if=/dev/mtdN bs=1 count=256 \| hexdump -C` → a chip magic and MAC-shaped bytes settle it |

On the OpenWrt One all three point at the same place: **`factory` on NOR
(mtd1)**, whose first bytes carry the `0x7981` MT7981 EEPROM magic with the
Wi-Fi MAC addresses immediately after.

> ⚠️ **It is not necessarily on the chip you assume.** The One has both NOR and
> NAND, and the calibration lives on **NOR** — which conveniently means
> replacing the NAND does not destroy it. Confirm before you start rather than
> guessing.

## 4. Dump, and three details that decide whether it worked

```sh
ssh root@<ip> "dd if=/dev/mtdN bs=64k 2>/dev/null" > mtdN-<name>.bin      # straight home, no space used on the board
r=$(ssh root@<ip> "sha256sum /dev/mtdN" | awk '{print $1}')               # also hash it on the device
l=$(shasum -a 256 mtdN-<name>.bin | awk '{print $1}')
[ "$r" = "$l" ] && echo OK || echo "!!! MISMATCH"
```

1. **Read `/dev/mtdN`, the character device — not `/dev/mtdblockN`.** The block
   device goes through the block layer and its cache.
2. **Checksum at both ends.** Hashing only your local copy verifies nothing
   except that a file exists. It is the device-side hash that proves the read
   was faithful.
3. **If NAND bad blocks > 0, `dd` is not enough** — use `nanddump`, which
   includes OOB. ⚠️ **The stock image does not ship `nanddump`** (only the
   `ubi*` tools), so `apk add mtd-utils` first — on releases before 25.x that is
   `opkg install mtd-utils`. With zero bad blocks, `dd` returns ECC-corrected
   data and is sufficient.

## 5. What to back up

| Target | Back up? | Why |
|---|---|---|
| `factory` / `art` | ✅ **first priority** | **Cannot be recreated** |
| bootloader (`bl2*`, `fip*`) | ✅ | Corrupt these and it is a brick |
| `recovery` | ✅ | It is the rescue path itself |
| kernel + rootfs (`fit`) | ✅ **if the board shipped a SNAPSHOT** | Snapshots are deleted upstream and **cannot be downloaded again**. Skip for a numbered release. |
| overlay (`rootfs_data`) | ❌ use `sysupgrade -b` instead | A 219 MB volume typically holding ~64 KB of actual content; restoring a raw ubifs image also means rebuilding the volume |

> ⚠️ **`sysupgrade -b` is not a flash backup.** It never touches mtd and cannot
> save `factory`. But it is exactly the right tool for the overlay. Two
> different jobs, two different tools — you need both.

## 6. Record the way back

A backup exists so you can return. Write down the route:

```sh
ssh root@<ip> 'fw_printenv' > raw/uboot-env.txt
```

Look for three things: the fallback order in `bootcmd`, what the buttons are
bound to, and whether `bootcount` / `altbootcmd` exist.

On the One this reveals the easiest rescue path: **rear button plus a USB stick
with a `*-squashfs-sysupgrade.itb` in the root of a FAT partition rewrites NAND
unattended** — no serial cable, no TFTP server.

⚠️ Do not assume a stock board has `bootcount`-based automatic rollback. On the
One the stock environment has no `bootcount`; `bootcmd` simply tries production
first and falls back to recovery.

---

## Checklist

- [ ] `proc-mtd.txt`, `mtd-sysfs.txt`, `dmesg.txt` **saved as files**, not pasted into a document
- [ ] NAND: `ubinfo-a.txt` saved, and every volume's purpose understood
- [ ] The irreplaceable partition identified via **all three clues**, with a hexdump kept as evidence
- [ ] Every dump has a sha256 from **both the device and the workstation**, and they match
- [ ] A `SHA256SUMS` file sits in the backup directory
- [ ] `fw_printenv` saved and the rescue path written down **somewhere that survives losing the network**
- [ ] Overlay backed up separately with `sysupgrade -b`
