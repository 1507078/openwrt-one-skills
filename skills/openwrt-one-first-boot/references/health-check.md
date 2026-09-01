# Is this board healthy, and what is plugged into it?

A short pass over the things that will bite you later if they are wrong. This is
not a hardware inventory — if you want to know what the SoC is and how the flash
is partitioned, that is
[`advanced/BOARD_BRINGUP.md`](../../../advanced/BOARD_BRINGUP.md).

**Ask the board, not the datasheet.** The spec sheet says what the hardware
*can* do; the board says what is wired up and what this firmware enabled.

---

## What is it, and what is it running

```sh
ubus call system board
cat /etc/openwrt_release
```

Confirm `board_name` is `openwrt,one` and that `DISTRIB_RELEASE` is a number
rather than `SNAPSHOT`.

## 🚨 The clock

```sh
date
```

The board has an RTC, but it commonly ships **without a working battery** —
`dmesg | grep -i rtc` will say `low voltage detected, date/time is not
reliable`. When that is the case the system time starts at the firmware build
date and stays wrong until something sets it.

This is not cosmetic. **Every log entry you collect from now on is stamped with
that wrong time**, which makes correlating anything — with your own notes, with
an outage, with the other AP — impossible after the fact.

Fix it before you rely on any log:

```sh
uci set system.@system[0].timezone='<your TZ>'
uci set system.@system[0].zonename='<Region/City>'
uci commit system && /etc/init.d/system restart
/etc/init.d/sysntpd restart && sleep 3 && date
```

## Network ports

```sh
for i in $(ls /sys/class/net | grep -E '^(eth|lan|wan)'); do
  echo "$i: carrier=$(cat /sys/class/net/$i/carrier 2>/dev/null) speed=$(cat /sys/class/net/$i/speed 2>/dev/null)"
done
```

`carrier=0` means nothing is plugged in. **A gigabit port that negotiated 100
Mbps is a cable or a socket**, and it is invisible until you look — it will
later present as "the internet is slow" with no other symptom.

## Temperature

```sh
cat /sys/class/thermal/thermal_zone0/temp     # millidegrees; 62000 = 62 °C
```

Somewhere in the 50s to 60s °C at idle is normal for this board.

🚨 **There is no frequency scaling on this CPU**, so there is no gradual
slowdown when it gets hot. The only thermal trip that acts is critical, and its
action is to power the board off. There is no warning stage — which is exactly
why the number is worth watching if the board lives somewhere warm or enclosed.

## Radios

```sh
iwinfo
iw reg get        # regulatory domain -- decides which channels are legal
```

Two radios, `phy0` (2.4 GHz) and `phy1` (5 GHz). The regulatory domain is yours
to set correctly for where you live; the skills will not change it for you.

## Write down what was *not* there

"No SD card slot in use", "PCIe slot empty", "no cpufreq". **Absent and
not-checked look identical in notes six months later.** Recording the zeroes is
what makes the notes worth having.
