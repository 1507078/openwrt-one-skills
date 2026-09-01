---
name: openwrt-one-observe
description: Read what an OpenWrt One is actually doing - airtime use, RF neighbours, thermals, client roaming - and turn it into a report with tuning proposals. Read-only. Use when the user asks why their Wi-Fi is slow, which channel to use, or whether the router is running hot.
---

# Observing an OpenWrt One

Read-only. This skill never changes configuration; it produces a report and
proposals the user can act on.

> Read-only throughout. Nothing here changes configuration.

## What makes this worth doing

Anyone can print `iwinfo`. The value is in the reasoning:

- **Airtime, not throughput.** A channel can be unusable while showing almost
  no traffic of your own, because the neighbours are using it.
- **Neighbour strength, not neighbour count.** Twenty APs at -85 dBm matter
  less than one at -55 dBm.
- **Corroborate across sources.** When you claim the uplink is saturated,
  show a second signal that agrees — Ethernet PAUSE frames, retransmit rates,
  a timeline that lines up.

Do not report a conclusion you have only one measurement for.

## Honest limits

State these rather than working around them:

- **mt76 beacon handling is a hardware black box.** Some things are simply not
  observable on this chipset.
- **The CPU has no DVFS.** There is no throttling step. The only thermal trip
  that acts is critical, and it powers off. Monitoring is the only early
  warning.
- **Syslog retention is short** and depends on what is flooding it. Check what
  the log is actually full of before trusting a window of history.
- **The two radios have their own thermal throttling** even though the CPU does
  not.

## Do not install daemons on the user's router

Produce reports. If the user wants history, give them a cron entry and a CSV
they own. Nothing in this skill should leave a process running on someone
else's hardware.

## "The internet is slow"

The most common request, and the one where guessing is most tempting. There are
six candidate bottlenecks and they fail differently:

```
client radio -> channel airtime -> LAN/switch -> router CPU -> WAN link -> upstream
```

Work down them, measuring at each boundary. Full method, including the two traps
that make queueing silently useless and the two different causes of Ethernet
PAUSE frames: [`references/throughput.md`](references/throughput.md).

## Temperature

```sh
cat /sys/class/thermal/thermal_zone0/temp        # CPU, in millidegrees
for h in /sys/class/hwmon/hwmon*; do echo "$(cat $h/name): $(cat $h/temp1_input 2>/dev/null)"; done
```

⚠️ Look radios up by **`name`** (`mt7915_phy0`, `mt7915_phy1`) rather than by
hwmon number — the numbering is not guaranteed stable across reboots.

🚨 **The CPU has no DVFS, so there is no throttling to observe.** The only
thermal trip that acts is critical, and its action is to power off. There is no
gradual slowdown that warns you first — which is exactly why monitoring is worth
doing here. The two radios do have their own throttling; the CPU does not.

If you report a temperature, report the headroom to the critical trip alongside
it. A number on its own means nothing to the reader.

## Which AP is a device actually on?

In a two-AP household this is the question behind most "roaming is broken"
reports, and it is easy to answer wrongly.

```sh
iw dev phy0-ap0 station dump | grep -E "Station|signal|connected time"
```

⚠️ A device absent from this list is not necessarily gone — **it may be
associated with the other AP**, which has its own station table you have to
check separately. Answer "which AP" before answering "why is it slow".

⚠️ And confirm you are watching the right device. A report of "my tablet keeps
dropping to 2.4 GHz" is worth checking against the actual station dump before
acting on it; it is frequently a different device, and sometimes it is normal
client roaming rather than a fault on either AP.

## Longer-term trends

For anything you want history on, give the user a cron entry and a CSV **they
own**. Do not leave a daemon running on someone else's router.

🚨 **Then add that CSV to `/etc/sysupgrade.conf` and confirm with
`sysupgrade -l`.** A data file collecting for months that was never added to
that list is destroyed by the next upgrade, silently. Editing the file is not
the check; re-reading the listing is.

## Done when

- [ ] Report produced with each claim tied to a specific measurement
- [ ] Limits stated where the data could not answer the question
- [ ] Any proposal marked clearly as a proposal, with the verification step
      that would confirm it worked
