# The USB-C console

The single most important thing about this board for anyone letting an agent
touch it: **there is a way in that does not depend on the network.**

Everything else in these skills is written on the assumption that you can fall
back to this. Set it up on day one, while nothing is broken.

---

## Connecting

**Front USB-C, not the rear one.** The rear port is power. Plugging the console
cable into it is the most common first mistake, and it looks exactly like a dead
console.

It enumerates as a USB CDC-ACM serial device. **No driver, no adapter, no
soldering** — the USB-to-serial bridge is on the board.

```sh
# macOS
ls /dev/cu.usbmodem*
screen /dev/cu.usbmodem00001 115200

# Linux
ls /dev/ttyACM*
screen /dev/ttyACM0 115200
```

115200 8N1. To leave `screen`: `Ctrl-A` then `k`, confirm with `y`.

If the device node does not appear at all, it is the cable or the port — a
charge-only USB-C cable has no data lines and is indistinguishable from a broken
console until you swap it.

## 🚨 It gives a root shell with no password — and a root password does not change that

Press enter and you are root. No login, no key, nothing.

**Setting a root password does not close the console.** People assume it does.
The logic is in `/usr/libexec/login.sh`, and it is explicit:

```sh
[ "$(uci -q get system.@system[0].ttylogin)" = 1 ] || exec /bin/login -f root
exec /bin/login
```

`ttylogin` is unset by default, so the console takes the first branch —
`login -f root`, where `-f` means *force this login without authenticating*.
That happens whether or not root has a password.

So the two doors close separately:

| Door | Closed by |
|---|---|
| ssh and LuCI | setting a root password |
| serial console | `uci set system.@system[0].ttylogin=1` |

**This is a trade, not an oversight.** The passwordless console is precisely
what makes this board recoverable — it is the way back in when the network
config is wrong, when a flash went badly, when nothing else answers. Turning on
`ttylogin` closes that door too, and then a forgotten password means the
recovery path needs a firmware rewrite instead of a cable.

Decide it deliberately:

- **Board at home, on a shelf** — leave it open. The rescue path is worth more
  than the threat.
- **Board anywhere people you do not know can reach it** — set `ttylogin=1`,
  and make sure the password is somewhere you will still have it in a year.

Either way, say it out loud to the user. **Physical access to this board is
total access**, and they should know that rather than discover it.

## What it is for

**1. Recovery when the network is gone.** The reason it exists. If a config
change takes the LAN down, the WAN misconfiguration cuts you off, or a flash
leaves the board unreachable, this still works. Nothing in the network stack has
to be functioning.

**2. Watching the boot.** `dmesg` starts at the kernel. BootROM, BL2, BL31 and
U-Boot exist **only** on this line, and only while they are running.

⭐ **The reason for the previous reboot is here and nowhere else** — a line like
`WDT: [40000000] Software reset (reboot)` distinguishes a clean reboot from a
watchdog bite from a power cut. Once Linux is up, that information is gone. When
a board reboots unexpectedly, this is the first thing to look at.

[`advanced/BOARD_BRINGUP.md`](../../../advanced/BOARD_BRINGUP.md) has the capture
recipe and the other three things only the boot log carries.

**3. Reaching the bootloader.** Interrupting boot gets you the U-Boot menu, which
is where recovery images get loaded. ⚠️ **The menu differs depending on which
medium booted** — the NAND menu does not contain the NOR entries. Do not assume
the menu you are looking at matches the one in the wiki.

## Prove it before you need it

"The cable is in the box" is not a working console. Before making any change
that can take the network down, the user should have **seen characters come out
of it while everything still worked.**

The check is one line:

```sh
ls /dev/cu.usbmodem* /dev/ttyACM* 2>/dev/null && echo "device node present"
```

Then open it, press enter, and confirm a prompt appears. A console you have
never opened is a console you are assuming, and the moment you need it is the
worst moment to find out the cable is charge-only.

> When debugging the kernel, stop the watchdog first or a hang will reboot the
> board and take your session with it — see
> [`advanced/BOARD_BRINGUP.md`](../../../advanced/BOARD_BRINGUP.md).
