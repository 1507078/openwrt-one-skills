# Configuration backup and restore

**This is not the same thing as a flash backup.** Two different jobs:

| | Tool | Covers | Use when |
|---|---|---|---|
| **Flash backup** | `dd` / `nanddump` on `/dev/mtdN` | Calibration data, MACs, bootloader — the parts that cannot be re-downloaded | Once, before you ever write to flash. See [advanced/FLASH_BACKUP.md](../../../advanced/FLASH_BACKUP.md). |
| **Config backup** | `sysupgrade -b` | Your settings: network, wireless, firewall, users | Before every change, and before every firmware upgrade |

`sysupgrade -b` never touches mtd and cannot save the calibration data. Doing
one does not excuse skipping the other.

---

## Make one

```sh
ssh root@<ip> "sysupgrade -b /tmp/backup-$(date +%F).tar.gz"
scp -O root@<ip>:/tmp/backup-*.tar.gz .        # dropbear has no sftp-server; -O is required
ssh root@<ip> "rm /tmp/backup-*.tar.gz"        # do not leave it on a board you are about to reflash
```

**Get it off the board.** A backup stored on the device you are about to reflash
is not a backup.

## 🚨 Check what it will actually contain

```sh
ssh root@<ip> "sysupgrade -l"
```

This lists every file that would be preserved — `/etc/config/*` plus anything
added to `/etc/sysupgrade.conf`. **Anything not on that list is destroyed by the
next upgrade**, silently and with no warning.

That includes things people routinely add and then lose:

- scripts dropped into `/usr/sbin/`
- init scripts in `/etc/init.d/`
- data files accumulating in `/root/` — logs, CSVs, anything you have been
  collecting over weeks

To keep something, add its path to `/etc/sysupgrade.conf`, then **run
`sysupgrade -l` again and confirm it now appears.** Editing the file is not the
verification; the listing is.

> This failure is not hypothetical and not obvious. A board can have three
> long-running data collectors where only two of the output files were ever
> added to `sysupgrade.conf`. Everything looks fine right up until the upgrade,
> at which point months of one dataset are gone and the other two are intact.
> **Diff the list against what you actually care about, before you need it.**

## Restore

```sh
scp -O backup-YYYY-MM-DD.tar.gz root@<ip>:/tmp/
ssh root@<ip> "sysupgrade -r /tmp/backup-YYYY-MM-DD.tar.gz"
ssh root@<ip> reboot
```

The restore unpacks files; it does not reload running services. **Reboot, then
verify by behaviour** — check that the network came up the way you expected,
not that the config file looks right.

⚠️ **A backup from a different firmware version may not apply cleanly.** Config
formats change between releases, and a restored file the new version does not
understand can leave a service failing to start rather than obviously broken.
Restoring across a version boundary is a thing to do deliberately and then
check, not a routine step.

## From LuCI

**System → Backup / Flash Firmware** does the same thing through the web
interface: "Generate archive" to download, "Upload archive" to restore. Useful
when you want the user to keep a copy themselves without touching a terminal.

## The discipline

- Take one **before** each change, not after.
- Keep the one from **before you started** separately from the rolling ones. It
  is the only way back to a state you know worked.
- Name them by date. `backup.tar.gz` tells you nothing three weeks later.
