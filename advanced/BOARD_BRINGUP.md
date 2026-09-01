# Board bring-up: full hardware inventory

> Engineering depth, kept out of the main skills on purpose. Nothing here is
> needed to run an OpenWrt One as a home router — it is for people bringing up
> a board, debugging one, or writing about the hardware.
>
> The health check the skills actually use is in
> [`../skills/openwrt-one-first-boot/SKILL.md`](../skills/openwrt-one-first-boot/SKILL.md).

Ask the board what it is. Do not quote the datasheet.

The spec sheet says what the SoC *can* do. The board says what is actually
wired up and what this firmware enabled. They differ more often than not, and
the second one is what the user has to live with.

Save every command's raw output to a file. A table you typed into a document is
a table you edited — it will be missing the column that turns out to matter.

---

## CPU

`/proc/cpuinfo` on ARM gives you neither the model name nor the frequency. It
gives MIDR fields, which you decode yourself:

```sh
grep -E "processor|BogoMIPS|CPU (implementer|part|revision)" /proc/cpuinfo
nproc
```

```
CPU implementer : 0x41   -> ARM Ltd.
CPU part        : 0xd03  -> Cortex-A53   (0xd07=A57 0xd08=A72 0xd0b=A76 ...)
CPU revision    : 4      -> r0p4
processor       : 0,1    -> 2 cores
```

> 🚨 **BogoMIPS is not the clock speed.** On the One it reads `26.00` while the
> CPU runs at 1.3 GHz. `dmesg` explains why:
> `Calibrating delay loop (skipped), value calculated using timer frequency`.
> Modern ARM64 derives it from the 13 MHz architected timer — `26.00 = 13 × 2` —
> and it has nothing to do with how fast the cores run. **Any reasoning from
> BogoMIPS to clock speed is wrong.**

For the real frequency, try three sources in order:

| Source | Command | On the One |
|---|---|---|
| cpufreq (only exists with DVFS) | `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq` | ❌ no such directory → **no DVFS, fixed clock** |
| ⭐ debugfs clock tree | `grep -iE "cpu\|armpll" /sys/kernel/debug/clk/clk_summary` | ✅ `armpll … 1300000000` → **1.3 GHz** |
| devicetree | `hexdump -e '1/4 "%d"' /sys/firmware/devicetree/base/cpus/cpu@0/clock-frequency` | ❌ property absent |

`clk_summary` is the one to trust: it is the value the kernel is using right
now, and it shows the other clocks too.

**No DVFS matters later.** It means there is no throttling step when the board
gets hot — see the thermal note below.

## Memory

```sh
head -2 /proc/meminfo
dmesg | grep -i "Memory:"
```

```
MemTotal: 1010928 kB                                    <- what the kernel can use
Memory: 1010480K/1048576K available (... 38096K reserved)
                    ^^^^^^^ 1 GiB is what is fitted
```

The difference is kernel reservation. **Quote the fitted size in specs; look at
`MemTotal` only when investigating memory pressure.**

## Flash

Chip part number and true capacity appear only in `dmesg`:

```sh
dmesg | grep -iE "spi-nor|spi-nand|mtd"
```

```
spi-nor  spi0.0: w25q128 (16384 Kbytes)                                   <- NOR 16 MB
spi-nand spi1.1: 256 MiB, block size: 128 KiB, page size: 2048, OOB: 128  <- NAND 256 MB
```

⚠️ **Partitions do not have to add up to the chip.** On the One, NOR partitions
stop at `0xE00000`, leaving roughly 2 MB at the end with no mtd node pointing at
it — unreadable, and impossible to back up. Record gaps like that when you find
them; they are invisible later.

## IO sweep

```sh
ls /sys/class/net /sys/class/leds /sys/class/i2c-dev /sys/class/mmc_host /sys/class/input
ls /sys/bus/usb/devices /sys/bus/pci/devices
for u in /sys/bus/usb/devices/usb*; do echo "$(basename $u) $(cat $u/version) speed=$(cat $u/speed)"; done
for g in /sys/class/gpio/gpiochip*; do echo "$(cat $g/label) ngpio=$(cat $g/ngpio)"; done
for t in /sys/class/thermal/thermal_zone*; do echo "$(cat $t/type) $(cat $t/temp)"; done
ls /dev/watchdog* /dev/ttyS*
```

What the One reports:

| IO | Result |
|---|---|
| 2.5G WAN `eth0` | PHY = **Airoha EN8811H**, `2500base-x`, with **MD32 firmware inside the PHY**. Record the firmware version — it affects link behaviour. |
| 1G LAN `eth1` | `speed=1000 carrier=1` |
| USB | `usb1` = 2.00/480, `usb2` = 3.10/20000 (⚠️ trap 1) |
| PCIe (M.2) | `link down … probe failed -110`, `pci devices: 0` → **empty slot** (⚠️ trap 2) |
| SD/MMC | none |
| I2C | `i2c-0` (scan with `apk add i2c-tools` then `i2cdetect -y 0`) |
| GPIO | `pinctrl_moore ngpio=57`; named exports `mikrobus-reset`, `usb-enable`, `watchdog-enable` → **there is a mikroBUS header** |
| LEDs | 9, including two WAN LEDs hanging off the PHY (`mdio-bus:0f:*:wan`) |
| RTC | `rtc-pcf8563` at i2c `0x51` — but typically `low voltage detected, date/time is not reliable`, i.e. **no battery fitted**. System time sits at the firmware build date. |
| Thermal | `cpu-thermal`, around 55 °C idle on the bench |
| Watchdog | **two** (⚠️ trap 3) |
| UART | `ttyS0/1/2` |
| Wi-Fi | `phy0`, `phy1` |

> 🚨 **The RTC one is not cosmetic.** With no battery, every log timestamp is
> wrong until something sets the clock. Fix it, or know that your logs cannot be
> correlated with anything.

## Four things only the boot console has

`dmesg` starts at the kernel. **BootROM → BL2 → BL31 → U-Boot exist only on the
serial line**, and they are gone once you reboot. So record one full boot:

```sh
screen -L -Logfile boot-console.log /dev/cu.usbmodemXXXX 115200   # start capture
ssh root@<ip> reboot                                              # trigger from another window
perl -pe 's/\e\[[0-9;?]*[A-Za-z]//g; s/\r//g' boot-console.log > boot-console.clean.log
```

| Only in the boot log | Example | Why it matters |
|---|---|---|
| CPU frequency | `CPU: MT7981 (1300MHz)` | Printed by the bootloader — an independent check on `clk_summary` |
| DRAM size + training result | `EMI: Detected DRAM size: 1024MB` | More authoritative than `MemTotal`, nothing subtracted yet |
| 🚨 **Why it rebooted last time** | `WDT: [40000000] Software reset (reboot)` | Distinguishes a software reboot from a watchdog bite from a power cut. **Unavailable once Linux is up — the first thing to look at when debugging.** |
| Bootloader variant | TF-A `mt7981-spim-nand-ubi-ddr4` | Says which boot medium and memory type it was built for |

Keep the boot menu text too. ⚠️ **The menu differs depending on which medium
booted** — the NAND menu does not contain the NOR entries. Do not assume the
menu in front of you is the one in the wiki.

## Three things people misread

**1. A root hub reporting 3.10 / 20 Gbps does not mean the connector is USB 3.**
That is the xHCI controller's capability. It says nothing about whether the
SuperSpeed pairs were routed to the socket. **Plug in a USB 3 stick and check
`speed` before believing it.**

**2. PCIe `probe failed -110` is not a fault — the M.2 slot is empty.** This is
the correct baseline for an empty slot. Write it down now, so that when a card
does go in and nothing happens, you can tell "the card is bad" from "it has
always looked like this".

**3. There is more than one watchdog, and which one is in service is a separate
question.**

```sh
for w in /sys/class/watchdog/watchdog*; do
  echo "$(basename $w): $(cat $w/identity) state=$(cat $w/state) timeout=$(cat $w/timeout)"; done
ubus call system watchdog        # who is feeding it, how often
```

```
watchdog0: GPIO Watchdog  state=active    timeout=30   <- separate chip, procd feeds it every 5 s
watchdog1: mtk-wdt        state=inactive  timeout=31   <- inside the SoC, nobody feeding it
/dev/watchdog (10,130)                                  <- legacy node, points at watchdog0
```

The difference is the whole point: **`gpio-watchdog` is a physical chip outside
the SoC.** If the SoC hangs completely it still resets the board. `mtk-wdt` is
inside the SoC and cannot reliably rescue it. This is a large part of why the
One is hard to brick.

> 🚨 **Stop the watchdog before kernel tracing or stress tests.** A 30-second
> hang reboots the board and takes your trace with it:
> ```sh
> ubus call system watchdog '{"magicclose":true}'
> ubus call system watchdog '{"stop":true}'   # {"stop":false} when you are done
> ```

**Bonus:** Linux registers no input devices at all — `/sys/class/input/` is
empty. But U-Boot's `check_buttons` uses both buttons. **The buttons are a
bootloader feature; do not go looking for them in Linux.**

## Write down what was not there

`mmc_host: 0`, `pci devices: 0`, `cpufreq: no nodes`.

**"Absent" and "not checked" look identical in notes six months later.** Record
the zeroes so the next reader knows it was a conclusion, not an omission.

## Finally, compare against the published spec

An inventory you never checked against the datasheet is half an inventory. The
differences *are* the todo list, and all three kinds need handling:

| Outcome | Example on the One | What to do |
|---|---|---|
| **Measured < spec** (usually you misread) | Spec says 5 GHz **3×3**; `iw` reports 2 streams. Reading the driver resolves it: 3×3 counts RF chains, `Available Antennas` counts spatial streams. 3T3R with 2 spatial streams — **both statements are correct.** | ⚠️ Assume you have not understood it yet. Chase it to the source or the EEPROM before concluding. Declaring the spec wrong is usually the wrong call. |
| **Measured > spec** | The spec never mentions watchdogs; the board has two. It does not name the 2.5G PHY either. | ⭐ This is your information advantage. Write it down. |
| **In the spec, dead on the board** | RTC present, battery flat | 🔧 Becomes a task immediately — otherwise every timestamp you collect is wrong |

The published documentation also carries things the board cannot tell you:
hardware write-protect jumper location and sequence, PoE ratings, what
filesystem the recovery USB stick needs. **Read both.**

---

## Checklist

- [ ] CPU: core count, microarchitecture, **real frequency** (`clk_summary`, *not* BogoMIPS), DVFS present or not
- [ ] Memory: **fitted** size from dmesg, not just `MemTotal`
- [ ] Flash: part number and true capacity, **compared against the partition total, gaps recorded**
- [ ] IO table: network (with PHY part and firmware version), USB, PCIe, MMC, I2C, GPIO, LED, thermal, UART
- [ ] Watchdog: how many, which is active, who feeds it, timeout, and how to stop it for debugging
- [ ] RTC: present, and **is the battery alive**
- [ ] Items that were **absent** are written down as absent
- [ ] ⭐ One full boot captured, including reset reason and boot menu
- [ ] ⭐ Measurements compared against the published spec, with a conclusion or a task for every difference
